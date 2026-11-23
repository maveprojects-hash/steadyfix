from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122213000_validate_stock_item_integrity.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
    "finite cost guard": "new.unit_cost::text in ('nan','infinity','-infinity')",
    "non-negative cost guard": "new.unit_cost < 0",
    "finite reorder threshold guard": "new.min_level::text in ('nan','infinity','-infinity')",
    "non-negative reorder threshold guard": "new.min_level < 0",
    "supplier company lookup": "from public.suppliers s",
    "supplier tenant enforcement": "v_supplier_company is distinct from new.company_id",
    "trigger covers tenant, costs, threshold, supplier": "before insert or update of company_id,unit_cost,min_level,supplier_id",
}
for label, marker in checks.items():
    if marker not in sql:
        raise SystemExit(f"Stock-item integrity regression missing: {label}")
print("Stock-item integrity regression: PASS")
