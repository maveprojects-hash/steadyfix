-- Company-specific, extensible industry profiles for STEADYFIX CMMS.
-- Additive only: existing companies, subscriptions, sites and operational records remain unchanged.

create table public.industry_catalog (
  slug text primary key,
  name text not null,
  description text not null,
  business_examples text[] not null default '{}'::text[],
  default_configuration jsonb not null default '{}'::jsonb,
  sort_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint industry_catalog_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint industry_catalog_configuration_object check (jsonb_typeof(default_configuration) = 'object')
);

insert into public.industry_catalog
  (slug, name, description, business_examples, default_configuration, sort_order)
values
  ('automation', 'Automation (Copier & Office Equipment)',
   'Service and maintenance businesses supporting copier machines and office automation equipment, including device fleets, service calls, maintenance contracts, meter readings and consumables.',
   array['Xerox equipment service','Nashua copier service','Multifunction devices','Office automation equipment'],
   '{"focus_areas":["customer sites","copier and device assets","service calls","preventive maintenance","service contracts","meter readings","toner and consumables","parts and stock"],"terminology":{"asset":"Copier / office device","work_order":"Service call","site":"Customer site"}}'::jsonb, 10),
  ('fleet-management', 'Fleet Management',
   'Businesses managing vehicle fleets, inspections, licensing, utilisation, maintenance schedules, fuel and operating costs.',
   array['Company vehicle fleets','Commercial fleets','Vehicle leasing and fleet services'],
   '{"focus_areas":["vehicles","fleet inspections","maintenance schedules","licensing","fuel and operating costs","vehicle availability"],"terminology":{"asset":"Vehicle","work_order":"Maintenance job","site":"Depot"}}'::jsonb, 20),
  ('workshops', 'Workshops & Service Centres',
   'Mechanical, technical and equipment workshops managing job cards, diagnostics, labour, parts, bookings and customer repairs.',
   array['Mechanical workshops','Equipment repair centres','Technical service centres'],
   '{"focus_areas":["job cards","workshop bookings","diagnostics","labour","parts","customer repairs","quality checks"],"terminology":{"work_order":"Job card","asset":"Customer equipment","site":"Workshop"}}'::jsonb, 30),
  ('logistics-transport', 'Logistics & Transport',
   'Transport and logistics operations coordinating depots, vehicles, equipment, facilities, inspections, schedules and operational downtime.',
   array['Transport operators','Warehousing and distribution','Delivery fleets','Freight operations'],
   '{"focus_areas":["depots","fleet availability","equipment","inspections","downtime","operational schedules","warehouse facilities"],"terminology":{"site":"Depot / facility","work_order":"Maintenance task"}}'::jsonb, 40),
  ('hospitality-tourism', 'Hospitality & Tourism',
   'Accommodation and tourism businesses maintaining guest-facing facilities, rooms, buildings, grounds, plant, safety equipment and service areas.',
   array['Hotels','Lodges','Game reserves','Guest houses','Resorts'],
   '{"focus_areas":["buildings and rooms","guest facilities","grounds","plant and equipment","housekeeping maintenance","safety inspections","service requests"],"terminology":{"site":"Property / lodge","work_order":"Maintenance request","asset":"Facility asset"}}'::jsonb, 50),
  ('food-beverage', 'Food & Beverage',
   'Restaurants, bars and catering businesses maintaining kitchens, refrigeration, extraction, dining areas, bars and related equipment.',
   array['Restaurants','Bars','Cafes','Catering operations'],
   '{"focus_areas":["kitchen equipment","refrigeration","extraction systems","dining areas","bar equipment","hygiene and safety checks"],"terminology":{"site":"Venue","work_order":"Maintenance request"}}'::jsonb, 60),
  ('property-management-facilities', 'Property Management & Facilities',
   'Property and facilities operators responsible for buildings, estates, schools, apartment blocks, commercial properties, common areas, grounds and building services.',
   array['Schools and campuses','Apartment buildings','Residential estates','Commercial buildings','Property portfolios','Facilities management'],
   '{"focus_areas":["property portfolios","buildings and blocks","schools and campuses","estates and common areas","grounds","building services","inspections","tenant and occupant requests"],"terminology":{"site":"Property / building","work_order":"Facilities request","asset":"Building asset"}}'::jsonb, 70),
  ('manufacturing-industrial', 'Manufacturing & Industrial',
   'Manufacturing and industrial operations maintaining production equipment, plant, utilities, safety systems and operational facilities.',
   array['Factories','Production facilities','Industrial plants','Processing operations'],
   '{"focus_areas":["production equipment","plant maintenance","utilities","downtime","planned maintenance","safety systems","facility inspections"],"terminology":{"asset":"Plant / production asset","work_order":"Maintenance job","site":"Plant"}}'::jsonb, 80),
  ('general-maintenance', 'General Maintenance & Multi-service',
   'General maintenance contractors and organisations managing mixed assets, facilities, service requests, inspections and planned maintenance across different environments.',
   array['Maintenance contractors','Multi-trade service providers','Mixed-use facilities','General business premises'],
   '{"focus_areas":["assets","work orders","planned maintenance","inspections","suppliers","stock","facilities"],"terminology":{"asset":"Asset","work_order":"Work order","site":"Site"}}'::jsonb, 90)
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  business_examples = excluded.business_examples,
  default_configuration = excluded.default_configuration,
  sort_order = excluded.sort_order,
  is_active = true;

