-- STEADYFIX Fleet Operations Foundation
-- Additive migration: daily inspections, defect records, fuel, tyres, compliance and downtime.
-- Run in Supabase SQL Editor after steadyfix_fleet_workshop.sql.
-- This migration creates company/site-scoped tables only; it does not alter live vehicle/job data.

create table if not exists fleet_drivers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  created_at timestamptz not null default now(),
  full_name text not null,
  employee_ref text,
  phone text,
  licence_number text,
  licence_class text,
  licence_expiry date,
  active boolean not null default true,
  notes text
);
create index if not exists fleet_drivers_co_site_active on fleet_drivers(company_id,site_id,active);

create table if not exists fleet_inspections (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  driver_id uuid references fleet_drivers(id) on delete set null,
  created_at timestamptz not null default now(),
  inspection_type text not null check (inspection_type in ('pre_trip','post_trip','weekly','ad_hoc')),
  inspected_at timestamptz not null default now(),
  odometer_km numeric check (odometer_km is null or odometer_km >= 0),
  result text not null default 'pass' check (result in ('pass','fail','needs_attention')),
  checklist jsonb not null default '[]'::jsonb check (jsonb_typeof(checklist)='array'),
  notes text,
  submitted_by uuid
);
create index if not exists fleet_inspections_co_site_vehicle_time on fleet_inspections(company_id,site_id,vehicle_id,inspected_at desc);

create table if not exists fleet_defects (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  inspection_id uuid references fleet_inspections(id) on delete set null,
  created_at timestamptz not null default now(),
  reported_at timestamptz not null default now(),
  reported_by uuid,
  category text not null check (category in ('safety','tyres','brakes','engine','electrical','body','documents','other')),
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  description text not null,
  status text not null default 'open' check (status in ('open','assigned','work_order','resolved','closed')),
  work_order_id uuid references work_orders(id) on delete set null,
  resolved_at timestamptz,
  resolution_notes text
);
create index if not exists fleet_defects_co_site_status on fleet_defects(company_id,site_id,status,severity);

create table if not exists fleet_fuel_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  driver_id uuid references fleet_drivers(id) on delete set null,
  created_at timestamptz not null default now(),
  fuel_date timestamptz not null default now(),
  odometer_km numeric not null check (odometer_km >= 0),
  litres numeric not null check (litres > 0),
  total_cost numeric not null check (total_cost >= 0),
  vendor text,
  receipt_ref text,
  notes text
);
create index if not exists fleet_fuel_co_site_vehicle_date on fleet_fuel_logs(company_id,site_id,vehicle_id,fuel_date desc);

create table if not exists fleet_tyre_records (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  created_at timestamptz not null default now(),
  action text not null check (action in ('fit','remove','rotate','inspect','replace')),
  tyre_position text not null check (tyre_position in ('front_left','front_right','rear_left','rear_right','spare','other')),
  brand text,
  serial_number text,
  tread_depth_mm numeric check (tread_depth_mm is null or tread_depth_mm >= 0),
  tyre_size text,
  performed_at timestamptz not null default now(),
  odometer_km numeric check (odometer_km is null or odometer_km >= 0),
  notes text
);
create index if not exists fleet_tyre_co_site_vehicle_time on fleet_tyre_records(company_id,site_id,vehicle_id,performed_at desc);

create table if not exists fleet_compliance_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  created_at timestamptz not null default now(),
  document_type text not null check (document_type in ('registration','insurance','roadworthy','permit','operator_licence','other')),
  document_ref text,
  issuer text,
  issued_on date,
  expires_on date,
  status text not null default 'valid' check (status in ('valid','pending','expired','cancelled')),
  notes text
);
create index if not exists fleet_compliance_co_site_expiry on fleet_compliance_items(company_id,site_id,expires_on,status);

create table if not exists fleet_downtime_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  work_order_id uuid references work_orders(id) on delete set null,
  created_at timestamptz not null default now(),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  reason text not null,
  notes text,
  check (ended_at is null or ended_at >= started_at)
);
create index if not exists fleet_downtime_co_site_vehicle on fleet_downtime_events(company_id,site_id,vehicle_id,started_at desc);

-- Tenant and site boundaries on every new table.
do $$
declare t text;
begin
  foreach t in array array[
    'fleet_drivers','fleet_inspections','fleet_defects','fleet_fuel_logs',
    'fleet_tyre_records','fleet_compliance_items','fleet_downtime_events'
  ] loop
    execute format('alter table %I enable row level security',t);
    execute format('drop policy if exists fleet_tenant_site on %I',t);
    execute format('create policy fleet_tenant_site on %I using (company_id = auth_company() and auth_site_ok(site_id)) with check (company_id = auth_company() and auth_site_ok(site_id))',t);
  end loop;
end $$;

-- Operational indexes and additive migration verification.
select 'fleet operations foundation installed' as status,
       (select count(*) from information_schema.tables where table_schema='public' and table_name in
        ('fleet_drivers','fleet_inspections','fleet_defects','fleet_fuel_logs','fleet_tyre_records','fleet_compliance_items','fleet_downtime_events')) as tables_created;

-- Explicit API privileges; RLS remains the tenant/site authorization boundary.
grant select, insert, update, delete on fleet_drivers, fleet_inspections, fleet_defects, fleet_fuel_logs, fleet_tyre_records, fleet_compliance_items, fleet_downtime_events to authenticated;

notify pgrst, 'reload schema';
