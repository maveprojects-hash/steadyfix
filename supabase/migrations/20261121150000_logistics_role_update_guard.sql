-- Restrict shipment edits by operational role.
-- Managers may edit booking details; technicians/storemen may only change status/POD flow fields.
begin;

create or replace function public.guard_logistics_shipment_role_updates()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_role text:=public.auth_role();
begin
  if v_role in ('owner','manager') then
    return new;
  end if;
  if v_role not in ('technician','storeman') then
    raise exception 'You are not allowed to update this shipment';
  end if;

  if new.id is distinct from old.id
    or new.company_id is distinct from old.company_id
    or new.site_id is distinct from old.site_id
    or new.waybill_no is distinct from old.waybill_no
    or new.tracking_no is distinct from old.tracking_no
    or new.sender_name is distinct from old.sender_name
    or new.recipient_name is distinct from old.recipient_name
    or new.recipient_phone is distinct from old.recipient_phone
    or new.origin_address is distinct from old.origin_address
    or new.destination_address is distinct from old.destination_address
    or new.parcel_description is distinct from old.parcel_description
    or new.package_count is distinct from old.package_count
    or new.weight_kg is distinct from old.weight_kg
    or new.service_level is distinct from old.service_level
    or new.expected_delivery is distinct from old.expected_delivery
    or new.dispatched_at is distinct from old.dispatched_at
    or (
      new.delivered_at is distinct from old.delivered_at
      and not (
        old.status is distinct from 'delivered'
        and new.status='delivered'
        and exists (
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
        )
      )
    )
    or (
      (new.pod_recipient_name is distinct from old.pod_recipient_name
        or new.pod_reference is distinct from old.pod_reference
        or new.pod_notes is distinct from old.pod_notes)
      and not (
        old.status is distinct from 'delivered'
        and new.status='delivered'
        and exists (
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
        )
      )
    )
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at
  then
    raise exception 'Only owners and managers may edit shipment booking details';
  end if;

  return new;
end;
$$;
revoke all on function public.guard_logistics_shipment_role_updates() from public,anon,authenticated;
drop trigger if exists logistics_shipments_role_update_guard on public.logistics_shipments;
create trigger logistics_shipments_role_update_guard
before update on public.logistics_shipments
for each row execute function public.guard_logistics_shipment_role_updates();

commit;