create table public.company_industry_profiles (
  company_id uuid primary key references public.companies(id) on delete cascade,
  primary_industry_slug text not null references public.industry_catalog(slug) on update cascade on delete restrict default 'general-maintenance',
  secondary_industry_slugs text[] not null default '{}'::text[],
  business_description text not null default '',
  configuration_overrides jsonb not null default '{}'::jsonb,
  config_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null,
  constraint company_industry_secondary_limit check (cardinality(secondary_industry_slugs) <= 8),
  constraint company_industry_overrides_object check (jsonb_typeof(configuration_overrides) = 'object'),
  constraint company_industry_version_positive check (config_version > 0)
);

create table public.company_industry_profile_revisions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  config_version integer not null,
  profile_snapshot jsonb not null,
  changed_by uuid null references public.profiles(id) on delete set null,
  change_note text not null default 'Industry profile saved',
  created_at timestamptz not null default now(),
  constraint company_industry_revision_version_unique unique (company_id, config_version),
  constraint company_industry_revision_snapshot_object check (jsonb_typeof(profile_snapshot) = 'object')
);

create index company_industry_profiles_primary_idx on public.company_industry_profiles(primary_industry_slug);
create index company_industry_profile_revisions_company_created_idx
  on public.company_industry_profile_revisions(company_id, created_at desc);

alter table public.industry_catalog enable row level security;
alter table public.company_industry_profiles enable row level security;
alter table public.company_industry_profile_revisions enable row level security;

grant select on public.industry_catalog to authenticated;
grant select, insert, update on public.company_industry_profiles to authenticated;
grant select on public.company_industry_profile_revisions to authenticated;

create policy industry_catalog_authenticated_read
  on public.industry_catalog for select to authenticated
  using (is_active = true);

create policy company_industry_profiles_company_read
  on public.company_industry_profiles for select to authenticated
  using (company_id = (select public.auth_company()));

create policy company_industry_profiles_owner_insert
  on public.company_industry_profiles for insert to authenticated
  with check (
    company_id = (select public.auth_company())
    and (select public.auth_role()) = 'owner'
  );

create policy company_industry_profiles_manager_update
  on public.company_industry_profiles for update to authenticated
  using (
    company_id = (select public.auth_company())
    and (select public.auth_role()) = any (array['owner','manager']::text[])
  )
  with check (
    company_id = (select public.auth_company())
    and (select public.auth_role()) = any (array['owner','manager']::text[])
  );

create policy company_industry_profile_revisions_company_read
  on public.company_industry_profile_revisions for select to authenticated
  using (company_id = (select public.auth_company()));

create or replace function public.validate_company_industry_profile()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
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

  new.secondary_industry_slugs := coalesce(new.secondary_industry_slugs, '{}'::text[]);
  new.business_description := left(coalesce(new.business_description, ''), 4000);
  return new;
end;
$$;

create or replace function public.version_company_industry_profile()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    if new.company_id <> old.company_id then
      raise exception 'A company industry profile cannot be moved to another company';
    end if;
    new.config_version := old.config_version + 1;
  else
    new.config_version := 1;
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

create or replace function public.audit_company_industry_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.company_industry_profile_revisions
    (company_id, config_version, profile_snapshot, changed_by, change_note)
  values (
    new.company_id,
    new.config_version,
    jsonb_build_object(
      'primary_industry_slug', new.primary_industry_slug,
      'secondary_industry_slugs', new.secondary_industry_slugs,
      'business_description', new.business_description,
      'configuration_overrides', new.configuration_overrides,
      'config_version', new.config_version
    ),
    auth.uid(),
    case when tg_op = 'INSERT' then 'Initial company industry profile' else 'Company industry profile updated' end
  );
  return new;
end;
$$;

create or replace function public.create_company_industry_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.company_industry_profiles (company_id, primary_industry_slug)
  values (new.id, 'general-maintenance')
  on conflict (company_id) do nothing;
  return new;
end;
$$;

revoke all on function public.audit_company_industry_profile() from public, anon, authenticated;
revoke all on function public.create_company_industry_profile() from public, anon, authenticated;

create trigger company_industry_profile_validate
  before insert or update on public.company_industry_profiles
  for each row execute function public.validate_company_industry_profile();

create trigger company_industry_profile_version
  before insert or update on public.company_industry_profiles
  for each row execute function public.version_company_industry_profile();

create trigger company_industry_profile_audit
  after insert or update on public.company_industry_profiles
  for each row execute function public.audit_company_industry_profile();

create trigger companies_create_industry_profile
  after insert on public.companies
  for each row execute function public.create_company_industry_profile();

insert into public.company_industry_profiles (company_id, primary_industry_slug)
select id, 'general-maintenance' from public.companies
on conflict (company_id) do nothing;
