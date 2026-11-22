-- Validate stock item financial fields and supplier tenant ownership.
create or replace function private.validate_stock_item_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_supplier_company uuid;
begin
  if new.unit_cost is not null then
    if new.unit_cost::text in ('NaN','Infinity','-Infinity') or new.unit_cost < 0 then
      raise exception 'Stock item unit cost must be finite and non-negative';
    end if;
  end if;
  if new.min_level is not null then
    if new.min_level::text in ('NaN','Infinity','-Infinity') or new.min_level < 0 then
      raise exception 'Stock item minimum level must be finite and non-negative';
    end if;
  end if;
  if new.supplier_id is not null then
    select s.company_id into v_supplier_company
    from public.suppliers s
    where s.id = new.supplier_id;
    if not found then
      raise exception 'Supplier does not exist';
    end if;
    if v_supplier_company is distinct from new.company_id then
      raise exception 'Supplier must belong to the same company as the stock item';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists stock_items_integrity_guard on public.stock_items;
create trigger stock_items_integrity_guard
before insert or update of company_id,unit_cost,min_level,supplier_id
on public.stock_items
for each row execute function private.validate_stock_item_integrity();
