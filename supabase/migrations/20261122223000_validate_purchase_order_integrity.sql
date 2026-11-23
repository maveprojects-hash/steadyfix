-- Guard purchase order tenant references and financial total.
create or replace function private.validate_purchase_order_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_site_company uuid;
  v_supplier_company uuid;
begin
  select s.company_id into v_site_company from public.sites s where s.id = new.site_id;
  if not found then raise exception 'Purchase order site does not exist'; end if;
  if v_site_company is distinct from new.company_id then
    raise exception 'Purchase order site must belong to the same company';
  end if;
  if new.supplier_id is not null then
    select s.company_id into v_supplier_company from public.suppliers s where s.id = new.supplier_id;
    if not found then raise exception 'Purchase order supplier does not exist'; end if;
    if v_supplier_company is distinct from new.company_id then
      raise exception 'Purchase order supplier must belong to the same company';
    end if;
  end if;
  if new.total_cost is not null and (new.total_cost::text in ('NaN','Infinity','-Infinity') or new.total_cost < 0) then
    raise exception 'Purchase order total must be finite and non-negative';
  end if;
  if new.lines is not null and jsonb_typeof(new.lines) <> 'array' then
    raise exception 'Purchase order lines must be an array';
  end if;
  return new;
end;
$$;

drop trigger if exists purchase_orders_integrity_guard on public.purchase_orders;
create trigger purchase_orders_integrity_guard
before insert or update of company_id,site_id,supplier_id,total_cost,lines
on public.purchase_orders
for each row execute function private.validate_purchase_order_integrity();
