-- STEADYFIX CMMS: secure, per-user notifications for work-order assignments.
-- Additive only: existing work-order and tenant data is not rewritten.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  work_order_id uuid references public.work_orders(id) on delete cascade,
  type text not null default 'work_order_assigned'
    check (type in ('work_order_assigned')),
  title text not null,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_created_idx
  on public.notifications (user_id, created_at desc);
create index notifications_unread_user_idx
  on public.notifications (user_id, created_at desc)
  where read_at is null;

alter table public.notifications enable row level security;
revoke all on table public.notifications from anon, public;
grant select on table public.notifications to authenticated;
grant update (read_at) on table public.notifications to authenticated;

create policy notifications_read_own
  on public.notifications
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    and company_id = (select public.auth_company())
    and public.auth_site_ok(site_id)
  );

create policy notifications_mark_own_read
  on public.notifications
  for update
  to authenticated
  using (
    user_id = (select auth.uid())
    and company_id = (select public.auth_company())
    and public.auth_site_ok(site_id)
  )
  with check (
    user_id = (select auth.uid())
    and company_id = (select public.auth_company())
    and public.auth_site_ok(site_id)
  );

-- Validate assignment server-side so a forged client cannot assign work
-- to another tenant, a disabled account, or a person without site access.
create or replace function public.validate_work_order_assignee()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_name text;
  v_role text;
begin
  if tg_op = 'UPDATE'
     and new.assigned_to is not distinct from old.assigned_to
     and new.company_id is not distinct from old.company_id
     and new.site_id is not distinct from old.site_id then
    return new;
  end if;

  if new.assigned_to is null then
    return new;
  end if;

  select p.full_name, p.role
    into v_name, v_role
    from public.profiles p
   where p.id = new.assigned_to
     and p.company_id = new.company_id
     and p.active is true;

  if not found then
    raise exception 'Assigned staff account must be active and belong to this company.'
      using errcode = '23514';
  end if;

  if v_role not in ('owner', 'manager')
     and not exists (
       select 1
         from public.user_sites us
        where us.user_id = new.assigned_to
          and us.site_id = new.site_id
          and us.company_id = new.company_id
     ) then
    raise exception 'Assigned staff member does not have access to this site.'
      using errcode = '23514';
  end if;

  new.assigned_name := v_name;
  return new;
end;
$$;

revoke all on function public.validate_work_order_assignee() from public, anon, authenticated;

drop trigger if exists validate_work_order_assignee on public.work_orders;
create trigger validate_work_order_assignee
before insert or update on public.work_orders
for each row execute function public.validate_work_order_assignee();

-- Create a durable inbox record when a work order is first assigned or reassigned.
create or replace function public.notify_work_order_assignee()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.assigned_to is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.assigned_to is not distinct from old.assigned_to
     and new.site_id is not distinct from old.site_id
     and new.company_id is not distinct from old.company_id then
    return new;
  end if;

  if new.assigned_to is distinct from new.created_by then
    insert into public.notifications (
      company_id, site_id, user_id, work_order_id, type, title, message
    ) values (
      new.company_id,
      new.site_id,
      new.assigned_to,
      new.id,
      'work_order_assigned',
      'New work order assigned',
      'You have been assigned "' ||
        left(coalesce(nullif(btrim(new.title), ''), 'a work order'), 160) ||
        '". Priority: ' || upper(coalesce(new.priority, 'medium')) ||
        case when new.due_date is not null
          then '. Due: ' || to_char(new.due_date, 'DD Mon YYYY')
          else ''
        end
    );
  end if;

  return new;
end;
$$;

revoke all on function public.notify_work_order_assignee() from public, anon, authenticated;

drop trigger if exists notify_work_order_assignee on public.work_orders;
create trigger notify_work_order_assignee
after insert or update of assigned_to, site_id, company_id on public.work_orders
for each row execute function public.notify_work_order_assignee();

-- Realtime is used only to wake the assigned user's authenticated inbox.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$$;

comment on table public.notifications is
  'Private per-user STEADYFIX CMMS notifications. Rows are created by trusted database triggers; users can only read their own and mark them read.';
