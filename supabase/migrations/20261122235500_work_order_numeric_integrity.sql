-- Reject invalid work-order financial and measurement values, including numeric NaN/infinity.
begin;
create or replace function public.validate_work_order_numeric_integrity()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if new.labour_cost is not null and (new.labour_cost < 0 or new.labour_cost in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Labour cost must be finite and non-negative'; end if;
  if new.other_cost is not null and (new.other_cost < 0 or new.other_cost in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Other cost must be finite and non-negative'; end if;
  if new.parts_cost is not null and (new.parts_cost < 0 or new.parts_cost in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Parts cost must be finite and non-negative'; end if;
  if new.labour_hours < 0 or new.labour_hours in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Labour hours must be finite and non-negative'; end if;
  if new.meter_reading is not null and (new.meter_reading < 0 or new.meter_reading in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Meter reading must be finite and non-negative'; end if;
  return new;
end;
$function$;
drop trigger if exists work_orders_numeric_integrity_guard on public.work_orders;
create trigger work_orders_numeric_integrity_guard
before insert or update of labour_cost,other_cost,parts_cost,labour_hours,meter_reading on public.work_orders
for each row execute function public.validate_work_order_numeric_integrity();
revoke all on function public.validate_work_order_numeric_integrity() from public;
grant execute on function public.validate_work_order_numeric_integrity() to authenticated;
commit;
