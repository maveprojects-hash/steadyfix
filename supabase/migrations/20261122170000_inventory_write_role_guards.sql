-- Inventory catalogue and stock balance writes are restricted to inventory-capable roles.
-- Tenant/site policies remain in force as permissive boundaries; these restrictive
-- role gates apply in addition to them for authenticated write operations.
begin;

drop policy if exists stock_items_inventory_insert_role_guard on public.stock_items;
create policy stock_items_inventory_insert_role_guard
  on public.stock_items as restrictive
  for insert to authenticated
  with check ((select public.auth_role()) in ('owner','manager','storeman'));

drop policy if exists stock_items_inventory_update_role_guard on public.stock_items;
create policy stock_items_inventory_update_role_guard
  on public.stock_items as restrictive
  for update to authenticated
  using ((select public.auth_role()) in ('owner','manager','storeman'))
  with check ((select public.auth_role()) in ('owner','manager','storeman'));

drop policy if exists stock_items_inventory_delete_role_guard on public.stock_items;
create policy stock_items_inventory_delete_role_guard
  on public.stock_items as restrictive
  for delete to authenticated
  using ((select public.auth_role()) in ('owner','manager','storeman'));

drop policy if exists stock_levels_inventory_insert_role_guard on public.stock_levels;
create policy stock_levels_inventory_insert_role_guard
  on public.stock_levels as restrictive
  for insert to authenticated
  with check ((select public.auth_role()) in ('owner','manager','storeman'));

drop policy if exists stock_levels_inventory_update_role_guard on public.stock_levels;
create policy stock_levels_inventory_update_role_guard
  on public.stock_levels as restrictive
  for update to authenticated
  using ((select public.auth_role()) in ('owner','manager','storeman'))
  with check ((select public.auth_role()) in ('owner','manager','storeman'));

drop policy if exists stock_levels_inventory_delete_role_guard on public.stock_levels;
create policy stock_levels_inventory_delete_role_guard
  on public.stock_levels as restrictive
  for delete to authenticated
  using ((select public.auth_role()) in ('owner','manager','storeman'));

commit;
