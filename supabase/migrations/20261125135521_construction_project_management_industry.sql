-- Add Construction & Project Management as a selectable standard-layout industry.
-- This profile intentionally reuses existing CMMS project delivery, asset, cost,
-- procurement, stock, contractor, safety and inspection modules.
insert into public.industry_catalog
  (slug, name, description, business_examples, default_configuration, sort_order, is_active)
values
  (
    'construction-project-management',
    'Construction & Project Management',
    'Construction contractors and project teams coordinating site work, work packages, plant and equipment, materials, subcontractors, budgets, costs, safety and quality inspections.',
    array[
      'Building contractors',
      'Civil engineering projects',
      'Renovation and fit-out teams',
      'Facilities and maintenance projects',
      'Project management companies'
    ],
    '{
      "focus_areas":[
        "construction projects and site work",
        "work packages and task assignments",
        "plant, tools and equipment",
        "project budgets and recorded costs",
        "materials procurement and site stock",
        "subcontractors and suppliers",
        "site safety and compliance",
        "quality and progress inspections",
        "defects and corrective actions"
      ],
      "terminology":{
        "site":"Project site",
        "asset":"Plant / construction equipment",
        "work_order":"Project work package"
      },
      "dashboard_priority_tabs":[
        "work_orders",
        "assets",
        "bud",
        "inv",
        "purchase_orders",
        "suppliers",
        "stock_items",
        "ohs",
        "chk",
        "damage_reports",
        "pm_schedules"
      ]
    }'::jsonb,
    45,
    true
  )
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  business_examples = excluded.business_examples,
  default_configuration = excluded.default_configuration,
  sort_order = excluded.sort_order,
  is_active = true;
