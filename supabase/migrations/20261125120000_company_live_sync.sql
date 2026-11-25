-- Company-wide live operational sync using minimal tenant-private Broadcast events.
-- The database emits only a table/operation invalidation; clients reload rows via RLS.
begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.broadcast_cmms_company_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_company_id uuid;
begin
  if tg_op = 'DELETE' then
    v_company_id := old.company_id;
  else
    v_company_id := new.company_id;
  end if;

  if v_company_id is null then
    return null;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'company_id', v_company_id,
      'table', tg_table_name,
      'operation', tg_op
    ),
    'cmms_change',
    'company:' || v_company_id::text || ':cmms-live',
    true
  );

  if tg_op = 'UPDATE' and old.company_id is distinct from new.company_id
     and old.company_id is not null then
    perform realtime.send(
      jsonb_build_object(
        'company_id', old.company_id,
        'table', tg_table_name,
        'operation', 'TENANT_MOVE'
      ),
      'cmms_change',
      'company:' || old.company_id::text || ':cmms-live',
      true
    );
  end if;

  return null;
end;
$$;

revoke all on function private.broadcast_cmms_company_change() from public, anon, authenticated;

-- A client may join only the private live channel belonging to its active company.
drop policy if exists cmms_company_live_sync_read on realtime.messages;
create policy cmms_company_live_sync_read
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and split_part((select realtime.topic()), ':', 2) = (select public.auth_company())::text
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.company_id = (select public.auth_company())
        and p.active = true
    )
  );

-- Cover every current tenant-owned public table, including new departments and
-- industry configuration tables, without exposing row contents on the channel.
do $$
declare
  v_table text;
begin
  for v_table in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'company_id'
      and a.attnum > 0 and not a.attisdropped
    where n.nspname = 'public'
      and c.relkind in ('r','p')
      and c.relrowsecurity
      and c.relname not in ('messages','notifications','company_conversations','conversation_members')
    order by c.relname
  loop
    execute format('drop trigger if exists cmms_company_live_change on public.%I', v_table);
    execute format(
      'create trigger cmms_company_live_change after insert or update or delete on public.%I for each row execute function private.broadcast_cmms_company_change()',
      v_table
    );
  end loop;
end $$;

commit;
