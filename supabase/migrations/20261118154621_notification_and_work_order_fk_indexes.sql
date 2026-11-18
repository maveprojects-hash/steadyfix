-- Supporting indexes for the new notification table and core work-order relations.
create index if not exists notifications_company_idx on public.notifications (company_id);
create index if not exists notifications_site_idx on public.notifications (site_id);
create index if not exists notifications_work_order_idx on public.notifications (work_order_id);
create index if not exists work_orders_company_idx on public.work_orders (company_id);
create index if not exists work_orders_asset_idx on public.work_orders (asset_id);
create index if not exists work_orders_pm_schedule_idx on public.work_orders (pm_schedule_id);
create index if not exists work_orders_created_by_idx on public.work_orders (created_by);
