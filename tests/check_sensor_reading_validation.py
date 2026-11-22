from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20261122173000_validate_sensor_readings.sql"
sql = migration.read_text(encoding="utf-8").lower()
checks = {
    "unknown sensor key guard": "if not found then raise exception 'unknown device key'",
    "subscription guard": "company_subscription_is_current(s.company_id)",
    "null and non-finite payload rejection": "p_value is null or p_value::text in ('nan', 'infinity', '-infinity')",
    "tenant-scoped insert": "insert into readings(company_id, sensor_id, value) values(s.company_id, s.id, p_value)",
    "alert threshold logic retained": "s.alert_min is not null and p_value < s.alert_min",
    "public execution revoked": "from public",
    "existing client grants retained": "to anon, authenticated",
}
for label, marker in checks.items():
    if marker not in sql:
        raise SystemExit(f"Sensor reading validation regression missing: {label}")
print("Sensor telemetry validation regression: PASS")
