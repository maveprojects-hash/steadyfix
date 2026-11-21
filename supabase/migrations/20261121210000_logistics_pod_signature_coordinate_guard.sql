-- Reject null and NaN signature coordinates at the database boundary.
begin;

create or replace function public.guard_logistics_pod_signature_coordinates()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_stroke jsonb;
  v_point jsonb;
  v_x numeric;
  v_y numeric;
begin
  if jsonb_typeof(new.signature_points) <> 'array' then
    raise exception 'Signature coordinates must be an array';
  end if;
  for v_stroke in select value from jsonb_array_elements(new.signature_points) loop
    if jsonb_typeof(v_stroke) <> 'array' then
      raise exception 'Signature stroke must be an array';
    end if;
    for v_point in select value from jsonb_array_elements(v_stroke) loop
      if jsonb_typeof(v_point) <> 'object' or not (v_point ? 'x') or not (v_point ? 'y') then
        raise exception 'Signature point must include x and y coordinates';
      end if;
      begin
        v_x := (v_point->>'x')::numeric;
        v_y := (v_point->>'y')::numeric;
      exception when others then
        raise exception 'Signature coordinates must be numeric';
      end;
      if v_x is null or v_y is null or v_x = 'NaN'::numeric or v_y = 'NaN'::numeric
        or v_x < 0 or v_x > 1 or v_y < 0 or v_y > 1 then
        raise exception 'Signature coordinates must be finite values between 0 and 1';
      end if;
    end loop;
  end loop;
  return new;
end;
$$;

revoke all on function public.guard_logistics_pod_signature_coordinates() from public, anon, authenticated;
drop trigger if exists logistics_pod_signature_coordinates_guard on public.logistics_pod_signoffs;
create trigger logistics_pod_signature_coordinates_guard
before insert on public.logistics_pod_signoffs
for each row execute function public.guard_logistics_pod_signature_coordinates();

commit;
