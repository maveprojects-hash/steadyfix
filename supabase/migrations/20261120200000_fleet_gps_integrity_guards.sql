-- STEADYFIX Fleet GPS integrity guards.
-- Apply through the normal migration process; do not execute against production directly.

begin;

-- Keep GPS position rows tied to the owning company and vehicle.
create or replace function public.validate_vehicle_position_integrity()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_company uuid;
begin
  if new.lat is null or new.lng is null or abs(new.lat) > 90 or abs(new.lng) > 180 then
    raise exception 'Invalid GPS coordinates';
  end if;
  if new.speed_kmh is not null and (new.speed_kmh < 0 or new.speed_kmh > 300) then
    raise exception 'Invalid GPS speed';
  end if;
  if new.heading is not null and (new.heading < 0 or new.heading > 360) then
    raise exception 'Invalid GPS heading';
  end if;
  if new.recorded_at is null or new.recorded_at > now() + interval '2 minutes' then
    raise exception 'GPS timestamp is invalid or too far in the future';
  end if;
  select company_id into v_company from public.vehicles where id = new.vehicle_id;
  if not found or v_company is distinct from new.company_id then
    raise exception 'GPS position vehicle must belong to the same company';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_vehicle_position_integrity() from public, anon, authenticated;
drop trigger if exists vehicle_positions_integrity_guard on public.vehicle_positions;
create trigger vehicle_positions_integrity_guard
before insert or update on public.vehicle_positions
for each row execute function public.validate_vehicle_position_integrity();

-- Add stable lookup indexes for fleet monitoring and history screens.
create index if not exists vehicle_positions_company_recent_idx
  on public.vehicle_positions(company_id, recorded_at desc);
create index if not exists vehicles_company_last_seen_idx
  on public.vehicles(company_id, last_seen desc);

commit;

notify pgrst, 'reload schema';
