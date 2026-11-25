-- Make Hospitality & Tourism the database-level default for new companies.
-- Existing company industry selections are intentionally left unchanged.
alter table public.company_industry_profiles
  alter column primary_industry_slug set default 'hospitality-tourism';

create or replace function public.create_company_industry_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.company_industry_profiles (company_id, primary_industry_slug)
  values (new.id, 'hospitality-tourism')
  on conflict (company_id) do nothing;
  return new;
end;
$$;

revoke all on function public.create_company_industry_profile() from public, anon, authenticated;
