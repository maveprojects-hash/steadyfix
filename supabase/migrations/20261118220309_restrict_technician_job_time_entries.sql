-- Ensure technicians can only record labour against job cards assigned to them.
create or replace function public.validate_work_order_time_entry()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_company uuid;
  v_site uuid;
  v_assigned uuid;
  v_staff_company uuid;
  v_active boolean;
begin
  select company_id,site_id,assigned_to
    into v_company,v_site,v_assigned
  from public.work_orders where id=new.work_order_id;
  if not found or v_company<>new.company_id or v_site<>new.site_id then
    raise exception 'Labour entry job card must belong to the same company and site';
  end if;
  select company_id,active into v_staff_company,v_active
  from public.profiles where id=new.technician_id;
  if not found or v_staff_company<>new.company_id or not v_active then
    raise exception 'Technician must be an active member of this company';
  end if;
  if public.auth_role()='technician' and v_assigned is distinct from auth.uid() then
    raise exception 'Technicians may only record labour against job cards assigned to them';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_work_order_time_entry() from public, anon, authenticated;