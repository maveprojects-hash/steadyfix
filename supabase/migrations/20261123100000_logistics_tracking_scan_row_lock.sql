-- Serialize user tracking scans with shipment lifecycle updates and validate terminal state under lock.
begin;

create or replace function public.guard_logistics_tracking_scan_insert()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_company uuid:=public.auth_company();
  v_role text:=public.auth_role();
  v_status text;
begin
  if new.event_type <> 'scan' then
    return new;
  end if;
  if auth.uid() is null or v_company is null or v_role is null
    or v_role not in ('owner','manager','technician','storeman')
    or new.created_by is distinct from auth.uid()
    or new.company_id is distinct from v_company
    or not public.auth_site_ok(new.site_id)
    or new.location is null or length(btrim(new.location)) not between 1 and 200
    or (new.notes is not null and length(new.notes)>2000) then
    raise exception 'Invalid tracking scan';
  end if;

  select s.status into v_status
  from public.logistics_shipments s
  where s.id=new.shipment_id
    and s.company_id=new.company_id
    and s.site_id=new.site_id
  for update;

  if not found then
    raise exception 'Shipment not found or inaccessible';
  end if;
  if v_status in ('delivered','returned') or v_status is distinct from new.status then
    raise exception 'Tracking scan status is stale or shipment is terminal';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_logistics_tracking_scan_insert() from public,anon,authenticated;
drop trigger if exists logistics_tracking_scan_insert_guard on public.logistics_tracking_events;
create trigger logistics_tracking_scan_insert_guard
before insert on public.logistics_tracking_events
for each row execute function public.guard_logistics_tracking_scan_insert();

commit;
