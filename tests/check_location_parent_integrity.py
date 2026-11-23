from pathlib import Path
root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122235000_location_parent_integrity.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
 "self-parent guard": "new.parent_id = new.id",
 "same company check": "v_parent_company is distinct from new.company_id",
 "same site check": "v_parent_site is distinct from new.site_id",
 "recursive cycle detection": "with recursive ancestors(id,parent_id)",
 "cycle rejection": "location hierarchy cannot contain a cycle",
 "insert/update trigger": "before insert or update of parent_id,company_id,site_id",
}
for label, marker in checks.items():
 if marker not in sql: raise SystemExit(f"Location parent integrity missing: {label}")
print("Location parent integrity regression: PASS")
