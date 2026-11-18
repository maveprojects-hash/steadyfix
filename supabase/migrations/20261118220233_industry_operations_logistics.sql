-- Industry operations integration: technician labour, stock issue, logistics waybills and POD.
begin;

-- Detailed labour entries are immutable operational records; managers may correct/remove them.
create table if not exists public.work_order_time_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  technician_id uuid not null references public.profiles(id) on delete restrict,
  work_date date not null default current_date,
  hours numeric(8,2) not null check (hours > 0 and hours <= 24),
  hourly_rate numeric(12,2) not null default 0 check (hourly_rate >= 0),
  notes text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists work_order_time_entries_job_idx
  on public.work_order_time_entries(company_id, site_id, work_order_id, work_date desc);
create index if not exists work_order_time_entries_technician_idx
  on public.work_order_time_entries(company_id, technician_id, work_date desc);
alter table public.work_order_time_entries enable row level security;
drop policy if exists work_order_time_entries_read on public.work_order_time_entries;
create policy work_order_time_entries_read on public.work_order_time_entries
  for select to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id)));
drop policy if exists work_order_time_entries_insert on public.work_order_time_entries;
create policy work_order_time_entries_insert on public.work_order_time_entries
  for insert to authenticated
  with check (
    company_id = (select public.auth_company())
    and (select public.auth_site_ok(site_id))
    and created_by = (select auth.uid())
    and (
      (select public.auth_role()) in ('owner','manager')
      or ((select public.auth_role()) = 'technician' and technician_id = (select auth.uid()))
    )
  );
drop policy if exists work_order_time_entries_manager_update on public.work_order_time_entries;
create policy work_order_time_entries_manager_update on public.work_order_time_entries
  for update to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
         and (select public.auth_role()) in ('owner','manager'))
  with check (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
              and (select public.auth_role()) in ('owner','manager'));
drop policy if exists work_order_time_entries_manager_delete on public.work_order_time_entries;
create policy work_order_time_entries_manager_delete on public.work_order_time_entries
  for delete to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
         and (select public.auth_role()) in ('owner','manager'));
grant select, insert, update, delete on public.work_order_time_entries to authenticated;

-- Every stock issue is a separate immutable ledger entry tied to its job card.
create table if not exists public.work_order_material_issues (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  item_name text not null,
  unit text not null default 'each',
  quantity numeric(12,3) not null check (quantity > 0),
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
  total_cost numeric(14,2) not null check (total_cost >= 0),
  notes text,
  issued_by uuid not null references public.profiles(id) on delete restrict,
  issued_at timestamptz not null default now()
);
create index if not exists work_order_material_issues_job_idx
  on public.work_order_material_issues(company_id, site_id, work_order_id, issued_at desc);
alter table public.work_order_material_issues enable row level security;
drop policy if exists work_order_material_issues_read on public.work_order_material_issues;
create policy work_order_material_issues_read on public.work_order_material_issues
  for select to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id)));
revoke all on public.work_order_material_issues from anon, authenticated;
grant select on public.work_order_material_issues to authenticated;

create or replace function public.issue_work_order_stock(
  p_work_order_id uuid,
  p_stock_item_id uuid,
  p_quantity numeric,
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
  if p_quantity is null or p_quantity <= 0 then raise exception 'Issue quantity must be greater than zero'; end if;
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
$$;
revoke all on function public.issue_work_order_stock(uuid,uuid,numeric,text) from public, anon;
grant execute on function public.issue_work_order_stock(uuid,uuid,numeric,text) to authenticated;

-- Ensure labour entries cannot point at another company's job or staff member.
create or replace function public.validate_work_order_time_entry()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare v_company uuid; v_site uuid; v_staff_company uuid; v_active boolean;
begin
  select company_id,site_id into v_company,v_site from public.work_orders where id=new.work_order_id;
  if not found or v_company<>new.company_id or v_site<>new.site_id then
    raise exception 'Labour entry job card must belong to the same company and site';
  end if;
  select company_id,active into v_staff_company,v_active from public.profiles where id=new.technician_id;
  if not found or v_staff_company<>new.company_id or not v_active then
    raise exception 'Technician must be an active member of this company';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_work_order_time_entry() from public, anon, authenticated;
drop trigger if exists work_order_time_entries_validate on public.work_order_time_entries;
create trigger work_order_time_entries_validate before insert or update on public.work_order_time_entries
for each row execute function public.validate_work_order_time_entry();

-- Logistics consignments and scan history.
create table if not exists public.logistics_shipments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  waybill_no text not null,
  tracking_no text,
  sender_name text,
  recipient_name text not null,
  recipient_phone text,
  origin_address text not null,
  destination_address text not null,
  parcel_description text,
  package_count integer not null default 1 check (package_count > 0),
  weight_kg numeric(12,3) check (weight_kg is null or weight_kg >= 0),
  service_level text not null default 'standard' check (service_level in ('standard','express','overnight','same_day')),
  status text not null default 'booked' check (status in ('booked','collected','in_transit','at_depot','out_for_delivery','delivered','exception','returned')),
  expected_delivery date,
  dispatched_at timestamptz,
  delivered_at timestamptz,
  pod_recipient_name text,
  pod_reference text,
  pod_notes text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,company_id,site_id),
  check (status <> 'delivered' or (delivered_at is not null and nullif(btrim(pod_recipient_name),'') is not null))
);
create unique index if not exists logistics_shipments_company_waybill_uidx
  on public.logistics_shipments(company_id,waybill_no);
