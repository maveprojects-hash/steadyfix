-- Prevent terminal Logistics shipments from being reopened or overwritten by concurrent POD/status updates.
begin;
create or replace function public.guard_logistics_terminal_status_transition()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if old.status in ('delivered','returned') and new.status is distinct from old.status then
    raise exception 'Terminal shipment status cannot be changed';
  end if;
  if new.status='delivered' and old.status is distinct from 'delivered' then
    if not exists (
      select 1 from public.logistics_pod_signoffs p
      where p.shipment_id=new.id and p.company_id=new.company_id and p.site_id=new.site_id
    ) then
      raise exception 'Delivery status requires a receiver signoff';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_logistics_terminal_status_transition() from public,anon,authenticated;
drop trigger if exists logistics_shipments_terminal_status_guard on public.logistics_shipments;
create trigger logistics_shipments_terminal_status_guard
before update of status on public.logistics_shipments
for each row execute function public.guard_logistics_terminal_status_transition();
commit;
