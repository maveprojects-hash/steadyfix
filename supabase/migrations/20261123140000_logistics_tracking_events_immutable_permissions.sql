-- Tracking history is append-only for authenticated users.
-- Lifecycle events are created by trusted shipment triggers; user events are scans.
-- Explicitly remove any UPDATE/DELETE table grants and stale write policies.
begin;

revoke update, delete on table public.logistics_tracking_events from authenticated;
drop policy if exists logistics_tracking_events_update on public.logistics_tracking_events;
drop policy if exists logistics_tracking_events_delete on public.logistics_tracking_events;

-- Preserve the intended authenticated read/scan-insert interface.
grant select, insert on table public.logistics_tracking_events to authenticated;

commit;
