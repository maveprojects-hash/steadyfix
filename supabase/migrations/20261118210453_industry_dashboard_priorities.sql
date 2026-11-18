-- Industry templates can prioritise dashboard sections without hiding core CMMS modules.
update public.industry_catalog as c
set default_configuration = c.default_configuration ||
  jsonb_build_object('dashboard_priority_tabs', to_jsonb(v.dashboard_priority_tabs))
from (values
  ('automation', array['assets','work_orders','pm_schedules','stock_items','purchase_orders','inv','suppliers','mon','fleet']::text[]),
  ('fleet-management', array['fleet','work_orders','pm_schedules','assets','stock_items','mon','ohs','suppliers']::text[]),
  ('workshops', array['fleet','stock_items','work_orders','pm_schedules','suppliers','assets','ohs']::text[]),
  ('logistics-transport', array['fleet','work_orders','assets','pm_schedules','mon','ohs','stock_items']::text[]),
  ('hospitality-tourism', array['assets','work_orders','pm_schedules','ohs','stock_items','suppliers','mon','shifts']::text[]),
  ('food-beverage', array['assets','ohs','work_orders','pm_schedules','stock_items','suppliers','shutdowns']::text[]),
  ('property-management-facilities', array['assets','work_orders','pm_schedules','ohs','suppliers','stock_items','damage_reports','mon']::text[]),
  ('manufacturing-industrial', array['assets','pm_schedules','shutdowns','work_orders','ohs','stock_items','mon','fleet']::text[]),
  ('general-maintenance', array['work_orders','pm_schedules','assets','stock_items','ohs','fleet','suppliers','damage_reports']::text[])
) as v(slug, dashboard_priority_tabs)
where c.slug = v.slug;
