#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL must point to disposable PostgreSQL test database}"
PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -X)
# Quote-conversion regression runs first and supplies reusable auth roles/functions.
"${PSQL[@]}" <<'SQL'
create schema if not exists private;
create table public.sites(id uuid primary key,company_id uuid not null);
create table public.stock_items(id uuid primary key,company_id uuid not null);
create table public.stock_levels(item_id uuid not null,site_id uuid not null,company_id uuid not null,on_hand numeric not null,unique(item_id,site_id));
insert into sites values ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001');
insert into stock_items values ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001');
insert into stock_levels values ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',100);
SQL
"${PSQL[@]}" -f supabase/migrations/20261123170000_atomic_stock_adjustments.sql
# Two independent authenticated sessions adjust a single item concurrently.
for delta in 10 20; do
  ("${PSQL[@]}" -c "set role authenticated; set test.user_id='00000000-0000-0000-0000-000000000004'; set test.company_id='00000000-0000-0000-0000-000000000001'; set test.role='manager'; set test.site_id='00000000-0000-0000-0000-000000000002'; select public.adjust_stock_level('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002',$delta,null);" ) &
done
wait
actual="$("${PSQL[@]}" -Atc "select on_hand from public.stock_levels where item_id='00000000-0000-0000-0000-000000000003'")"
[[ "$actual" == "130" ]] || { echo "Concurrent increments lost: expected 130, got $actual"; exit 1; }
# Underflow must fail and leave the balance unchanged.
if "${PSQL[@]}" -c "set role authenticated; set test.user_id='00000000-0000-0000-0000-000000000004'; set test.company_id='00000000-0000-0000-0000-000000000001'; set test.role='manager'; set test.site_id='00000000-0000-0000-0000-000000000002'; select public.adjust_stock_level('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002',-131,null);" >/tmp/stock-adjustment-negative.log 2>&1; then
  echo "Expected negative-stock adjustment rejection"; exit 1
fi
actual="$("${PSQL[@]}" -Atc "select on_hand from public.stock_levels where item_id='00000000-0000-0000-0000-000000000003'")"
[[ "$actual" == "130" ]] || { echo "Rejected adjustment mutated balance: $actual"; exit 1; }
echo "Concurrent stock adjustment PostgreSQL regression: PASS"
