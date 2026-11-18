from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
html = (root / "maintdesk_app.html").read_text(encoding="utf-8")
scripts = re.findall(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, re.I | re.S)
if not scripts:
    raise SystemExit("No inline CMMS application script found")

with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8") as f:
    f.write("\n".join(scripts))
    f.flush()
    subprocess.run(["node", "--check", f.name], check=True)

required_ui = [
    "STAFF('assigned_to')",
    "startNotifications()",
    "postgres_changes",
    "markAllNotificationsRead()",
    "enableDesktopNotifications()",
]
for marker in required_ui:
    if marker not in html:
        raise SystemExit(f"Missing notification UI behavior: {marker}")

migration = next((root / "supabase" / "migrations").glob("*_work_order_notifications.sql"))
sql = migration.read_text(encoding="utf-8")
for marker in [
    "enable row level security",
    "notifications_read_own",
    "notifications_mark_own_read",
    "validate_work_order_assignee",
    "notify_work_order_assignee",
    "supabase_realtime",
]:
    if marker not in sql.lower():
        raise SystemExit(f"Missing notification migration safeguard: {marker}")

print("CMMS inline JavaScript syntax and notification safeguards: PASS")
