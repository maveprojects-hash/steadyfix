-- Fleet vehicle assignment lifecycle with tenant/site isolation and atomic conflict prevention.
begin;
create table if not exists public.fleet_vehicle_assignments (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 site_id uuid not null references public.sites(id) on delete cascade,
 vehicle_id uuid not null references public.vehicles(id) on delete restrict,
 assigned_user_id uuid not null references public.profiles(id) on delete restrict,
 assigned_by uuid not null references public.profiles(id) on delete restrict,
 assigned_at timestamptz not null default now(), released_at timestamptz,
 status text not null default 'active' check(status in ('active','released','cancelled')),
 notes text,
 check((status='active' and released_at is null) or (status<>'active' and released_at is not null))
);
create index if not exists fleet_vehicle_assignments_site_recent_idx on public.fleet_vehicle_assignments(company_id,site_id,assigned_at desc);
create index if not exists fleet_vehicle_assignments_user_idx on public.fleet_vehicle_assignments(company_id,assigned_user_id,status);
create unique index if not exists fleet_vehicle_assignment_one_active_vehicle_uidx on public.fleet_vehicle_assignments(vehicle_id) where status='active';
alter table public.fleet_vehicle_assignments enable row level security;
drop policy if exists fleet_vehicle_assignments_read on public.fleet_vehicle_assignments;
create policy fleet_vehicle_assignments_read on public.fleet_vehicle_assignments for select to authenticated using(company_id=(select public.auth_company()) and (select public.auth_site_ok(site_id)));
revoke all on public.fleet_vehicle_assignments from anon,authenticated;
grant select on public.fleet_vehicle_assignments to authenticated;

create or replace function public.validate_fleet_vehicle_assignment()
returns trigger language plpgsql set search_path=pg_catalog,public,pg_temp as $$
declare v_vehicle_company uuid; v_vehicle_site uuid; v_driver_company uuid; v_driver_active boolean; v_site_company uuid;
begin
 select company_id,site_id into v_vehicle_company,v_vehicle_site from public.vehicles where id=new.vehicle_id;
 if not found or v_vehicle_company<>new.company_id or v_vehicle_site<>new.site_id then raise exception 'Assignment vehicle must belong to the same company and site'; end if;
 select company_id,active into v_driver_company,v_driver_active from public.profiles where id=new.assigned_user_id;
 if not found or v_driver_company<>new.company_id or not coalesce(v_driver_active,false) then raise exception 'Assigned driver must be an active member of this company'; end if;
 select company_id into v_site_company from public.sites where id=new.site_id;
 if not found or v_site_company<>new.company_id then raise exception 'Assignment site must belong to the same company'; end if;
 if new.status='active' and new.released_at is not null then raise exception 'Active assignment cannot have a release timestamp'; end if;
 return new;
end; $$;
revoke all on function public.validate_fleet_vehicle_assignment() from public,anon,authenticated;
drop trigger if exists fleet_vehicle_assignment_validate on public.fleet_vehicle_assignments;
create trigger fleet_vehicle_assignment_validate before insert or update on public.fleet_vehicle_assignments for each row execute function public.validate_fleet_vehicle_assignment();

create or replace function public.assign_fleet_vehicle(p_vehicle_id uuid,p_assigned_user_id uuid,p_notes text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_user uuid:=auth.uid(); v_company uuid:=public.auth_company(); v_role text:=public.auth_role(); v_site uuid; v_status text; v_driver_company uuid; v_driver_active boolean; v_assignment uuid;
begin
 if v_user is null or v_company is null then raise exception 'Authentication required'; end if;
 if v_role not in ('owner','manager') then raise exception 'Only company owners or managers may assign vehicles'; end if;
 select site_id,status into v_site,v_status from public.vehicles where id=p_vehicle_id and company_id=v_company for update;
 if not found then raise exception 'Vehicle not found in this company'; end if;
 if not public.auth_site_ok(v_site) then raise exception 'You do not have access to this site'; end if;
 if v_status<>'available' then raise exception 'Vehicle is not available for assignment'; end if;
 select company_id,active into v_driver_company,v_driver_active from public.profiles where id=p_assigned_user_id;
 if not found or v_driver_company<>v_company or not coalesce(v_driver_active,false) then raise exception 'Driver must be an active member of this company'; end if;
 if not exists(select 1 from public.user_sites where user_id=p_assigned_user_id and site_id=v_site) then raise exception 'Driver is not authorized for this site'; end if;
 insert into public.fleet_vehicle_assignments(company_id,site_id,vehicle_id,assigned_user_id,assigned_by,notes) values(v_company,v_site,p_vehicle_id,p_assigned_user_id,v_user,nullif(btrim(p_notes),'')) returning id into v_assignment;
 update public.vehicles set status='in_use' where id=p_vehicle_id and company_id=v_company and site_id=v_site;
 if not found then raise exception 'Vehicle status could not be updated'; end if;
 return v_assignment;
end; $$;
revoke all on function public.assign_fleet_vehicle(uuid,uuid,text) from public,anon;
grant execute on function public.assign_fleet_vehicle(uuid,uuid,text) to authenticated;

create or replace function public.release_fleet_vehicle_assignment(p_assignment_id uuid,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_user uuid:=auth.uid(); v_company uuid:=public.auth_company(); v_role text:=public.auth_role(); v_vehicle uuid; v_site uuid; v_status text;
begin
 if v_user is null or v_company is null then raise exception 'Authentication required'; end if;
 if v_role not in ('owner','manager') then raise exception 'Only company owners or managers may release vehicles'; end if;
 select vehicle_id,site_id,status into v_vehicle,v_site,v_status from public.fleet_vehicle_assignments where id=p_assignment_id and company_id=v_company for update;
 if not found then raise exception 'Assignment not found in this company'; end if;
 if not public.auth_site_ok(v_site) then raise exception 'You do not have access to this site'; end if;
 if v_status<>'active' then raise exception 'Assignment is already closed'; end if;
 update public.fleet_vehicle_assignments set status='released',released_at=now(),notes=case when nullif(btrim(p_notes),'") is null then notes else concat_ws(E'\n',notes,'Release: '||btrim(p_notes)) end where id=p_assignment_id and company_id=v_company and status='active';
 update public.vehicles set status='available' where id=v_vehicle and company_id=v_company and site_id=v_site and status='in_use';
 if not found then raise exception 'Vehicle could not be returned to available status'; end if;
 return jsonb_build_object('ok',true,'vehicle_id',v_vehicle,'released_at',now());
end; $$;
revoke all on function public.release_fleet_vehicle_assignment(uuid,text) from public,anon;
grant execute on function public.release_fleet_vehicle_assignment(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
