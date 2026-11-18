-- Automation (copier and office-equipment service) operations.
-- Additive changes only: existing work orders, assets, customers and documents remain intact.

alter table public.assets
  add column if not exists customer_id uuid references public.customers(id) on delete set null,
  add column if not exists manufacturer text,
  add column if not exists model text,
  add column if not exists meter_reading numeric,
  add column if not exists meter_unit text not null default 'pages';

alter table public.work_orders
  add column if not exists job_number text default ('SF-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  add column if not exists customer_id uuid references public.customers(id) on delete set null,
  add column if not exists service_type text not null default 'callout',
  add column if not exists reported_problem text,
  add column if not exists diagnosis text,
  add column if not exists work_performed text,
  add column if not exists labour_hours numeric not null default 0,
  add column if not exists meter_reading numeric,
  add column if not exists customer_approval_status text not null default 'pending';

alter table public.documents
  add column if not exists contract_type text,
  add column if not exists start_date date,
  add column if not exists end_date date,
  add column if not exists billing_cycle text not null default 'monthly',
  add column if not exists monthly_fee numeric not null default 0,
  add column if not exists response_hours numeric,
  add column if not exists included_pages numeric,
  add column if not exists overage_rate numeric,
  add column if not exists covered_devices jsonb not null default '[]'::jsonb;

alter table public.assets
  add constraint assets_meter_reading_nonnegative
    check (meter_reading is null or meter_reading >= 0),
  add constraint assets_meter_unit_valid
    check (meter_unit in ('pages', 'prints', 'copies'));

alter table public.work_orders
  add constraint work_orders_labour_hours_nonnegative
    check (labour_hours >= 0),
  add constraint work_orders_meter_reading_nonnegative
    check (meter_reading is null or meter_reading >= 0),
  add constraint work_orders_customer_approval_valid
    check (customer_approval_status in ('pending', 'approved', 'declined', 'not_required'));

alter table public.documents
  add constraint documents_contract_covered_devices_array
    check (jsonb_typeof(covered_devices) = 'array'),
  add constraint documents_contract_amounts_nonnegative
    check (monthly_fee >= 0 and (response_hours is null or response_hours >= 0)
      and (included_pages is null or included_pages >= 0)
      and (overage_rate is null or overage_rate >= 0));

create unique index if not exists work_orders_company_job_number_uidx
  on public.work_orders(company_id, job_number)
  where job_number is not null and job_number <> '';

create index if not exists assets_company_customer_idx
  on public.assets(company_id, customer_id)
  where customer_id is not null;

create index if not exists documents_company_kind_created_idx
  on public.documents(company_id, kind, created_at desc);

-- Technicians need to see customer contact details for assigned service calls.
-- The existing all-actions customer policy remains manager-only.
create policy customers_service_team_read
  on public.customers
  for select
  to authenticated
  using (
    company_id = (select public.auth_company())
    and (select public.auth_role()) = any (array['owner','manager','technician']::text[])
  );

-- Validate linked records against the authenticated tenant and current site.
create or replace function public.validate_automation_service_links()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_table_name = 'assets' then
    if new.customer_id is not null and not exists (
      select 1 from public.customers c
      where c.id = new.customer_id and c.company_id = new.company_id
    ) then
      raise exception 'Equipment customer must belong to the same company';
    end if;
  elsif tg_table_name = 'work_orders' then
    if new.customer_id is not null and not exists (
      select 1 from public.customers c
      where c.id = new.customer_id and c.company_id = new.company_id
    ) then
      raise exception 'Service job customer must belong to the same company';
    end if;
    if new.asset_id is not null and not exists (
      select 1 from public.assets a
      where a.id = new.asset_id
        and a.company_id = new.company_id
        and a.site_id = new.site_id
    ) then
      raise exception 'Service job equipment must belong to the same company and site';
    end if;
  elsif tg_table_name = 'documents' and new.kind = 'service_contract' then
    if new.customer_id is not null and not exists (
      select 1 from public.customers c
      where c.id = new.customer_id and c.company_id = new.company_id
    ) then
      raise exception 'Service contract customer must belong to the same company';
    end if;
    if new.end_date is not null and new.start_date is not null and new.end_date < new.start_date then
      raise exception 'Service contract end date cannot be before its start date';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.validate_automation_service_links() from public, anon, authenticated;

drop trigger if exists assets_validate_automation_customer on public.assets;
create trigger assets_validate_automation_customer
  before insert or update of company_id, customer_id on public.assets
  for each row execute function public.validate_automation_service_links();

drop trigger if exists work_orders_validate_automation_links on public.work_orders;
create trigger work_orders_validate_automation_links
  before insert or update of company_id, site_id, customer_id, asset_id on public.work_orders
  for each row execute function public.validate_automation_service_links();

drop trigger if exists documents_validate_service_contract on public.documents;
create trigger documents_validate_service_contract
  before insert or update of company_id, kind, customer_id, start_date, end_date on public.documents
  for each row execute function public.validate_automation_service_links();
