-- Prevent user scans after a shipment reaches a terminal state.
-- Delivered and returned parcels must not receive additional scan events.
begin;

drop policy if exists logistics_tracking_events_insert on public.logistics_tracking_events;
create policy logistics_tracking_events_insert on public.logistics_tracking_events
  for insert to authenticated
  with check (
    company_id = (select public.auth_company())
    and (select public.auth_site_ok(site_id))
    and created_by = (select auth.uid())
    and event_type = 'scan'
    and location is not null
    and length(btrim(location)) > 0
    and (notes is null or length(notes) <= 2000)
    and exists (
      select 1
      from public.logistics_shipments s
      where s.id = logistics_tracking_events.shipment_id
        and s.company_id = logistics_tracking_events.company_id
        and s.site_id = logistics_tracking_events.site_id
        and s.status is not distinct from logistics_tracking_events.status
        and s.status not in ('delivered','returned')
    )
  );

commit;
