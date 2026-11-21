-- Keep shipment identity and booking reference immutable after creation.
begin;

create or replace function public.guard_logistics_shipment_identity()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.id is distinct from old.id
    or new.company_id is distinct from old.company_id
    or new.site_id is distinct from old.site_id
    or new.waybill_no is distinct from old.waybill_no
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'Shipment identity and waybill cannot be changed after booking';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_logistics_shipment_identity() from public, anon, authenticated;
drop trigger if exists logistics_shipments_identity_guard on public.logistics_shipments;
create trigger logistics_shipments_identity_guard
before update on public.logistics_shipments
for each row execute function public.guard_logistics_shipment_identity();

commit;
