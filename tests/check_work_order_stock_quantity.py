from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122200000_validate_work_order_stock_quantity.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
    "non-finite quantity guard": "p_quantity::text in ('nan','infinity','-infinity')",
    "positive quantity guard": "p_quantity <= 0",
    "row lock before balance update": "for update",
    "company-scoped work order": "w.id = p_work_order_id and w.company_id = v_company",
    "company-scoped stock item": "i.id = p_stock_item_id and i.company_id = v_company",
    "site-scoped stock balance": "sl.item_id = p_stock_item_id and sl.site_id = v_site and sl.company_id = v_company",
    "quantity deducted from stock": "v_remaining := v_on_hand - p_quantity",
    "material issue recorded": "insert into public.work_order_material_issues",
}
for label, marker in checks.items():
    if marker not in sql:
        raise SystemExit(f"Work-order stock quantity regression missing: {label}")
print("Work-order stock quantity validation regression: PASS")
