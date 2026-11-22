from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = next(root.glob("supabase/migrations/*_validate_gps_tracker_inputs.sql"))
sql = migration.read_text(encoding="utf-8").lower()
checks = {
    "finite coordinates": "not isfinite(p_lat) or not isfinite(p_lng)",
    "latitude and longitude bounds": "abs(p_lat) > 90 or abs(p_lng) > 180",
    "finite speed and speed bounds": "not isfinite(p_speed) or p_speed < 0 or p_speed > 300",
    "heading bounds": "not isfinite(p_heading) or p_heading < 0 or p_heading > 360",
    "odometer bounds": "not isfinite(p_odometer) or p_odometer < 0 or p_odometer > 10000000",
    "subscription check retained": "company_subscription_is_current(v.company_id)",
    "tenant assignment retained": "values (v.company_id, v.id, t, p_lat, p_lng",
    "tracker function grants retained": "to anon, authenticated",
}
for label, marker in checks.items():
    if marker not in sql:
        raise SystemExit(f"GPS ingestion regression missing: {label}")
print("GPS tracker numeric validation regression: PASS")
