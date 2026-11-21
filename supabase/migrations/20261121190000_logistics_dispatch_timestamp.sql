-- Automatically timestamp shipment collection; this field was previously never populated by status changes.
begin;

create or replace function public.set_logistics_dispatch_timestamp()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if old.status is distinct from new.status and new.status='collected' then
    new.dispatched_at:=coalesce(new.dispatched_at,now());
  end if;
  return new;
end;
$$;
revoke all on function public.set_logistics_dispatch_timestamp() from public, anon, authenticated;
drop trigger if exists logistics_shipments_dispatch_timestamp on public.logistics_shipments;
create trigger logistics_shipments_dispatch_timestamp
before update of status on public.logistics_shipments
for each row execute function public.set_logistics_dispatch_timestamp();

commit;
