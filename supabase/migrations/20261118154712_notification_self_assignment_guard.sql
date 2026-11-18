-- Suppress self-assignment alerts without suppressing reassignment alerts to the original creator.
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

  if new.assigned_to is distinct from auth.uid() then
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
