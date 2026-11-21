-- Require new logistics shipments to begin in booked status.
-- Later lifecycle states must be reached through guarded status transitions.
begin;

create or replace function public.guard_logistics_shipment_initial_status()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.status is distinct from 'booked' then
    raise exception 'New shipments must begin in booked status';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_logistics_shipment_initial_status() from public, anon, authenticated;
drop trigger if exists logistics_shipments_initial_status_guard on public.logistics_shipments;
create trigger logistics_shipments_initial_status_guard
before insert on public.logistics_shipments
for each row execute function public.guard_logistics_shipment_initial_status();

commit;
