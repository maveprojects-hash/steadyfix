-- Reject duplicate secondary industries at the database boundary, not only in the UI.
create or replace function public.validate_company_industry_profile()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  secondary_count integer;
  distinct_secondary_count integer;
begin
  if not exists (
    select 1 from public.industry_catalog
    where slug = new.primary_industry_slug and is_active
  ) then
    raise exception 'Select an active industry profile';
  end if;

  if exists (
    select 1
    from unnest(coalesce(new.secondary_industry_slugs, '{}'::text[])) as item(slug)
    where item.slug = new.primary_industry_slug
       or not exists (
         select 1 from public.industry_catalog c
         where c.slug = item.slug and c.is_active
       )
  ) then
    raise exception 'Secondary industries must be active profiles and cannot repeat the primary industry';
  end if;

  select count(*), count(distinct slug)
    into secondary_count, distinct_secondary_count
    from unnest(coalesce(new.secondary_industry_slugs, '{}'::text[])) as items(slug);
  if secondary_count <> distinct_secondary_count then
    raise exception 'Secondary industries cannot contain duplicates';
  end if;

  new.secondary_industry_slugs := coalesce(new.secondary_industry_slugs, '{}'::text[]);
  new.business_description := left(coalesce(new.business_description, ''), 4000);
  return new;
end;
$$;
