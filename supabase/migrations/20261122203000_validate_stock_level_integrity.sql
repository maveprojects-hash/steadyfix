-- Guard stock-level quantities and ensure item/site ownership matches the row's tenant.
begin;

create or replace function private.validate_stock_level_integrity()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_item_company uuid;
  v_site_company uuid;
begin
  if new.on_hand is null or new.on_hand::text in ('NaN','Infinity','-Infinity') or new.on_hand < 0 then
    raise exception 'Stock on hand must be a finite non-negative quantity';
  end if;

  select company_id into v_item_company
  from public.stock_items
  where id = new.item_id;
  if not found then raise exception 'Stock item not found'; end if;

  select company_id into v_site_company
  from public.sites
  where id = new.site_id;
  if not found then raise exception 'Stock site not found'; end if;

  if v_item_company is distinct from new.company_id or v_site_company is distinct from new.company_id then
    raise exception 'Stock item and site must belong to the same company as the stock balance';
  end if;
  return new;
end;
$function$;

revoke all on function private.validate_stock_level_integrity() from public;
drop trigger if exists stock_levels_integrity_guard on public.stock_levels;
create trigger stock_levels_integrity_guard
before insert or update of item_id,site_id,company_id,on_hand on public.stock_levels
for each row execute function private.validate_stock_level_integrity();

commit;
