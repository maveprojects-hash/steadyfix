-- Keep shipment POD summary fields authoritative to the signed receiver record.
begin;

create or replace function public.guard_logistics_pod_metadata()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if (tg_op='INSERT' and (
       new.delivered_at is not null
       or new.pod_recipient_name is not null
       or new.pod_reference is not null
       or new.pod_notes is not null
     ))
     or (tg_op='UPDATE' and (
       new.delivered_at is distinct from old.delivered_at
       or new.pod_recipient_name is distinct from old.pod_recipient_name
       or new.pod_reference is distinct from old.pod_reference
       or new.pod_notes is distinct from old.pod_notes
     )) then
    if not exists (
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
      raise exception 'POD metadata must match a valid receiver signoff';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_logistics_pod_metadata() from public,anon,authenticated;
drop trigger if exists logistics_shipments_pod_metadata_guard on public.logistics_shipments;
create trigger logistics_shipments_pod_metadata_guard
before insert or update
on public.logistics_shipments
for each row execute function public.guard_logistics_pod_metadata();

commit;
