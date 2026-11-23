from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122234000_validate_work_order_stock_cost.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
    "unit cost finite guard": "v_unit_cost::text in ('nan','infinity','-infinity')",
    "unit cost nonnegative guard": "v_unit_cost < 0",
    "computed total finite guard": "v_total::text in ('nan','infinity','-infinity')",
    "computed total nonnegative guard": "v_total < 0",
    "validation before issue record": "material issue total cost must be finite and non-negative",
}
for label, marker in checks.items():
    if marker not in sql:
        raise SystemExit(f"Stock issue cost integrity missing: {label}")
print("Stock issue cost integrity regression: PASS")
