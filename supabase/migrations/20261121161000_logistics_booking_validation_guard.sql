-- Enforce shipment booking bounds and non-blank required fields at the database boundary.
begin;

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
  if nullif(btrim(new.waybill_no),'') is null then
    raise exception 'Waybill number is required';
  end if;
  if nullif(btrim(new.recipient_name),'') is null then
    raise exception 'Recipient name is required';
  end if;
  if nullif(btrim(new.origin_address),'') is null then
    raise exception 'Origin address is required';
  end if;
  if nullif(btrim(new.destination_address),'') is null then
    raise exception 'Destination address is required';
  end if;
  if new.package_count is null or new.package_count<1 or new.package_count>10000 then
    raise exception 'Package count must be between 1 and 10000';
  end if;
  if new.weight_kg is not null and (new.weight_kg<0 or new.weight_kg>1000000) then
    raise exception 'Shipment weight must be between 0 and 1000000 kg';
  end if;
  if new.service_level not in ('standard','express','overnight','same_day') then
    raise exception 'Invalid shipment service level';
  end if;
    if new.status='delivered' and (new.delivered_at is null or nullif(btrim(new.pod_recipient_name),'') is null) then
    raise exception 'Proof of delivery must include the receiver name before marking delivered';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

commit;
