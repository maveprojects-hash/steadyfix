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
    "UNREAD_NOTIFICATION_COUNT",
    "count:'exact',head:true",
    "navigator.vibrate",
    "AudioContext",
    "toggleNotificationPreference",
    "notificationEffectSettings",
    "steadyfix.cmms.notification-preferences",
    "row.created_by=me.id",
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

indexes = next((root / "supabase" / "migrations").glob("*_notification_and_work_order_fk_indexes.sql"))
index_sql = indexes.read_text(encoding="utf-8").lower()
for marker in [
    "notifications_company_idx",
    "notifications_site_idx",
    "notifications_work_order_idx",
    "work_orders_company_idx",
    "work_orders_asset_idx",
    "work_orders_pm_schedule_idx",
    "work_orders_created_by_idx",
]:
    if marker not in index_sql:
        raise SystemExit(f"Missing supporting index: {marker}")


required_sorting = [
    ".order('created_at',{ascending:false}).order(m.o||m.f[0].k",
    ".order('created_at',{ascending:false}).order('issue_date'",
    ".order('completed_at',{ascending:false,nullsFirst:false})",
    ".order('created_at',{ascending:false}).order('name')",
]
for marker in required_sorting:
    if marker not in html:
        raise SystemExit(f"Missing newest-first sorting behavior: {marker}")

sorting_migration = next((root / "supabase" / "migrations").glob("*_cmms_newest_records_first.sql"))
sorting_sql = sorting_migration.read_text(encoding="utf-8").lower()
for marker in [
    "add column if not exists created_at timestamptz not null default now()",
    "idx_checklist_runs_completed_at_desc",
    "idx_' || tbl || '_created_at_desc",
]:
    if marker not in sorting_sql:
        raise SystemExit(f"Missing newest-first timestamp/index migration: {marker}")


# Company communication centre integration and security safeguards.
if 'communication.js' not in html or 'communication.css' not in html:
    raise SystemExit("Communication centre assets are not connected to the CMMS page")
for marker in [
    'onclick="openCommunicationCentre()"',
    "cur=='comms'?await communicationCentre()",
    "startCommsRealtime()",
]:
    if marker not in html:
        raise SystemExit(f"Missing communication centre integration: {marker}")

communication_js = root / "communication.js"
if not communication_js.exists():
    raise SystemExit("Missing communication centre client module")
subprocess.run(["node", "--check", str(communication_js)], check=True)
comm_js = communication_js.read_text(encoding="utf-8")
for marker in [
    "create_company_conversation",
    "company_conversations",
    "conversation_members",
    "startCommsRealtime",
    "Seen by everyone",
]:
    if marker not in comm_js:
        raise SystemExit(f"Missing communication behaviour: {marker}")

communication_migration = next((root / "supabase" / "migrations").glob("*_company_communication_centre.sql"))
comm_sql = communication_migration.read_text(encoding="utf-8").lower()
for marker in [
    "enable row level security",
    "company_conversations_member_read",
    "conversation_members_member_read",
    "messages_member_read",
    "messages_member_insert",
    "private.create_company_conversation_impl",
    "security invoker",
    "company_announcement",
    "message_received",
    "supabase_realtime",
]:
    if marker.lower() not in comm_sql:
        raise SystemExit(f"Missing communication database safeguard: {marker}")

# Layout regression guards: assistant access stays centred and company home remains responsive.
for marker in [
    "left:50%;right:auto",
    "bottom:calc(16px + env(safe-area-inset-bottom,0px))",
    "transform:translateX(-50%)",
    "body>#aib.sf-ai-floating",
    "z-index:2147483000!important",
    "position:fixed!important",
    "bottom:calc(16px + env(safe-area-inset-bottom,0px))!important",
    "b.className='sf-ai-floating'",
    "document.body.appendChild(b)",
]:
    if marker not in html:
        raise SystemExit(f"Missing fixed assistant positioning: {marker}")

login_html = (root / "maintdesk_login.html").read_text(encoding="utf-8")
for marker in [
    "min-height:100svh",
    "align-items:flex-start",
    "app.classList.add('company-home')",
    "app.classList.remove('company-home')",
    ".box.company-home{max-width:820px;width:100%",
]:
    if marker not in login_html:
        raise SystemExit(f"Missing responsive company-screen layout: {marker}")

