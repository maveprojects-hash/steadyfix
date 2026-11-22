from pathlib import Path
root = Path(__file__).resolve().parents[1]
sql = (root / "supabase/migrations/20261122235500_work_order_numeric_integrity.sql").read_text(encoding="utf-8").lower()
checks = {
 "labour cost finite guard": "new.labour_cost in ('nan'::numeric,'infinity'::numeric,'-infinity'::numeric)",
 "other cost finite guard": "new.other_cost in ('nan'::numeric,'infinity'::numeric,'-infinity'::numeric)",
 "parts cost finite guard": "new.parts_cost in ('nan'::numeric,'infinity'::numeric,'-infinity'::numeric)",
 "hours finite guard": "new.labour_hours in ('nan'::numeric,'infinity'::numeric,'-infinity'::numeric)",
 "meter finite guard": "new.meter_reading in ('nan'::numeric,'infinity'::numeric,'-infinity'::numeric)",
 "update trigger": "before insert or update of labour_cost,other_cost,parts_cost,labour_hours,meter_reading",
}
for label, marker in checks.items():
 if marker not in sql: raise SystemExit(f"Missing {label}")
print("Work-order numeric integrity regression: PASS")
