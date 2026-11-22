-- Prevent location trees from crossing company/site boundaries or creating cycles.
begin;
create or replace function public.validate_location_parent_integrity()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_parent_company uuid;
  v_parent_site uuid;
begin
  if new.parent_id is null then return new; end if;
  if new.parent_id = new.id then raise exception 'A location cannot be its own parent'; end if;
  select company_id,site_id into v_parent_company,v_parent_site
    from public.locations where id = new.parent_id;
  if not found then raise exception 'Parent location not found'; end if;
  if v_parent_company is distinct from new.company_id
     or v_parent_site is distinct from new.site_id then
    raise exception 'Parent location must belong to the same company and site';
  end if;
  if exists (
    with recursive ancestors(id,parent_id) as (
      select id,parent_id from public.locations where id = new.parent_id
      union
      select l.id,l.parent_id from public.locations l join ancestors a on l.id = a.parent_id
    )
    select 1 from ancestors where id = new.id
  ) then raise exception 'Location hierarchy cannot contain a cycle'; end if;
  return new;
end;
$function$;
drop trigger if exists locations_parent_integrity_guard on public.locations;
create trigger locations_parent_integrity_guard
before insert or update of parent_id,company_id,site_id on public.locations
for each row execute function public.validate_location_parent_integrity();
revoke all on function public.validate_location_parent_integrity() from public;
grant execute on function public.validate_location_parent_integrity() to authenticated;
commit;
