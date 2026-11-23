#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL must point to disposable PostgreSQL test database}"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
create role authenticated;
create role anon;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create or replace function public.auth_company() returns uuid language sql stable as $$ select nullif(current_setting('test.company',true),'')::uuid $$;
create or replace function public.auth_role() returns text language sql stable as $$ select coalesce(current_setting('test.role',true),'') $$;
create or replace function public.auth_site_ok(uuid) returns boolean language sql stable as $$ select true $$;
create table public.sites(id uuid primary key,company_id uuid not null);
create table public.stock_items(id uuid primary key,company_id uuid not null);
create table public.stock_levels(item_id uuid not null,site_id uuid not null,company_id uuid not null,on_hand numeric not null,unique(item_id,site_id));
insert into sites values ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001');
insert into stock_items values ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001');
insert into stock_levels values ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',100);
SQL
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261122173000_atomic_stock_adjustments.sql
# Use separate sessions, each authenticated with same company/site context, to exercise lock-based updates.
for delta in 10 20; do
  (psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
set test.company='00000000-0000-0000-0000-000000000001';
set test.role='manager';
select public.adjust_stock_level('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002',$delta,null);
SQL
  ) &
done
wait
# Both increments must be retained, not overwritten by a stale absolute update.
actual=$(psql "$DATABASE_URL" -Atc "select on_hand from public.stock_levels where item_id='00000000-0000-0000-0000-000000000003'")
[[ "$actual" == "130" ]] || { echo "Concurrent increments lost: expected 130, got $actual"; exit 1; }
# Negative resulting balance is rejected and leaves balance unchanged.
if psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
set test.company='00000000-0000-0000-0000-000000000001';
set test.role='manager';
select public.adjust_stock_level('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002',-131,null);
SQL
then echo "Expected negative-stock adjustment rejection"; exit 1; fi
actual=$(psql "$DATABASE_URL" -Atc "select on_hand from public.stock_levels where item_id='00000000-0000-0000-0000-000000000003'")
[[ "$actual" == "130" ]] || { echo "Rejected adjustment mutated balance: $actual"; exit 1; }
echo "Concurrent stock adjustment PostgreSQL regression: PASS"