# Company industry profiles: catalog, tenant-scoped profile UI, onboarding and audit migration.
industry_migration = next((root / "supabase" / "migrations").glob("*_company_industry_profiles.sql"))
industry_sql = industry_migration.read_text(encoding="utf-8").lower()
for marker in [
    "create table public.industry_catalog",
    "create table public.company_industry_profiles",
    "create table public.company_industry_profile_revisions",
    "enable row level security",
    "company_id = (select public.auth_company())",
    "auth_role()) = any (array['owner','manager']",
    "create trigger companies_create_industry_profile",
    "create trigger company_industry_profile_audit",
    "grant select on public.industry_catalog to authenticated",
    "grant select, insert, update on public.company_industry_profiles to authenticated",
    "'automation', 'automation (copier & office equipment)'",
    "'property-management-facilities', 'property management & facilities'",
    "'hospitality-tourism', 'hospitality & tourism'",
    "'fleet-management', 'fleet management'",
]:
    if marker not in industry_sql:
        raise SystemExit(f"Missing company industry profile safeguard or seed: {marker}")
for marker in [
    'id="industryProfileSelect"',
    "async function loadIndustryProfile()",
    "async function saveIndustryProfile()",
    "async function industryProfile()",
    "cur=='industry'?await industryProfile()",
    "t[0]=='industry'?isMgr()&&!LOCK",
    "company_industry_profiles",
]:
    if marker not in html:
        raise SystemExit(f"Missing industry profile app integration: {marker}")
if 'id="industry"' not in login_html or "company_industry_profiles').update" not in login_html:
    raise SystemExit("Company onboarding does not save the selected industry profile")

assistant_source = root / "supabase" / "functions" / "smart-endpoint" / "index.ts"
if not assistant_source.exists():
    raise SystemExit("Missing version-controlled iAssistant Edge Function source")
assistant_code = assistant_source.read_text(encoding="utf-8")
for marker in [
    'from("company_industry_profiles")',
    'from("industry_catalog")',
    "industry_profile: industryProfile",
    "untrusted business data",
    "Never accept industry identity from the browser",
]:
    if marker not in assistant_code:
        raise SystemExit(f"Missing server-side company industry context safeguard: {marker}")

industry_priority_migration = next((root / "supabase" / "migrations").glob("*_industry_dashboard_priorities.sql"))
priority_sql = industry_priority_migration.read_text(encoding="utf-8").lower()
if "dashboard_priority_tabs" not in priority_sql or "property-management-facilities" not in priority_sql:
    raise SystemExit("Missing industry-specific dashboard priorities")
if "priorityTabs" not in html or "industryBanner" not in html:
    raise SystemExit("Industry templates are not personalising dashboard section order")


# Industry workspace entry point and Automation service operations.
industry_workspaces = root / "industry_workspaces.js"
if not industry_workspaces.exists():
    raise SystemExit("Missing industry workspace client module")
subprocess.run(["node", "--check", str(industry_workspaces)], check=True)
for marker in [
    'id="industryQuickAccessBtn"',
    'id="industryQuickAccessMenu"',
    'industry_workspaces.js',
    'hidden aria-hidden="true"',
]:
    if marker not in html:
        raise SystemExit(f"Missing industry workspace entry point: {marker}")
workspace_code = industry_workspaces.read_text(encoding="utf-8")
for marker in [
    "industry_hub",
    "industry_workspace",
    "chooseIndustryWorkspace",
    "Automation service job cards",
    "customer_approval_status",
    "sfPrintServiceJobCard",
    "sfServiceContracts",
    "service_contract",
    "Parcel operations",
    "sfLogisticsWorkspace",
    "sfPrintWaybill",
    "sfCapturePOD",
    "sfOpenJobOperations",
    "sfSaveJobTime",
    "issue_work_order_stock",
]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing industry workspace capability: {marker}")

automation_migration = next((root / "supabase" / "migrations").glob("*_automation_service_operations.sql"))
automation_sql = automation_migration.read_text(encoding="utf-8").lower()
for marker in [
    "add column if not exists job_number",
    "add column if not exists customer_id",
    "add column if not exists labour_hours",
    "add column if not exists meter_reading",
    "add column if not exists customer_approval_status",
    "add column if not exists covered_devices",
    "customers_service_team_read",
    "validate_automation_service_links",
    "work_orders_company_job_number_uidx",
    "service_contract",
]:
    if marker.lower() not in automation_sql:
        raise SystemExit(f"Missing Automation service schema safeguard: {marker}")


