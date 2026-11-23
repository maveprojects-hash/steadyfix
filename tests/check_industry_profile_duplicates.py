from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122150000_reject_duplicate_secondary_industries.sql"
sql = migration.read_text(encoding="utf-8").lower()
for marker in [
    "count(distinct slug)",
    "secondary_count <> distinct_secondary_count",
    "secondary industries cannot contain duplicates",
    "create or replace function public.validate_company_industry_profile()",
]:
    if marker not in sql:
        raise SystemExit(f"Missing duplicate-secondary-industry database guard: {marker}")
print("Industry profile duplicate-secondary validation: PASS")
