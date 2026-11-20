-- Fleet Operations migration smoke assertions.
-- Run after steadyfix_fleet_operations.sql in a Supabase SQL Editor session.
do $$
declare
  expected text[] := array['fleet_drivers','fleet_inspections','fleet_defects','fleet_fuel_logs','fleet_tyre_records','fleet_compliance_items','fleet_downtime_events'];
  missing text[];
  no_rls text[];
  no_policy text[];
  no_grant text[];
begin
  select array_agg(x) into missing from unnest(expected) x
    where not exists (select 1 from information_schema.tables t where t.table_schema='public' and t.table_name=x);
  if coalesce(array_length(missing,1),0)>0 then raise exception 'Missing Fleet Operations tables: %',missing; end if;

  select array_agg(x) into no_rls from unnest(expected) x
    where not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                     where n.nspname='public' and c.relname=x and c.relrowsecurity);
  if coalesce(array_length(no_rls,1),0)>0 then raise exception 'RLS not enabled on: %',no_rls; end if;

  select array_agg(x) into no_policy from unnest(expected) x
    where not exists (select 1 from pg_policies p where p.schemaname='public' and p.tablename=x and p.policyname='fleet_tenant_site');
  if coalesce(array_length(no_policy,1),0)>0 then raise exception 'Tenant/site policy missing on: %',no_policy; end if;

  select array_agg(x) into no_grant from unnest(expected) x
    where not has_table_privilege('authenticated','public.'||x,'select')
       or not has_table_privilege('authenticated','public.'||x,'insert')
       or not has_table_privilege('authenticated','public.'||x,'update')
       or not has_table_privilege('authenticated','public.'||x,'delete');
  if coalesce(array_length(no_grant,1),0)>0 then raise exception 'Authenticated table privileges missing on: %',no_grant; end if;

  raise notice 'Fleet Operations smoke assertions passed for all 7 tables.';
end $$;
