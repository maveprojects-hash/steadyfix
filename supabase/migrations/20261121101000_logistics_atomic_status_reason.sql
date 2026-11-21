-- Atomic logistics status change and exception/return reason capture.
begin;
create or replace function public.logistics_update_status_with_reason(
  p_shipment_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_company_id uuid;
  v_site_id uuid;
  v_current_status text;
  v_reason text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_status not in ('collected','in_transit','at_depot','out_for_delivery','exception','returned') then
    raise exception 'Unsupported shipment status';
  end if;
  if p_status in ('exception','returned') then
    v_reason := nullif(btrim(p_reason),'");
    if v_reason is null then raise exception 'A reason is required'; end if;
    if length(v_reason)>2000 then raise exception 'Reason must be 2,000 characters or fewer'; end if;
  elsif p_reason is not null and btrim(p_reason)<>'' then
    raise exception 'Reason is only accepted for exception or return statuses';
  end if;
  select company_id,site_id,status into v_company_id,v_site_id,v_current_status
    from public.logistics_shipments
    where id=p_shipment_id and company_id=(select public.auth_company())
      and (select public.auth_site_ok(site_id))
    for update;
  if not found then raise exception 'Shipment not found or access denied'; end if;
  update public.logistics_shipments
    set status=p_status, delivered_at=null
    where id=p_shipment_id and company_id=v_company_id and site_id=v_site_id;
  if p_status in ('exception','returned') then
    insert into public.logistics_tracking_events(company_id,site_id,shipment_id,event_type,status,notes,created_by)
    values(v_company_id,v_site_id,p_shipment_id,
      case when p_status='exception' then 'exception_note' else 'return_note' end,
      p_status,v_reason,auth.uid());
  end if;
end;
$$;
revoke all on function public.logistics_update_status_with_reason(uuid,text,text) from public, anon;
grant execute on function public.logistics_update_status_with_reason(uuid,text,text) to authenticated;
commit;
notify pgrst, 'reload schema';
