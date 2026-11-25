-- Company-wide live operational sync for the shared web and desktop CMMS.
-- Only tenant-scoped tables with RLS and a company_id column are published.
begin;

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
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime publication is not present; skipping live table registration';
    return;
  end if;

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
    ) and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end $$;

commit;
