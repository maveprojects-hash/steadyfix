-- Dispatch timestamps are database-owned and lifecycle-bound.
begin;

create or replace function public.guard_logistics_dispatch_timestamp()
returns trigger
language plpgsql
set search_path=pg_catalog,public
as $$
begin
  if tg_op='INSERT' then
    if new.dispatched_at is not null then
      raise exception 'Dispatch timestamp is database-owned';
    end if;
    return new;
  end if;

  if old.status is distinct from new.status and new.status='collected' then
    new.dispatched_at:=statement_timestamp();
  elsif new.dispatched_at is distinct from old.dispatched_at then
    raise exception 'Dispatch timestamp cannot be changed outside collection transition';
  end if;

  return new;
end;
$$;
revoke all on function public.guard_logistics_dispatch_timestamp() from public,anon,authenticated;
drop trigger if exists logistics_shipments_dispatch_timestamp_guard on public.logistics_shipments;
drop trigger if exists logistics_shipments_dispatch_timestamp on public.logistics_shipments;
create trigger logistics_shipments_dispatch_timestamp_guard
before insert or update on public.logistics_shipments
for each row execute function public.guard_logistics_dispatch_timestamp();

commit;
