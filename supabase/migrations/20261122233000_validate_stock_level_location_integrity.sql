-- Ensure optional stock location belongs to the same company and site as its stock balance.
begin;

create or replace function private.validate_stock_level_location_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_location_company uuid;
  v_location_site uuid;
begin
  if new.location_id is not null then
    select company_id, site_id into v_location_company, v_location_site
    from public.locations
    where id = new.location_id;
    if not found then
      raise exception 'Stock location does not exist';
    end if;
    if v_location_company is distinct from new.company_id
       or v_location_site is distinct from new.site_id then
      raise exception 'Stock location must belong to the stock balance company and site';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.validate_stock_level_location_integrity() from public;
drop trigger if exists stock_levels_location_integrity_guard on public.stock_levels;
create trigger stock_levels_location_integrity_guard
before insert or update of company_id,site_id,location_id
on public.stock_levels
for each row execute function private.validate_stock_level_location_integrity();

commit;
