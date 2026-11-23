-- Reject null and non-finite sensor values before persisting telemetry.
-- Keep sensor-specific finite thresholds intact; this guards only malformed numeric payloads.
create or replace function public.ingest_reading(p_key text, p_value numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s sensors;
begin
  select * into s from sensors where device_key = p_key;
  if not found then raise exception 'Unknown device key'; end if;

  if not public.company_subscription_is_current(s.company_id) then
    raise exception 'Your trial or subscription has ended. Please choose a plan to continue.';
  end if;

  if p_value is null or p_value::text in ('NaN', 'Infinity', '-Infinity') then
    raise exception 'Invalid sensor reading';
  end if;

  insert into readings(company_id, sensor_id, value) values(s.company_id, s.id, p_value);
  return jsonb_build_object('ok', true,
    'alert', (s.alert_min is not null and p_value < s.alert_min)
           or (s.alert_max is not null and p_value > s.alert_max));
end;
$$;

revoke all on function public.ingest_reading(text, numeric) from public;
grant execute on function public.ingest_reading(text, numeric) to anon, authenticated;
notify pgrst, 'reload schema';
