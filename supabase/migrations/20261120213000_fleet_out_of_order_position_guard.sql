-- Fleet GPS: serialize tracker writes and prevent stale positions from replacing the current vehicle state.
-- Compatible with existing device_key credentials and RPC signature.
create or replace function public.ingest_position(
  p_key text, p_lat double precision, p_lng double precision,
  p_speed numeric default 0, p_heading numeric default null,
  p_odometer numeric default null, p_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v public.vehicles%rowtype;
  t timestamptz;
begin
  -- Lock the vehicle row to serialize concurrent updates and odometer checks.
  select * into v
  from public.vehicles
  where device_key = p_key
  for update;

  if not found then
    raise exception 'Unknown tracker key';
  end if;

  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'Bad position';
  end if;
  if p_speed is not null and (p_speed < 0 or p_speed > 300) then
    raise exception 'Bad speed';
  end if;
  if p_heading is not null and (p_heading < 0 or p_heading > 360) then
    raise exception 'Bad heading';
  end if;
  if p_odometer is not null and p_odometer < 0 then
    raise exception 'Bad odometer';
  end if;

  t := least(coalesce(p_at, now()), now());

  -- Keep every accepted point in history, but only newer telemetry may update
  -- the vehicle's live location, speed, last_seen, or odometer snapshot.
  insert into public.vehicle_positions
    (company_id, vehicle_id, recorded_at, lat, lng, speed_kmh, heading)
  values
    (v.company_id, v.id, t, p_lat, p_lng, coalesce(p_speed, 0), p_heading);

  if v.last_seen is null or t > v.last_seen then
    if p_odometer is not null and v.odometer_km is not null and p_odometer < v.odometer_km then
      raise exception 'Odometer cannot move backwards';
    end if;

    update public.vehicles
    set last_lat = p_lat,
        last_lng = p_lng,
        last_speed = coalesce(p_speed, 0),
        last_seen = t,
        odometer_km = coalesce(p_odometer, odometer_km)
    where id = v.id;
  elsif p_odometer is not null and v.odometer_km is not null and p_odometer < v.odometer_km then
    -- Older GPS points must not be allowed to roll the odometer backwards.
    raise exception 'Odometer cannot move backwards';
  end if;

  return jsonb_build_object('ok', true, 'current_updated', (v.last_seen is null or t > v.last_seen));
end;
$$;

revoke all on function public.ingest_position(text, double precision, double precision, numeric, numeric, numeric, timestamptz) from public;
grant execute on function public.ingest_position(text, double precision, double precision, numeric, numeric, numeric, timestamptz) to anon, authenticated;

notify pgrst, 'reload schema';
