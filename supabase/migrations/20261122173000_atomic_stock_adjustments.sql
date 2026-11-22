-- Serialize stock adjustments on the catalogue item to prevent lost updates from stale UI reads.
create or replace function private.adjust_stock_level_impl(
  p_item_id uuid,
  p_site_id uuid,
  p_delta numeric,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user uuid := auth.uid();
  v_company uuid := public.auth_company();
  v_role text := public.auth_role();
  v_site uuid;
  v_on_hand numeric := 0;
  v_new numeric;
begin
  if v_user is null or v_company is null then raise exception 'Authentication required'; end if;
  if v_role not in ('owner','manager','storeman') then raise exception 'You are not allowed to adjust stock'; end if;
  if p_item_id is null then raise exception 'Stock item is required'; end if;
  if p_delta is null or p_delta in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or p_delta = 0 or abs(p_delta) > 1000000000 then
    raise exception 'Stock adjustment must be a finite non-zero quantity within the allowed range';
  end if;
  select s.id into v_site from public.sites s where s.id=p_site_id and s.company_id=v_company;
  if not found then raise exception 'Site not found in this company'; end if;
  if not public.auth_site_ok(v_site) then raise exception 'You do not have access to this site'; end if;
  -- Lock the parent catalogue row first to serialize even when no balance row exists yet.
  perform 1 from public.stock_items i where i.id=p_item_id and i.company_id=v_company for update;
  if not found then raise exception 'Stock item not found in this company'; end if;
  select sl.on_hand into v_on_hand
    from public.stock_levels sl
    where sl.item_id=p_item_id and sl.site_id=v_site and sl.company_id=v_company
    for update;
  if not found then v_on_hand := 0; end if;
  v_new := v_on_hand + p_delta;
  if v_new < 0 then raise exception 'Stock adjustment would make inventory negative'; end if;
  insert into public.stock_levels(item_id,site_id,company_id,on_hand)
  values(p_item_id,v_site,v_company,v_new)
  on conflict(item_id,site_id) do update set on_hand=excluded.on_hand, company_id=excluded.company_id;
  return jsonb_build_object('previous_quantity',v_on_hand,'new_quantity',v_new,'adjustment',p_delta);
end;
$$;
revoke all on function private.adjust_stock_level_impl(uuid,uuid,numeric,text) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.adjust_stock_level_impl(uuid,uuid,numeric,text) to authenticated;

create or replace function public.adjust_stock_level(
  p_item_id uuid,
  p_site_id uuid,
  p_delta numeric,
  p_notes text default null
) returns jsonb
language sql
security invoker
set search_path = pg_catalog, public, private
as $$ select private.adjust_stock_level_impl(p_item_id,p_site_id,p_delta,p_notes); $$;
revoke all on function public.adjust_stock_level(uuid,uuid,numeric,text) from public, anon;
grant execute on function public.adjust_stock_level(uuid,uuid,numeric,text) to authenticated;
