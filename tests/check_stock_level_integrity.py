from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122203000_validate_stock_level_integrity.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
    "non-finite quantity rejection": "new.on_hand::text in ('nan','infinity','-infinity')",
    "negative quantity rejection": "new.on_hand < 0",
    "stock item tenant lookup": "from public.stock_items",
    "site tenant lookup": "from public.sites",
    "cross-tenant consistency guard": "v_item_company is distinct from new.company_id or v_site_company is distinct from new.company_id",
    "trigger coverage": "before insert or update of item_id,site_id,company_id,on_hand",
}
for label, marker in checks.items():
    if marker not in sql:
        raise SystemExit(f"Stock-level integrity regression missing: {label}")
print("Stock-level integrity regression: PASS")
