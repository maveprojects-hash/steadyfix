from pathlib import Path
root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122240000_purchase_order_line_values.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
 "array guard": "jsonb_typeof(new.lines) <> 'array'",
 "object guard": "jsonb_typeof(v_line) <> 'object'",
 "quantity numeric type": "jsonb_typeof(v_line->'q') is distinct from 'number'",
 "price numeric type": "jsonb_typeof(v_line->'p') is distinct from 'number'",
 "finite quantity": "v_qty::text in ('nan','infinity','-infinity')",
 "positive quantity": "v_qty <= 0",
 "finite price": "v_price::text in ('nan','infinity','-infinity')",
 "nonnegative price": "v_price < 0",
 "lines trigger": "before insert or update of lines on public.purchase_orders",
}
for label, marker in checks.items():
 if marker not in sql: raise SystemExit(f"PO line validation missing: {label}")
print("Purchase order line validation regression: PASS")
