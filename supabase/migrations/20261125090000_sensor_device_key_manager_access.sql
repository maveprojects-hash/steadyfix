-- Keep sensor device credentials private to company owners and managers.
-- Ordinary staff can continue viewing monitoring status and recorded readings.

revoke select (device_key), insert (device_key), update (device_key), references (device_key)
  on table public.sensors from authenticated;

drop policy if exists tenant_site on public.sensors;

create policy tenant_site_read
  on public.sensors
  for select
  to authenticated
  using (company_id = public.auth_company() and public.auth_site_ok(site_id));

create policy tenant_site_manager_write
  on public.sensors
  for all
  to authenticated
  using (
    company_id = public.auth_company()
    and public.auth_site_ok(site_id)
    and public.auth_role() in ('owner','manager')
  )
  with check (
    company_id = public.auth_company()
    and public.auth_site_ok(site_id)
    and public.auth_role() in ('owner','manager')
  );

create or replace function public.get_sensor_device_keys(p_site_id uuid)
returns table(sensor_id uuid, device_key text)
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
    raise exception 'Only a company owner or manager may access sensor device keys';
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
    select s.id, s.device_key
    from public.sensors s
    where s.company_id = v_company_id
      and s.site_id = p_site_id
    order by s.name;
end;
$function$;

revoke all on function public.get_sensor_device_keys(uuid) from public, anon;
grant execute on function public.get_sensor_device_keys(uuid) to authenticated;
