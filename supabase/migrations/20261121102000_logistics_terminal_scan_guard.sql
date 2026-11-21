-- Prevent tracking scans after shipment terminal status, including direct API inserts.
begin;
create or replace function public.logistics_validate_scan_terminal_status()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_status text;
begin
  if new.event_type <> 'scan' then return new; end if;
  select status into v_status from public.logistics_shipments
    where id=new.shipment_id and company_id=new.company_id and site_id=new.site_id
    for update;
  if v_status in ('delivered','returned') then
    raise exception 'Tracking scans are closed for delivered or returned consignments';
  end if;
  return new;
end;
$$;
revoke all on function public.logistics_validate_scan_terminal_status() from public, anon, authenticated;
drop trigger if exists logistics_tracking_scan_terminal_guard on public.logistics_tracking_events;
create trigger logistics_tracking_scan_terminal_guard
before insert on public.logistics_tracking_events
for each row execute function public.logistics_validate_scan_terminal_status();
commit;
