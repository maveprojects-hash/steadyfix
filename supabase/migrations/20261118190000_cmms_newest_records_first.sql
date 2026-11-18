-- Give every user-managed CMMS record a consistent insertion timestamp.
-- Existing data is preserved; older rows receive the migration timestamp.
DO $$
DECLARE
  tbl text;
  tables text[] := ARRAY[
    'locations','sites','profiles','suppliers','assets','pm_schedules',
    'checklist_templates','stock_items','purchase_orders','shutdowns',
    'shifts','budgets','expenses','customers','vehicles','sensors',
    'staff_members','roster_shifts','invitations'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    IF to_regclass(format('public.%I', tbl)) IS NOT NULL THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now()',
        tbl
      );
      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS %I ON public.%I (created_at DESC)',
        'idx_' || tbl || '_created_at_desc',
        tbl
      );
    END IF;
  END LOOP;
END $$;

-- Keep checklist history ordered by the moment it was completed.
CREATE INDEX IF NOT EXISTS idx_checklist_runs_completed_at_desc
  ON public.checklist_runs (completed_at DESC);
