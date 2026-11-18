-- Electronic receiver signature for logistics proof of delivery.
begin;

create table if not exists public.logistics_pod_signoffs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  shipment_id uuid not null unique,
  receiver_name text not null check (length(btrim(receiver_name)) between 2 and 160),
  signature_points jsonb not null check (jsonb_typeof(signature_points)='array'),
  receiver_consent boolean not null default false check (receiver_consent=true),
  reference text,
  notes text,
  signed_by uuid not null references public.profiles(id) on delete restrict,
  signed_at timestamptz not null default now(),
  foreign key (shipment_id,company_id,site_id)
    references public.logistics_shipments(id,company_id,site_id) on delete cascade
);
create index if not exists logistics_pod_signoffs_site_idx
  on public.logistics_pod_signoffs(company_id,site_id,signed_at desc);
alter table public.logistics_pod_signoffs enable row level security;
drop policy if exists logistics_pod_signoffs_read on public.logistics_pod_signoffs;
create policy logistics_pod_signoffs_read on public.logistics_pod_signoffs
  for select to authenticated
  using (company_id=(select public.auth_company()) and (select public.auth_site_ok(site_id)));
revoke all on public.logistics_pod_signoffs from anon,authenticated;
grant select on public.logistics_pod_signoffs to authenticated;

create or replace function private.record_logistics_pod_signoff_impl(
  p_shipment_id uuid,
  p_receiver_name text,
  p_signature_points jsonb,
  p_reference text default null,
  p_notes text default null,
  p_receiver_consent boolean default false
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid:=public.auth_company();
  v_role text:=public.auth_role();
  v_site uuid;
  v_status text;
  v_stroke jsonb;
  v_point jsonb;
  v_x numeric;
  v_y numeric;
  v_total_points integer:=0;
  v_strokes integer:=0;
  v_signoff_id uuid;
  v_signed_at timestamptz;
begin
  if v_user is null or v_company is null then raise exception 'Authentication required'; end if;
  if v_role not in ('owner','manager','technician','storeman') then raise exception 'You are not allowed to capture proof of delivery'; end if;
  if p_receiver_consent is distinct from true then raise exception 'Receiver confirmation is required'; end if;
  if p_receiver_name is null or length(btrim(p_receiver_name))<2 or length(btrim(p_receiver_name))>160 then
    raise exception 'Enter the receiver full name';
  end if;
  if p_reference is not null and length(p_reference)>200 then raise exception 'Delivery reference is too long'; end if;
  if p_notes is not null and length(p_notes)>2000 then raise exception 'Delivery notes are too long'; end if;
  if p_signature_points is null or jsonb_typeof(p_signature_points)<>'array' then raise exception 'A receiver signature is required'; end if;
  v_strokes:=jsonb_array_length(p_signature_points);
  if v_strokes<1 or v_strokes>12 then raise exception 'Signature must contain between 1 and 12 strokes'; end if;
  for v_stroke in select value from jsonb_array_elements(p_signature_points) loop
    if jsonb_typeof(v_stroke)<>'array' or jsonb_array_length(v_stroke)<2 then raise exception 'Each signature stroke must contain at least two points'; end if;
    for v_point in select value from jsonb_array_elements(v_stroke) loop
      if jsonb_typeof(v_point)<>'object' or not (v_point ? 'x') or not (v_point ? 'y') then raise exception 'Signature point is invalid'; end if;
      begin
        v_x:=(v_point->>'x')::numeric;
        v_y:=(v_point->>'y')::numeric;
      exception when others then raise exception 'Signature coordinates must be numeric';
      end;
      if v_x<0 or v_x>1 or v_y<0 or v_y>1 then raise exception 'Signature coordinates are out of range'; end if;
      v_total_points:=v_total_points+1;
      if v_total_points>1000 then raise exception 'Signature contains too many points'; end if;
    end loop;
  end loop;
  if v_total_points<3 then raise exception 'Signature is too short'; end if;
  select s.site_id,s.status into v_site,v_status
  from public.logistics_shipments s where s.id=p_shipment_id and s.company_id=v_company;
  if not found then raise exception 'Consignment not found in this company'; end if;
  if not public.auth_site_ok(v_site) then raise exception 'You do not have access to this site'; end if;
  if v_status='delivered' then raise exception 'This consignment is already marked delivered'; end if;
  if v_status='returned' then raise exception 'A returned consignment cannot be marked delivered'; end if;
  insert into public.logistics_pod_signoffs(
    company_id,site_id,shipment_id,receiver_name,signature_points,receiver_consent,reference,notes,signed_by
  ) values (
    v_company,v_site,p_shipment_id,btrim(p_receiver_name),p_signature_points,true,
    nullif(btrim(p_reference),''),nullif(btrim(p_notes),''),v_user
  ) returning id,signed_at into v_signoff_id,v_signed_at;
  update public.logistics_shipments
  set status='delivered',delivered_at=v_signed_at,pod_recipient_name=btrim(p_receiver_name),
      pod_reference=nullif(btrim(p_reference),''),pod_notes=nullif(btrim(p_notes),'')
  where id=p_shipment_id and company_id=v_company and site_id=v_site;
  return jsonb_build_object('signoff_id',v_signoff_id,'signed_at',v_signed_at,'status','delivered');
end;
$$;
revoke all on function private.record_logistics_pod_signoff_impl(uuid,text,jsonb,text,text,boolean) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.record_logistics_pod_signoff_impl(uuid,text,jsonb,text,text,boolean) to authenticated;

create or replace function public.record_logistics_pod_signoff(
  p_shipment_id uuid,
  p_receiver_name text,
  p_signature_points jsonb,
  p_reference text default null,
  p_notes text default null,
  p_receiver_consent boolean default false
) returns jsonb
language sql
security invoker
set search_path=pg_catalog,public,private
as $$
  select private.record_logistics_pod_signoff_impl(
    p_shipment_id,p_receiver_name,p_signature_points,p_reference,p_notes,p_receiver_consent
  );
$$;
revoke all on function public.record_logistics_pod_signoff(uuid,text,jsonb,text,text,boolean) from public,anon;
grant execute on function public.record_logistics_pod_signoff(uuid,text,jsonb,text,text,boolean) to authenticated;

commit;
