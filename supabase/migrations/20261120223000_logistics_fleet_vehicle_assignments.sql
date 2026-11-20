-- Logistics <-> Fleet vehicle assignment, with tenant/site validation and audit history.
begin;
alter table public.logistics_shipments add column if not exists vehicle_id uuid references public.vehicles(id) on delete set null;
create index if not exists logistics_shipments_company_site_vehicle_idx on public.logistics_shipments(company_id,site_id,vehicle_id) where vehicle_id is not null;
create or replace function public.validate_logistics_vehicle_assignment()
returns trigger language plpgsql set search_path = pg_catalog, public, pg_temp as $$
declare v_company uuid; v_site uuid; v_status text;
begin
  if old.vehicle_id is not distinct from new.vehicle_id then return new; end if;
  if new.status in ('delivered','returned') then raise exception 'Delivered or returned consignments cannot change vehicle assignment'; end if;
  if new.vehicle_id is null then return new; end if;
  select company_id,site_id,status into v_company,v_site,v_status from public.vehicles where id=new.vehicle_id;
  if not found or v_company is distinct from new.company_id or v_site is distinct from new.site_id then
    raise exception 'Assigned vehicle must belong to the same company and site';
  end if;
  if v_status = 'in_service' then
    raise exception 'Vehicles in service cannot be assigned to consignments';
  end if;
  return new;
end; $$;
revoke all on function public.validate_logistics_vehicle_assignment() from public, anon, authenticated;
drop trigger if exists logistics_vehicle_assignment_validate on public.logistics_shipments;
create trigger logistics_vehicle_assignment_validate before insert or update of vehicle_id on public.logistics_shipments for each row execute function public.validate_logistics_vehicle_assignment();
alter table public.logistics_tracking_events drop constraint if exists logistics_tracking_events_event_type_check;
alter table public.logistics_tracking_events add constraint logistics_tracking_events_event_type_check check (event_type in ('created','status_change','scan','pod','vehicle_assignment','exception_note','return_note'));
create or replace function public.logistics_record_vehicle_assignment_event()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_old_name text; v_new_name text; v_note text;
begin
  if old.vehicle_id is not distinct from new.vehicle_id then return new; end if;
  if old.vehicle_id is not null then select coalesce(name,reg_no,'Vehicle') into v_old_name from public.vehicles where id=old.vehicle_id; end if;
  if new.vehicle_id is not null then select coalesce(name,reg_no,'Vehicle') into v_new_name from public.vehicles where id=new.vehicle_id; end if;
  v_note := case
    when old.vehicle_id is null and new.vehicle_id is not null then 'Vehicle assigned: '||coalesce(v_new_name,'vehicle')
    when old.vehicle_id is not null and new.vehicle_id is null then 'Vehicle assignment cleared: '||coalesce(v_old_name,'vehicle')
    else 'Vehicle reassigned from '||coalesce(v_old_name,'vehicle')||' to '||coalesce(v_new_name,'vehicle')
  end;
  insert into public.logistics_tracking_events(company_id,site_id,shipment_id,event_type,status,notes,created_by)
  values(new.company_id,new.site_id,new.id,'vehicle_assignment',new.status,v_note,auth.uid());
  return new;
end; $$;
revoke all on function public.logistics_record_vehicle_assignment_event() from public, anon, authenticated;
drop trigger if exists logistics_shipments_vehicle_assignment_event on public.logistics_shipments;
create trigger logistics_shipments_vehicle_assignment_event after update of vehicle_id on public.logistics_shipments for each row execute function public.logistics_record_vehicle_assignment_event();
commit;
notify pgrst, 'reload schema';
