from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122233000_validate_stock_level_location_integrity.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
    "location lookup": "from public.locations",
    "location company enforcement": "v_location_company is distinct from new.company_id",
    "location site enforcement": "v_location_site is distinct from new.site_id",
    "null location supported": "if new.location_id is not null then",
    "trigger coverage": "before insert or update of company_id,site_id,location_id",
}
for label, marker in checks.items():
    if marker not in sql:
        raise SystemExit(f"Stock location integrity regression missing: {label}")
print("Stock location integrity regression: PASS")
