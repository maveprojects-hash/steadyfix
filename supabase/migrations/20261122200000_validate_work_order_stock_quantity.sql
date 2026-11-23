-- Reject non-finite work-order material issue quantities before stock arithmetic.
begin;

create or replace function private.issue_work_order_stock_impl(
  p_work_order_id uuid,
  p_stock_item_id uuid,
  p_quantity numeric,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_user uuid := auth.uid();
  v_company uuid := public.auth_company();
  v_role text := public.auth_role();
  v_site uuid;
  v_assigned uuid;
  v_item_name text;
  v_unit text;
  v_unit_cost numeric;
  v_on_hand numeric;
  v_remaining numeric;
  v_total numeric;
begin
  if v_user is null or v_company is null then raise exception 'Authentication required'; end if;
  if v_role not in ('owner','manager','technician','storeman') then raise exception 'You are not allowed to issue stock'; end if;
  if p_quantity is null or p_quantity::text in ('NaN','Infinity','-Infinity') or p_quantity <= 0 then
    raise exception 'Issue quantity must be a finite number greater than zero';
  end if;
  select w.site_id,w.assigned_to into v_site,v_assigned
  from public.work_orders w
  where w.id = p_work_order_id and w.company_id = v_company;
  if not found then raise exception 'Job card not found in this company'; end if;
  if not public.auth_site_ok(v_site) then raise exception 'You do not have access to this site'; end if;
  if v_role = 'technician' and v_assigned is distinct from v_user then
    raise exception 'Technicians may only issue stock to their assigned job cards';
  end if;
  select i.name,i.unit,i.unit_cost into v_item_name,v_unit,v_unit_cost
  from public.stock_items i
  where i.id = p_stock_item_id and i.company_id = v_company;
  if not found then raise exception 'Stock item not found in this company'; end if;
  select sl.on_hand into v_on_hand
  from public.stock_levels sl
  where sl.item_id = p_stock_item_id and sl.site_id = v_site and sl.company_id = v_company
  for update;
  if not found then raise exception 'There is no stock balance for this item at the job site'; end if;
  if v_on_hand < p_quantity then
    raise exception 'Insufficient stock. Available: % %', v_on_hand, coalesce(v_unit,'units');
  end if;
  v_remaining := v_on_hand - p_quantity;
  v_total := round(p_quantity * coalesce(v_unit_cost,0),2);
  update public.stock_levels set on_hand = v_remaining
  where item_id = p_stock_item_id and site_id = v_site and company_id = v_company;
  insert into public.work_order_material_issues(
    company_id,site_id,work_order_id,stock_item_id,item_name,unit,quantity,unit_cost,total_cost,notes,issued_by
  ) values (
    v_company,v_site,p_work_order_id,p_stock_item_id,v_item_name,coalesce(v_unit,'each'),
    p_quantity,coalesce(v_unit_cost,0),v_total,nullif(btrim(p_notes),''),v_user
  );
  return jsonb_build_object('remaining_quantity',v_remaining,'quantity_issued',p_quantity,'total_cost',v_total);
end;
$function$;

revoke all on function private.issue_work_order_stock_impl(uuid,uuid,numeric,text) from public;
grant execute on function private.issue_work_order_stock_impl(uuid,uuid,numeric,text) to authenticated;

commit;
