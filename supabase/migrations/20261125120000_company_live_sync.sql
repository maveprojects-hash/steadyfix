-- Company-wide live operational sync using minimal tenant-private Broadcast events.
-- The database emits only a table/operation invalidation; clients reload rows via RLS.
begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.broadcast_cmms_company_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, realtime
as $$
declare
  v_company_id uuid;
begin
  if tg_op = 'DELETE' then
    v_company_id := old.company_id;
  else
    v_company_id := new.company_id;
  end if;

  if v_company_id is null then
    return null;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'company_id', v_company_id,
      'table', tg_table_name,
      'operation', tg_op
    ),
    'cmms_change',
    'company:' || v_company_id::text || ':cmms-live',
    true
  );
  return null;
end;
$$;

revoke all on function private.broadcast_cmms_company_change() from public, anon, authenticated;

-- A client may join only the private live channel belonging to its active company.
drop policy if exists cmms_company_live_sync_read on realtime.messages;
create policy cmms_company_live_sync_read
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and split_part((select realtime.topic()), ':', 2) = (select public.auth_company())::text
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.company_id = (select public.auth_company())
        and p.active = true
    )
  );

do $$
declare
  v_table text;
  v_tables text[] := array[
    'work_orders','pm_schedules','stock_items','purchase_orders','shutdowns',
    'sensors','assets','shifts','budgets','expenses','customers','suppliers',
    'damage_reports','ohs_inspections','ohs_hazards','ohs_incidents','ohs_ppe',
    'ohs_training','ohs_regs','fire_equipment','fire_inspections','vehicles',
    'workshop_jobs','work_order_time_entries','work_order_material_issues',
    'work_order_customer_signoffs','logistics_shipments','logistics_tracking_events',
    'logistics_pod_signoffs','documents'
  ];
begin
  foreach v_table in array v_tables loop
    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attname = 'company_id'
        and a.attnum > 0 and not a.attisdropped
      where n.nspname = 'public'
        and c.relname = v_table
        and c.relkind in ('r','p')
        and c.relrowsecurity
    ) then
      execute format('drop trigger if exists cmms_company_live_change on public.%I', v_table);
      execute format(
        'create trigger cmms_company_live_change after insert or update or delete on public.%I for each row execute function private.broadcast_cmms_company_change()',
        v_table
      );
    end if;
  end loop;
end $$;

commit;
