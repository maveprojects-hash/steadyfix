-- Keep GPS bearer keys private to company owners and managers.
-- Vehicle status and non-secret operational fields remain available to authorized site users.

alter table public.vehicles add column if not exists license_expiry date;

revoke all privileges on table public.vehicles from authenticated;

grant select (
  id, company_id, site_id, name, reg_no, odometer_km, next_service_km,
  status, make_model, vin, next_service_date, license_expiry, speed_limit,
  last_lat, last_lng, last_speed, last_seen, created_at
) on table public.vehicles to authenticated;

grant insert (
  company_id, site_id, name, reg_no, odometer_km, next_service_km,
  status, make_model, vin, next_service_date, license_expiry, speed_limit,
  last_lat, last_lng, last_speed, last_seen
) on table public.vehicles to authenticated;

grant update (
  name, reg_no, odometer_km, next_service_km, status, make_model, vin,
  next_service_date, license_expiry, speed_limit, last_lat, last_lng, last_speed, last_seen
) on table public.vehicles to authenticated;

grant delete on table public.vehicles to authenticated;

create or replace function public.get_vehicle_device_keys(p_site_id uuid)
returns table(vehicle_id uuid, device_key text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_company_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if public.auth_role() not in ('owner','manager') then
    raise exception 'Only a company owner or manager may access vehicle device keys';
  end if;

  v_company_id := public.auth_company();
  if v_company_id is null or p_site_id is null then
    raise exception 'A valid company and site are required';
  end if;

  if not exists (
    select 1 from public.sites
    where id = p_site_id and company_id = v_company_id
  ) then
    raise exception 'The selected site is unavailable for this company';
  end if;

  return query
    select v.id, v.device_key
    from public.vehicles v
    where v.company_id = v_company_id
      and v.site_id = p_site_id
    order by v.name;
end;
$function$;

revoke all on function public.get_vehicle_device_keys(uuid) from public, anon;
grant execute on function public.get_vehicle_device_keys(uuid) to authenticated;
