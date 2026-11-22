-- Validate tracker numeric inputs at the database boundary.
-- GPS tracker keys remain the authentication mechanism; reject malformed telemetry.
create or replace function public.ingest_position(
  p_key text,
  p_lat double precision,
  p_lng double precision,
  p_speed numeric default 0,
  p_heading numeric default null,
  p_odometer numeric default null,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v vehicles%rowtype;
  t timestamptz;
begin
  select * into v from vehicles where device_key = p_key limit 1;
  if not found then raise exception 'Unknown tracker key'; end if;

  if p_lat is null or p_lng is null
     
     or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'Bad position';
  end if;

  if p_speed is not null and (p_speed < 0 or p_speed > 300) then
    raise exception 'Bad speed';
  end if;

  if p_heading is not null and (p_heading < 0 or p_heading > 360) then
    raise exception 'Bad heading';
  end if;

  if p_odometer is not null and (p_odometer < 0 or p_odometer > 10000000) then
    raise exception 'Bad odometer';
  end if;

  if not public.company_subscription_is_current(v.company_id) then
    raise exception 'Your trial or subscription has ended. Please choose a plan to continue.';
  end if;

  t := least(coalesce(p_at, now()), now());
  insert into vehicle_positions (company_id, vehicle_id, recorded_at, lat, lng, speed_kmh, heading)
    values (v.company_id, v.id, t, p_lat, p_lng, coalesce(p_speed, 0), p_heading);

  update vehicles
     set last_lat = p_lat,
         last_lng = p_lng,
         last_speed = coalesce(p_speed, 0),
         last_seen = t,
         odometer_km = coalesce(p_odometer, odometer_km)
   where id = v.id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.ingest_position(text, double precision, double precision, numeric, numeric, numeric, timestamptz) from public;
grant execute on function public.ingest_position(text, double precision, double precision, numeric, numeric, numeric, timestamptz) to anon, authenticated;
notify pgrst, 'reload schema';