create index if not exists logistics_shipments_site_status_idx
  on public.logistics_shipments(company_id,site_id,status,created_at desc);
create index if not exists logistics_shipments_tracking_idx
  on public.logistics_shipments(company_id,tracking_no) where tracking_no is not null;

create table if not exists public.logistics_tracking_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  shipment_id uuid not null,
  event_type text not null check (event_type in ('created','status_change','scan','pod')),
  status text,
  location text,
  notes text,
  event_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  foreign key (shipment_id,company_id,site_id)
    references public.logistics_shipments(id,company_id,site_id) on delete cascade
);
create index if not exists logistics_tracking_events_shipment_idx
  on public.logistics_tracking_events(company_id,site_id,shipment_id,event_at desc);
alter table public.logistics_shipments enable row level security;
alter table public.logistics_tracking_events enable row level security;
drop policy if exists logistics_shipments_read on public.logistics_shipments;
create policy logistics_shipments_read on public.logistics_shipments
  for select to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id)));
drop policy if exists logistics_shipments_insert on public.logistics_shipments;
create policy logistics_shipments_insert on public.logistics_shipments
  for insert to authenticated
  with check (
    company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
    and created_by = (select auth.uid())
    and (select public.auth_role()) in ('owner','manager','technician','storeman')
  );
drop policy if exists logistics_shipments_update on public.logistics_shipments;
create policy logistics_shipments_update on public.logistics_shipments
  for update to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
         and (select public.auth_role()) in ('owner','manager','technician','storeman'))
  with check (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
              and (select public.auth_role()) in ('owner','manager','technician','storeman'));
drop policy if exists logistics_shipments_delete on public.logistics_shipments;
create policy logistics_shipments_delete on public.logistics_shipments
  for delete to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
         and (select public.auth_role()) in ('owner','manager'));
drop policy if exists logistics_tracking_events_read on public.logistics_tracking_events;
create policy logistics_tracking_events_read on public.logistics_tracking_events
  for select to authenticated
  using (company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id)));
drop policy if exists logistics_tracking_events_insert on public.logistics_tracking_events;
create policy logistics_tracking_events_insert on public.logistics_tracking_events
  for insert to authenticated
  with check (
    company_id = (select public.auth_company()) and (select public.auth_site_ok(site_id))
    and created_by = (select auth.uid())
    and (select public.auth_role()) in ('owner','manager','technician','storeman')
  );
grant select,insert,update,delete on public.logistics_shipments to authenticated;
grant select,insert on public.logistics_tracking_events to authenticated;

create or replace function public.validate_logistics_shipment()
returns trigger language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare v_site_company uuid;
begin
  select company_id into v_site_company from public.sites where id=new.site_id;
  if not found or v_site_company<>new.company_id then
    raise exception 'Shipment site must belong to the same company';
  end if;
  if new.status='delivered' and (new.delivered_at is null or nullif(btrim(new.pod_recipient_name),'') is null) then
    raise exception 'Proof of delivery must include the receiver name before marking delivered';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.validate_logistics_shipment() from public, anon, authenticated;
drop trigger if exists logistics_shipments_validate on public.logistics_shipments;
create trigger logistics_shipments_validate before insert or update on public.logistics_shipments
for each row execute function public.validate_logistics_shipment();

create or replace function public.logistics_record_status_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op='INSERT' then
    insert into public.logistics_tracking_events(company_id,site_id,shipment_id,event_type,status,notes,created_by)
    values(new.company_id,new.site_id,new.id,'created',new.status,'Waybill created',new.created_by);
  elsif old.status is distinct from new.status then
    insert into public.logistics_tracking_events(company_id,site_id,shipment_id,event_type,status,notes,created_by)
    values(new.company_id,new.site_id,new.id,
      case when new.status='delivered' then 'pod' else 'status_change' end,
      new.status,
      case when new.status='delivered' then 'Proof of delivery recorded for '||new.pod_recipient_name
           else 'Shipment status changed from '||old.status||' to '||new.status end,
      auth.uid());
  end if;
  return new;
end;
$$;
revoke all on function public.logistics_record_status_event() from public, anon, authenticated;
drop trigger if exists logistics_shipments_status_event on public.logistics_shipments;
create trigger logistics_shipments_status_event after insert or update of status on public.logistics_shipments
for each row execute function public.logistics_record_status_event();

commit;
