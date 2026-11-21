-- Enforce shipment lifecycle transitions in PostgreSQL, including delivery via signed POD.
begin;

create or replace function public.guard_logistics_shipment_status_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if old.status is not distinct from new.status then
    return new;
  end if;

  if not (
    (old.status='booked' and new.status in ('collected','exception')) or
    (old.status='collected' and new.status in ('in_transit','exception')) or
    (old.status='in_transit' and new.status in ('at_depot','out_for_delivery','exception')) or
    (old.status='at_depot' and new.status in ('out_for_delivery','in_transit','exception')) or
    (old.status='out_for_delivery' and new.status in ('delivered','at_depot','exception')) or
    (old.status='exception' and new.status in ('booked','collected','in_transit','at_depot','out_for_delivery','returned'))
  ) then
    raise exception 'Invalid shipment status transition: % -> %', old.status, new.status;
  end if;

  if new.status='delivered' and not exists (
    select 1 from public.logistics_pod_signoffs p
    where p.shipment_id=new.id
      and p.company_id=new.company_id
      and p.site_id=new.site_id
      and p.receiver_consent=true
      and length(btrim(p.receiver_name))>=2
      and p.signed_at=new.delivered_at
      and btrim(p.receiver_name)=btrim(new.pod_recipient_name)
      and p.reference is not distinct from nullif(btrim(new.pod_reference),'')
      and p.notes is not distinct from nullif(btrim(new.pod_notes),'')
  ) then
    raise exception 'Shipment delivery requires a valid signed proof of delivery';
  end if;

  return new;
end;
$$;
revoke all on function public.guard_logistics_shipment_status_transition() from public, anon, authenticated;
drop trigger if exists logistics_shipments_status_transition_guard on public.logistics_shipments;
create trigger logistics_shipments_status_transition_guard
before update of status on public.logistics_shipments
for each row execute function public.guard_logistics_shipment_status_transition();

commit;
