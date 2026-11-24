#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must point to the PostgreSQL CI service}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -X)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Minimal schema/auth fixture to exercise the real conversion migration in PostgreSQL.
"${PSQL[@]}" <<'SQL'
create role anon nologin;
create role authenticated nologin;
create schema auth;
grant usage on schema auth to authenticated;
create or replace function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('test.user_id', true),'')::uuid $$;
create or replace function public.auth_company() returns uuid language sql stable as
  $$ select nullif(current_setting('test.company_id', true),'')::uuid $$;
create or replace function public.auth_role() returns text language sql stable as
  $$ select current_setting('test.role', true) $$;
create or replace function public.auth_site_ok(p_site_id uuid) returns boolean language sql stable as
  $$ select p_site_id = nullif(current_setting('test.site_id', true),'')::uuid $$;

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  site_id uuid,
  kind text not null,
  number text not null,
  customer_id uuid,
  customer_name text,
  issue_date date,
  due_date date,
  status text,
  currency text,
  vat_rate numeric,
  lines jsonb,
  notes text,
  subtotal numeric,
  vat_amount numeric,
  total numeric,
  converted_from uuid,
  reference text,
  sales_rep text,
  discount_pct numeric,
  discount_amount numeric,
  paid_amount numeric default 0
);
grant select, insert, update on public.documents to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function public.auth_company() to authenticated;
grant execute on function public.auth_role() to authenticated;
grant execute on function public.auth_site_ok(uuid) to authenticated;

-- Exercise the RPC as an invoker under RLS, matching the live documents policy shape.
create or replace function public.company_subscription_access() returns boolean
language sql stable as $$ select true $$;
grant execute on function public.company_subscription_access() to authenticated;
alter table public.documents enable row level security;
create policy docs_mgr on public.documents for all to public
  using (company_id = public.auth_company() and public.auth_role() in ('owner','manager'))
  with check (company_id = public.auth_company() and public.auth_role() in ('owner','manager'));
create policy subscription_entitlement_gate on public.documents for all to authenticated
  using (public.company_subscription_access())
  with check (public.company_subscription_access());
SQL

# Apply the actual uniqueness migration from PR #25 and the new atomic RPC migration.
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261120130000_invoice_quote_conversion_unique.sql"
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261120150000_company_document_number_unique.sql"
"${PSQL[@]}" -f "$ROOT/supabase/migrations/20261123110000_quote_conversion_atomic_rpc.sql"

COMPANY='11111111-1111-4111-8111-111111111111'
OTHER_COMPANY='22222222-2222-4222-8222-222222222222'
SITE='33333333-3333-4333-8333-333333333333'
OTHER_SITE='44444444-4444-4444-8444-444444444444'
USER='55555555-5555-4555-8555-555555555555'
Q1='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
Q2='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
Q3='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
Q4='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
Q5='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'

"${PSQL[@]}" <<SQL
insert into public.documents(id,company_id,site_id,kind,number,customer_name,status,currency,vat_rate,lines,subtotal,vat_amount,total,discount_pct,discount_amount,paid_amount)
values
 ('$Q1','$COMPANY','$SITE','quote','Q-001','Test customer','draft','ZAR',15,'[]',100,15,115,0,0,0),
 ('$Q2','$COMPANY','$SITE','quote','Q-002','Test customer','draft','ZAR',15,'[]',100,15,115,0,0,0),
 ('$Q3','$COMPANY','$SITE','quote','Q-003','Test customer','draft','ZAR',15,'[]',100,15,115,0,0,0),
 ('$Q4','$OTHER_COMPANY','$SITE','quote','Q-004','Other tenant','draft','ZAR',15,'[]',100,15,115,0,0,0),
 ('$Q5','$COMPANY','$OTHER_SITE','quote','Q-005','Other site','draft','ZAR',15,'[]',100,15,115,0,0,0);
SQL