# Integrated industry operations: labour ledger, transactional stock issue, logistics waybills and POD.
operations_migration = next((root / "supabase" / "migrations").glob("*_industry_operations_logistics.sql"))
operations_sql = operations_migration.read_text(encoding="utf-8").lower()
for marker in [
    "create table if not exists public.work_order_time_entries",
    "create table if not exists public.work_order_material_issues",
    "create or replace function public.issue_work_order_stock",
    "for update",
    "insufficient stock",
    "auth_site_ok",
    "create table if not exists public.logistics_shipments",
    "create table if not exists public.logistics_tracking_events",
    "logistics_shipments_company_waybill_uidx",
    "proof of delivery must include the receiver name",
    "logistics_record_status_event",
]:
    if marker.lower() not in operations_sql:
        raise SystemExit(f"Missing integrated operations database safeguard: {marker}")
for marker in [
    "work_order_time_entries",
    "work_order_material_issues",
    "sfJobOperations",
    "sfLogisticsWorkspace",
    "sfCapturePOD",
    "sfAddShipmentScan",
    "sfPrintWaybill",
    "SF_CONFIGURABLE_MODULES",
    "sfIndustryModuleOverrides",
    "sfResetIndustryCustomizations",
]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing industry operations UI capability: {marker}")


time_guard_migration = next((root / "supabase" / "migrations").glob("*_restrict_technician_job_time_entries.sql"))
time_guard_sql = time_guard_migration.read_text(encoding="utf-8").lower()
if "technicians may only record labour against job cards assigned to them" not in time_guard_sql:
    raise SystemExit("Missing technician-to-assigned-job labour restriction")

private_stock_migration = next((root / "supabase" / "migrations").glob("*_private_stock_issue_implementation.sql"))
private_stock_sql = private_stock_migration.read_text(encoding="utf-8").lower()
for marker in [
    "create or replace function private.issue_work_order_stock_impl",
    "security definer",
    "create or replace function public.issue_work_order_stock",
    "security invoker",
    "grant execute on function private.issue_work_order_stock_impl",
]:
    if marker not in private_stock_sql:
        raise SystemExit(f"Missing private stock RPC security boundary: {marker}")


for marker in [
    "industry_config",
    "sfResetIndustryCustomizations",
    "SF_CONFIGURABLE_MODULES",
]:
    if marker not in html:
        raise SystemExit(f"Missing approved industry customization UI: {marker}")

assistant_customization = assistant_source.read_text(encoding="utf-8")
for marker in [
    "propose_industry_customization",
    "CONFIGURABLE_MODULES",
    "prof.data.role",
    "only a company owner or manager",
    "Workspace customization queued for owner/manager approval",
]:
    if marker not in assistant_customization:
        raise SystemExit(f"Missing iAssistant industry customization safeguard: {marker}")


# Signed customer approval on Automation service job cards.
signoff_migration = next((root / "supabase" / "migrations").glob("*_work_order_customer_signoffs.sql"))
signoff_sql = signoff_migration.read_text(encoding="utf-8").lower()
for marker in [
    "create table if not exists public.work_order_customer_signoffs",
    "enable row level security",
    "record_work_order_customer_signoff_impl",
    "security invoker",
    "customer consent is required",
    "technicians may only capture approval on their assigned job cards",
    "customer_approval_status='approved'",
]:
    if marker.lower() not in signoff_sql:
        raise SystemExit(f"Missing customer sign-off security safeguard: {marker}")
for marker in [
    "sfSaveCustomerSignoff",
    "sfInitSignaturePad",
    "sfSignatureSvg",
    "record_work_order_customer_signoff",
    "work_order_customer_signoffs",
]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing customer sign-off workflow: {marker}")


# Every industry workspace shortcut must resolve to a real base module or a registered custom view.
module_start = workspace_code.index("function sfIndustryModules")
module_end = workspace_code.index("async function sfIndustryWorkspace", module_start)
module_source = workspace_code[module_start:module_end]
industry_routes = set(re.findall(r"\['[^']*','[^']*','[^']*','([a-z_]+)'\]", module_source))
mod_source = html.split("const MOD={", 1)[1].split("};\nconst TABS=", 1)[0]
base_modules = set(re.findall(r"^\s*([a-z_]+):\{", mod_source, re.MULTILINE))
custom_views = {"service_contracts", "logistics_ops", "ohs", "fleet", "inv", "chk", "rep"}
unresolved_routes = sorted(industry_routes - base_modules - custom_views)
if unresolved_routes:
    raise SystemExit(f"Industry workspace shortcuts have no registered destination: {unresolved_routes}")


