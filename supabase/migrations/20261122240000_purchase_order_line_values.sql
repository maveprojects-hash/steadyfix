-- Validate every purchase order line's quantity and unit price, not just its aggregate total.
begin;
create or replace function private.validate_purchase_order_line_values()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_line jsonb;
  v_qty numeric;
  v_price numeric;
begin
  if new.lines is null then return new; end if;
  if jsonb_typeof(new.lines) <> 'array' then
    raise exception 'Purchase order lines must be an array';
  end if;
  for v_line in select value from jsonb_array_elements(new.lines)
  loop
    if jsonb_typeof(v_line) <> 'object'
       or jsonb_typeof(v_line->'q') IS DISTINCT FROM 'number'
       or jsonb_typeof(v_line->'p') IS DISTINCT FROM 'number' then
      raise exception 'Each purchase order line must have numeric quantity and unit price';
    end if;
    v_qty := (v_line->>'q')::numeric;
    v_price := (v_line->>'p')::numeric;
    if v_qty::text in ('NaN','Infinity','-Infinity') or v_qty <= 0 then
      raise exception 'Purchase order line quantity must be finite and greater than zero';
    end if;
    if v_price::text in ('NaN','Infinity','-Infinity') or v_price < 0 then
      raise exception 'Purchase order line unit price must be finite and non-negative';
    end if;
  end loop;
  return new;
end;
$function$;
drop trigger if exists purchase_order_line_values_guard on public.purchase_orders;
create trigger purchase_order_line_values_guard
before insert or update of lines on public.purchase_orders
for each row execute function private.validate_purchase_order_line_values();
revoke all on function private.validate_purchase_order_line_values() from public;
grant execute on function private.validate_purchase_order_line_values() to authenticated;
commit;