auth_call() {
  local quote="$1" number="$2"
  "${PSQL[@]}" -c "set role authenticated; set test.user_id='$USER'; set test.company_id='$COMPANY'; set test.role='owner'; set test.site_id='$SITE'; select public.convert_quote_to_invoice('$quote','$number');"
}

# Missing/null role must fail closed (SQL NULL must not bypass NOT IN authorization).
auth_call_without_role() {
  local quote="$1" number="$2"
  "${PSQL[@]}" -c "set role authenticated; set test.user_id='$USER'; set test.company_id='$COMPANY'; set test.site_id='$SITE'; select public.convert_quote_to_invoice('$quote','$number');"
}

# First conversion and repeat request: exactly one invoice, second response idempotent.
first="$(auth_call "$Q1" "INV-001")"
second="$(auth_call "$Q1" "INV-RETRY")"
grep -q '"already_converted": false' <<<"$first"
grep -q '"already_converted": true' <<<"$second"
count="$("${PSQL[@]}" -Atc "select count(*) from public.documents where kind='invoice' and converted_from='$Q1'")"
status="$("${PSQL[@]}" -Atc "select status from public.documents where id='$Q1'")"
[[ "$count" == "1" && "$status" == "accepted" ]]

# Two concurrent requests for the same quote serialize on the quote row and cannot duplicate.
auth_call "$Q2" "INV-002A" >"$TMP/a" 2>&1 &
pid_a=$!
auth_call "$Q2" "INV-002B" >"$TMP/b" 2>&1 &
pid_b=$!
wait "$pid_a"
wait "$pid_b"
grep -q '"already_converted": false' "$TMP/a" "$TMP/b"
grep -q '"already_converted": true' "$TMP/a" "$TMP/b"
count="$("${PSQL[@]}" -Atc "select count(*) from public.documents where kind='invoice' and converted_from='$Q2'")"
[[ "$count" == "1" ]]

# A conflicting invoice number aborts conversion atomically; the quote stays draft and no linked invoice exists.
"${PSQL[@]}" <<SQL
insert into public.documents(company_id,site_id,kind,number,customer_name,status,currency,vat_rate,lines,subtotal,vat_amount,total,paid_amount)
values ('$COMPANY','$SITE','invoice','INV-FAIL','Existing','draft','ZAR',15,'[]',1,0.15,1.15,0);
SQL
if auth_call "$Q3" "INV-FAIL" >"$TMP/fail" 2>&1; then
  echo "Expected invoice-number conflict to fail" >&2
  exit 1
fi
status="$("${PSQL[@]}" -Atc "select status from public.documents where id='$Q3'")"
count="$("${PSQL[@]}" -Atc "select count(*) from public.documents where kind='invoice' and converted_from='$Q3'")"
[[ "$status" == "draft" && "$count" == "0" ]]

# Tenant and site guards reject conversion of quotes outside the caller's scope.
if auth_call_without_role "$Q5" "INV-NO-ROLE" >"$TMP/no-role" 2>&1; then
  echo "Expected missing-role authorization to fail closed" >&2
  exit 1
fi
# Failed authorization must leave source quote untouched and create no invoice.
status="$("${PSQL[@]}" -Atc "select status from public.documents where id='$Q5'")"
count="$("${PSQL[@]}" -Atc "select count(*) from public.documents where kind='invoice' and converted_from='$Q5'")"
[[ "$status" == "draft" && "$count" == "0" ]]
if auth_call "$Q4" "INV-004" >"$TMP/tenant" 2>&1; then
  echo "Expected tenant-scoped quote lookup to fail" >&2
  exit 1
fi
if auth_call "$Q5" "INV-005" >"$TMP/site" 2>&1; then
  echo "Expected site authorization guard to fail" >&2
  exit 1
fi
echo "Quote conversion PostgreSQL regression: PASS (idempotency, concurrency, rollback, missing-role, tenant/site guards)"
