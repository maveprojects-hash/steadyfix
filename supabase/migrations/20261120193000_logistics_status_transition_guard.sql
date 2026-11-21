-- Enforce logistics shipment lifecycle transitions at the database layer.
-- UI transition checks are helpful, but this trigger protects writes from every client.
begin;

create or replace function public.logistics_validate_status_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if not (
    (old.status = 'booked' and new.status in ('collected','exception'))
    or (old.status = 'collected' and new.status in ('in_transit','exception'))
    or (old.status = 'in_transit' and new.status in ('at_depot','out_for_delivery','exception'))
    or (old.status = 'at_depot' and new.status in ('in_transit','out_for_delivery','exception'))
    or (old.status = 'out_for_delivery' and new.status in ('delivered','exception'))
    or (old.status = 'exception' and new.status in ('collected','in_transit','at_depot','out_for_delivery','delivered','returned'))
  ) then
    raise exception 'Invalid logistics status transition: % -> %', old.status, new.status
      using errcode = '23514';
  end if;

  if new.status = 'delivered' and (
    new.delivered_at is null or nullif(btrim(new.pod_recipient_name),'') is null
  ) then
    raise exception 'Delivered shipments require delivery timestamp and receiver name'
      using errcode = '23514';
  end if;

  if new.status = 'returned' and old.status <> 'exception' then
    raise exception 'Shipments may only be returned from exception status'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.logistics_validate_status_transition() from public, anon, authenticated;

drop trigger if exists logistics_shipments_validate_status_transition on public.logistics_shipments;
create trigger logistics_shipments_validate_status_transition
before update of status on public.logistics_shipments
for each row execute function public.logistics_validate_status_transition();

commit;
