-- STEADYFIX Fleet and workshop: job cards, GPS tracking, speeding alerts.
-- Run this whole block once in the Supabase SQL Editor. Safe to run more than once.

-- ---------- Vehicles: more details and tracker fields ----------
alter table vehicles
  add column if not exists make_model text,
  add column if not exists vin text,
  add column if not exists next_service_date date,
  add column if not exists speed_limit numeric default 100,
  add column if not exists device_key text default replace(gen_random_uuid()::text, '-', ''),
  add column if not exists last_lat double precision,
  add column if not exists last_lng double precision,
  add column if not exists last_speed numeric,
  add column if not exists last_seen timestamptz;
update vehicles set device_key = replace(gen_random_uuid()::text, '-', '') where device_key is null;
create unique index if not exists vehicles_device_key_uq on vehicles (device_key);

-- ---------- Workshop job cards ----------
create table if not exists workshop_jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  created_at timestamptz not null default now(),
  job_no text not null,
  vehicle_id uuid references vehicles(id) on delete set null,
  complaint text, work_to_do text, mechanic text, priority text,
  status text default 'booked',
  opened_on date default current_date, due_date date,
  odometer_in numeric, labour_hours numeric, labour_cost numeric,
  lines jsonb default '[]'::jsonb, parts_cost numeric default 0, notes text);

-- ---------- GPS positions ----------
create table if not exists vehicle_positions (
  id bigint generated always as identity primary key,
  company_id uuid not null references companies(id) on delete cascade,
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  recorded_at timestamptz not null default now(),
  lat double precision not null, lng double precision not null,
  speed_kmh numeric default 0, heading numeric);
create index if not exists vehicle_positions_v_time on vehicle_positions (vehicle_id, recorded_at desc);

-- ---------- Row-level security ----------
alter table workshop_jobs enable row level security;
drop policy if exists tenant_site on workshop_jobs;
create policy tenant_site on workshop_jobs using (company_id = auth_company() and auth_site_ok(site_id)) with check (company_id = auth_company() and auth_site_ok(site_id));
create index if not exists workshop_jobs_co_site on workshop_jobs (company_id, site_id);

alter table vehicle_positions enable row level security;
drop policy if exists pos_read on vehicle_positions;
create policy pos_read on vehicle_positions for select using (company_id = auth_company());

-- ---------- Trackers report here (the vehicle's own key is the password) ----------
create or replace function ingest_position(
  p_key text, p_lat double precision, p_lng double precision,
  p_speed numeric default 0, p_heading numeric default null,
  p_odometer numeric default null, p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path = public as $$
declare v vehicles%rowtype; t timestamptz;
begin
  select * into v from vehicles where device_key = p_key limit 1;
  if not found then raise exception 'Unknown tracker key'; end if;
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then raise exception 'Bad position'; end if;
  t := least(coalesce(p_at, now()), now());
  insert into vehicle_positions (company_id, vehicle_id, recorded_at, lat, lng, speed_kmh, heading)
    values (v.company_id, v.id, t, p_lat, p_lng, coalesce(p_speed, 0), p_heading);
  update vehicles set last_lat = p_lat, last_lng = p_lng, last_speed = coalesce(p_speed, 0), last_seen = t,
         odometer_km = coalesce(p_odometer, odometer_km) where id = v.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function ingest_position(text, double precision, double precision, numeric, numeric, numeric, timestamptz) from public;
grant execute on function ingest_position(text, double precision, double precision, numeric, numeric, numeric, timestamptz) to anon, authenticated;

notify pgrst, 'reload schema';

-- Check: this should list 2 tables, and the vehicle columns should show
select table_name from information_schema.tables where table_schema = 'public' and table_name in ('workshop_jobs', 'vehicle_positions') order by 1;
select column_name from information_schema.columns where table_name = 'vehicles' and column_name in ('device_key', 'speed_limit', 'last_seen') order by 1;