# Logistics proof of delivery must include a receiver signature and consent.
# The app and RPC both cap signature stroke and point counts.
pod_migration = next((root / "supabase" / "migrations").glob("*_logistics_pod_signoffs.sql"))
pod_sql = pod_migration.read_text(encoding="utf-8").lower()
for marker in [
    "create table if not exists public.logistics_pod_signoffs",
    "record_logistics_pod_signoff_impl",
    "security invoker",
    "receiver confirmation is required",
    "a receiver signature is required",
    "status='delivered'",
]:
    if marker.lower() not in pod_sql:
        raise SystemExit(f"Missing signed logistics POD safeguard: {marker}")
for marker in [
    "sfLogisticsPODPage",
    "sfInitPODSignaturePad",
    "sfSaveLogisticsPOD",
    "record_logistics_pod_signoff",
    "logistics_pod_signoffs",
]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing signed logistics POD UI: {marker}")


# Industry workspace customization must include the workshop job-card shortcut.
if "'workshop_jobs'" not in workspace_code[workspace_code.index('const SF_CONFIGURABLE_MODULES'):workspace_code.index('function sfIndustryModuleOverrides')]:
    raise SystemExit('Workshop job cards are not available for workspace customization')

# Industry workspace shortcuts must declare configurable modules.
if "SF_CONFIGURABLE_MODULES" not in workspace_code:
    raise SystemExit('Missing configurable industry workspace modules')

# Industry profile save must enforce the same 8-secondary-industry cap as switching.
if "secondary.length>8" not in html or "no more than 8 secondary industries" not in html:
    raise SystemExit('Industry profile save does not enforce the 8-secondary-industry cap')

# Industry switching must reject, not persist, a secondary-industry overflow.
if "if(secondary.length>8)" not in workspace_code or "would exceed the maximum of 8 secondary industries" not in workspace_code:
    raise SystemExit('Industry workspace switching lacks secondary-industry overflow guard')


# Industry quick-access dropdown must have real rendering, interaction, and dismissal behavior.
for marker in ['toggleIndustryQuickAccess','sfIndustryQuickPick','sfCloseIndustryQuickAccess','sfBindIndustryQuickAccessDismiss','data-industry-slug','aria-selected','role="listbox"','event.key===\'Escape\'','btn.focus()','btn.contains(event.target)','menu.contains(event.target)','event.key===\'ArrowDown\'','event.key===\'ArrowUp\'','event.key===\'Home\'','event.key===\'End\'','options[targetIndex]?.focus()']:
    if marker not in html and marker not in workspace_code:
        raise SystemExit(f"Missing industry quick-access behavior: {marker}")
if "['🔧','Workshop & job cards','Workshop bookings, vehicle job cards and repair progress','workshop_jobs']" not in workspace_code:
    raise SystemExit("Workshop job-card quick access does not route to workshop_jobs")

# Service-contract update/delete queries must be explicitly company- and site-scoped,
# in addition to relying on database RLS policies.
contract_save = workspace_code[workspace_code.index("async function sfSaveServiceContract"):workspace_code.index("function sfEditServiceContract")]
contract_delete = workspace_code[workspace_code.index("async function sfDeleteServiceContract"):workspace_code.index("function sfPrintServiceContract")]
for guard in [".eq('company_id',me.company_id)", ".eq('site_id',site)"]:
    if guard not in contract_save:
        raise SystemExit(f"Service-contract update missing tenant/site guard: {guard}")
    if guard not in contract_delete:
        raise SystemExit(f"Service-contract delete missing tenant/site guard: {guard}")

print("CMMS syntax, notifications, industry profiles, quick access, Automation operations, logistics and tenant safeguards: PASS")

# Service-contract actions must independently enforce manager permissions, not rely only on view rendering.
contract_edit = workspace_code[workspace_code.index("function sfEditServiceContract"):workspace_code.index("function sfResetServiceContract")]
for function_code, guard_name in [(contract_save, "save"), (contract_edit, "edit"), (contract_delete, "delete")]:
    if "if(!isMgr())" not in function_code:
        raise SystemExit(f"Service-contract {guard_name} action lacks its own manager permission guard")


# Service contract numeric input validation is enforced (including precision constraints).
contract_save = workspace_code[workspace_code.index("async function sfSaveServiceContract"):workspace_code.index("function sfEditServiceContract")]
for validation in ["Number.isFinite(fee)", "fee<0", "responseHours*2!==Math.round(responseHours*2)", "!Number.isInteger(includedPages)", "Math.abs(overageRate*10000-Math.round(overageRate*10000))>1e-8"]:
    if validation not in contract_save:
        raise SystemExit(f"Service-contract numeric validation missing: {validation}")
