-- Replace broad table-level sensor grants with least-privilege column access.
-- The device_key column is only readable through get_sensor_device_keys(),
-- which enforces authenticated owner/manager and company/site checks.

revoke all privileges on table public.sensors from authenticated;

grant select (
  id, company_id, site_id, name, kind, unit,
  alert_min, alert_max, external_id, created_at
) on table public.sensors to authenticated;

grant insert (
  company_id, site_id, name, kind, unit,
  alert_min, alert_max, external_id
) on table public.sensors to authenticated;

grant update (
  name, kind, unit, alert_min, alert_max, external_id
) on table public.sensors to authenticated;

grant delete on table public.sensors to authenticated;
