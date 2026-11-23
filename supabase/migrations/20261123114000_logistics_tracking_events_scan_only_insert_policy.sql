-- Restrict authenticated direct inserts to user-created scan events only.
-- Shipment lifecycle events are emitted by the SECURITY DEFINER status trigger.
begin;
drop policy if exists logistics_tracking_events_insert on public.logistics_tracking_events;
create policy logistics_tracking_events_insert on public.logistics_tracking_events
  for insert to authenticated
  with check (
    event_type = 'scan'
    and company_id = (select public.auth_company())
    and (select public.auth_site_ok(site_id))
    and created_by = (select auth.uid())
    and (select public.auth_role()) in ('owner','manager','technician','storeman')
  );
commit;
