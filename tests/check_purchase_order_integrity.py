from pathlib import Path
root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122223000_validate_purchase_order_integrity.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
 "site tenant lookup": "from public.sites s where s.id = new.site_id",
 "site company enforcement": "v_site_company is distinct from new.company_id",
 "supplier tenant lookup": "from public.suppliers s where s.id = new.supplier_id",
 "supplier company enforcement": "v_supplier_company is distinct from new.company_id",
 "finite total guard": "new.total_cost::text in ('nan','infinity','-infinity')",
 "non-negative total": "new.total_cost < 0",
 "lines array validation": "jsonb_typeof(new.lines) <> 'array'",
 "trigger coverage": "before insert or update of company_id,site_id,supplier_id,total_cost,lines",
}
for label, marker in checks.items():
 if marker not in sql: raise SystemExit(f"Purchase-order integrity regression missing: {label}")
print("Purchase-order integrity regression: PASS")
