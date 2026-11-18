-- STEADYFIX CMMS company communication centre
-- Tenant-scoped conversations, messages, announcements and message notifications.

begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table if not exists public.company_conversations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('direct','group','announcement')),
  title text,
  direct_key text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique (id, company_id),
  check ((kind = 'direct' and direct_key is not null) or (kind <> 'direct' and direct_key is null))
);
create unique index if not exists company_conversations_direct_pair_uq
  on public.company_conversations(company_id, direct_key) where kind = 'direct';
create index if not exists company_conversations_company_last_idx
  on public.company_conversations(company_id, last_message_at desc);
create index if not exists company_conversations_created_by_idx
  on public.company_conversations(created_by);

create table if not exists public.conversation_members (
  conversation_id uuid not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  is_muted boolean not null default false,
  primary key (conversation_id, user_id),
  foreign key (conversation_id, company_id)
    references public.company_conversations(id, company_id) on delete cascade
);
create index if not exists conversation_members_user_idx
  on public.conversation_members(company_id, user_id, conversation_id);
create index if not exists conversation_members_conversation_company_idx
  on public.conversation_members(conversation_id, company_id);
create index if not exists conversation_members_user_fk_idx
  on public.conversation_members(user_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete restrict,
  body text not null check (char_length(btrim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  foreign key (conversation_id, company_id)
    references public.company_conversations(id, company_id) on delete cascade
);
create index if not exists messages_conversation_created_idx
  on public.messages(conversation_id, created_at desc);
create index if not exists messages_company_created_idx
  on public.messages(company_id, created_at desc);
create index if not exists messages_conversation_company_fk_idx
  on public.messages(conversation_id, company_id);
create index if not exists messages_sender_fk_idx
  on public.messages(sender_id);

alter table public.company_conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

create or replace function private.is_conversation_member(p_conversation_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.user_id = (select auth.uid())
      and cm.company_id = public.auth_company()
  );
$$;

create or replace function private.can_post_to_conversation(p_conversation_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.company_conversations c
    where c.id = p_conversation_id
      and c.company_id = public.auth_company()
      and exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = c.id
          and cm.company_id = c.company_id
          and cm.user_id = (select auth.uid())
      )
      and (c.kind <> 'announcement' or public.auth_role() in ('owner','manager'))
  );
$$;
revoke all on function private.is_conversation_member(uuid) from public, anon;
revoke all on function private.can_post_to_conversation(uuid) from public, anon;
grant execute on function private.is_conversation_member(uuid) to authenticated;
grant execute on function private.can_post_to_conversation(uuid) to authenticated;

drop policy if exists company_conversations_member_read on public.company_conversations;
create policy company_conversations_member_read
  on public.company_conversations for select to authenticated
  using (company_id = (select public.auth_company()) and private.is_conversation_member(id));
drop policy if exists conversation_members_member_read on public.conversation_members;
create policy conversation_members_member_read
  on public.conversation_members for select to authenticated
  using (company_id = (select public.auth_company()) and private.is_conversation_member(conversation_id));
drop policy if exists conversation_members_update_own on public.conversation_members;
create policy conversation_members_update_own
  on public.conversation_members for update to authenticated
  using (user_id = (select auth.uid()) and company_id = (select public.auth_company())
         and private.is_conversation_member(conversation_id))
  with check (user_id = (select auth.uid()) and company_id = (select public.auth_company())
              and private.is_conversation_member(conversation_id));
drop policy if exists messages_member_read on public.messages;
create policy messages_member_read
  on public.messages for select to authenticated
  using (company_id = (select public.auth_company()) and private.is_conversation_member(conversation_id));
drop policy if exists messages_member_insert on public.messages;
create policy messages_member_insert
  on public.messages for insert to authenticated
  with check (
    company_id = (select public.auth_company())
    and sender_id = (select auth.uid())
    and private.can_post_to_conversation(conversation_id)
    and char_length(btrim(body)) between 1 and 5000
  );

revoke all on public.company_conversations, public.conversation_members, public.messages from anon, authenticated;
grant select on public.company_conversations, public.conversation_members, public.messages to authenticated;
grant update (last_read_at, is_muted) on public.conversation_members to authenticated;
grant insert on public.messages to authenticated;

create or replace function private.create_company_conversation_impl(
  p_kind text, p_title text default null, p_member_ids uuid[] default '{}'::uuid[]
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_user uuid := auth.uid();
  v_company uuid;
  v_members uuid[];
  v_valid integer;
  v_id uuid;
  v_direct_key text;
  v_title text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select p.company_id into v_company from public.profiles p
  where p.id = v_user and p.active = true;
  if v_company is null then raise exception 'An active company staff profile is required'; end if;
  if p_kind not in ('direct','group','announcement') then raise exception 'Invalid conversation type'; end if;

  if p_kind = 'announcement' then
    if public.auth_role() not in ('owner','manager') then
      raise exception 'Only company owners and managers can publish announcements';
    end if;
    select array_agg(p.id order by p.id) into v_members
    from public.profiles p where p.company_id = v_company and p.active = true;
    v_title := nullif(btrim(p_title), '');
    if v_title is null then raise exception 'Announcement title is required'; end if;
  else
    select array_agg(x order by x) into v_members
    from (
      select distinct u as x
      from unnest(coalesce(p_member_ids, '{}'::uuid[]) || array[v_user]) as u
      where u is not null
    ) ids;
    if cardinality(v_members) < 2 then raise exception 'Choose at least one other active staff member'; end if;
    select count(*) into v_valid from public.profiles p
    where p.id = any(v_members) and p.company_id = v_company and p.active = true;
    if v_valid <> cardinality(v_members) then
      raise exception 'Every participant must be an active member of your company';
    end if;
    if p_kind = 'direct' and cardinality(v_members) <> 2 then
      raise exception 'A private chat must have exactly two participants';
    end if;
    if p_kind = 'group' then
      v_title := nullif(btrim(p_title), '');
      if v_title is null then v_title := 'Team group'; end if;
    end if;
  end if;

  if p_kind = 'direct' then
    select string_agg(x::text, ':' order by x::text) into v_direct_key from unnest(v_members) as x;
    insert into public.company_conversations(company_id,kind,direct_key,created_by)
    values (v_company,'direct',v_direct_key,v_user)
    on conflict (company_id,direct_key) where kind='direct' do nothing
    returning id into v_id;
    if v_id is null then
      select c.id into v_id from public.company_conversations c
      where c.company_id=v_company and c.kind='direct' and c.direct_key=v_direct_key;
    end if;
  else
    insert into public.company_conversations(company_id,kind,title,created_by)
    values (v_company,p_kind,v_title,v_user)
    returning id into v_id;
  end if;

  insert into public.conversation_members(conversation_id,company_id,user_id)
  select v_id,v_company,u from unnest(v_members) as u
  on conflict (conversation_id,user_id) do nothing;
  return v_id;
end;
$$;
revoke all on function private.create_company_conversation_impl(text,text,uuid[]) from public, anon;
grant execute on function private.create_company_conversation_impl(text,text,uuid[]) to authenticated;

create or replace function public.create_company_conversation(
  p_kind text, p_title text default null, p_member_ids uuid[] default '{}'::uuid[]
)
returns uuid language sql security invoker
set search_path = pg_catalog, public, private
as $$ select private.create_company_conversation_impl(p_kind,p_title,p_member_ids); $$;
revoke all on function public.create_company_conversation(text,text,uuid[]) from public, anon;
grant execute on function public.create_company_conversation(text,text,uuid[]) to authenticated;

create or replace function private.on_company_message_insert()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_kind text;
  v_title text;
  v_sender text;
  v_notification_type text;
  v_notification_title text;
begin
  select c.kind,c.title into v_kind,v_title from public.company_conversations c
  where c.id=new.conversation_id and c.company_id=new.company_id;
  update public.company_conversations set last_message_at=new.created_at,updated_at=now()
  where id=new.conversation_id and company_id=new.company_id;
  select p.full_name into v_sender from public.profiles p where p.id=new.sender_id;
  v_notification_type := case when v_kind='announcement' then 'company_announcement' else 'message_received' end;
  v_notification_title := case when v_kind='announcement' then coalesce(v_title,'Company announcement')
    else coalesce(v_sender,'A colleague') || ' sent you a message' end;
  insert into public.notifications(company_id,site_id,user_id,work_order_id,type,title,message)
  select new.company_id,null,cm.user_id,null,v_notification_type,v_notification_title,left(new.body,180)
  from public.conversation_members cm
  where cm.conversation_id=new.conversation_id and cm.company_id=new.company_id
    and cm.user_id <> new.sender_id;
  return new;
end;
$$;
revoke all on function private.on_company_message_insert() from public, anon;
drop trigger if exists company_message_after_insert on public.messages;
create trigger company_message_after_insert after insert on public.messages
for each row execute function private.on_company_message_insert();

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('work_order_assigned','message_received','company_announcement'));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

commit;
