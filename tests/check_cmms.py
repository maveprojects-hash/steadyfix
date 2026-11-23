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
for marker in ["active_department:cur", "Current department: ${ctx.active_department || \"not specified\"}"]:
    if marker not in html and marker not in assistant_code:
        raise SystemExit(f"Assistant missing active department context: {marker}")

for marker in ["retrieval_cap_reached", "Only the newest 200 records were retrieved before filtering"]:
    if marker not in assistant_code:
        raise SystemExit(f"Assistant record-search cap disclosure missing: {marker}")

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
    'onclick="openIndustryHub()"',
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


# Waybill printing must surface POD lookup errors rather than silently omit the signature.
waybill_print = workspace_code[workspace_code.index("async function sfPrintWaybill"):workspace_code.index("// Extend the existing navigation")]
if "if(pod.error){alert('Could not load proof of delivery for this waybill: '+pod.error.message);return;}" not in waybill_print:
    raise SystemExit("Waybill print must surface POD lookup errors instead of silently omitting signature")


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


# Tracking history is lazy-loaded per shipment, with bounded pages and tenant/site filters.
logistics_workspace = workspace_code[workspace_code.index("async function sfLogisticsWorkspace"):workspace_code.index("const SF_SHIPMENT_CREATE_LOCK")]
if "logistics_tracking_events').select('*').eq('company_id',me.company_id).eq('site_id',site).order('event_at'" in logistics_workspace:
    raise SystemExit("Logistics workspace must not eagerly fetch the full tracking event history")
lazy_history = workspace_code[workspace_code.index("async function sfLoadShipmentHistory"):workspace_code.index("async function sfLogisticsWorkspace")]
for marker in [
    "sfShipmentHistory_",
    "eq('company_id',me.company_id)",
    "eq('site_id',site)",
    "eq('shipment_id',id)",
    "pageSize=50",
    "range(offset,offset+pageSize-1)",
    "Load tracking history",
]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing lazy tracking history safeguard: {marker}")
if "data-offset" not in logistics_workspace or "Load more scans" not in lazy_history:
    raise SystemExit("Tracking history must support bounded paging")


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

print("CMMS syntax, notifications, industry profiles, Automation operations, logistics and tenant safeguards: PASS")

# Shipment tracking scan submission validation and duplicate-click protection.
for marker in [
    "const SF_SCAN_SUBMISSIONS=new Set()",
    "if(SF_SCAN_SUBMISSIONS.has(id))return;",
    "SF_SCAN_SUBMISSIONS.add(id)",
    "const location=locationInput.trim();if(!location)",
    "finally{SF_SCAN_SUBMISSIONS.delete(id);}"]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing shipment scan safeguard: {marker}")


# POD signatures reject null/NaN and out-of-range coordinates in a DB trigger.
signature_coordinate_guard = root / "supabase" / "migrations" / "20261121210000_logistics_pod_signature_coordinate_guard.sql"
if not signature_coordinate_guard.exists():
    raise SystemExit("Missing POD signature coordinate guard migration")
signature_coordinate_sql = signature_coordinate_guard.read_text(encoding="utf-8").lower()
for marker in [
    "guard_logistics_pod_signature_coordinates",
    "v_x is null or v_y is null",
    "v_x = 'nan'::numeric",
    "v_y = 'nan'::numeric",
    "signature coordinates must be finite values between 0 and 1",
    "before insert on public.logistics_pod_signoffs",
]:
    if marker not in signature_coordinate_sql:
        raise SystemExit(f"Missing POD signature coordinate safeguard: {marker}")

# Newly inserted logistics shipments must start booked; lifecycle transitions are guarded separately.
initial_status_guard = root / "supabase" / "migrations" / "20261121200000_logistics_booking_initial_status_guard.sql"
if not initial_status_guard.exists():
    raise SystemExit("Missing initial Logistics booked-status guard migration")
initial_status_sql = initial_status_guard.read_text(encoding="utf-8").lower()
for marker in [
    "guard_logistics_shipment_initial_status",
    "new.status is distinct from 'booked'",
    "new shipments must begin in booked status",
    "before insert on public.logistics_shipments",
]:
    if marker not in initial_status_sql:
        raise SystemExit(f"Missing initial shipment status safeguard: {marker}")

# Shipment status history is recorded by the database trigger, not a second UI insert.
if "event_type:'status_change',status,notes:'Status changed from '+shipment.status+' to '+status" in workspace_code:
    raise SystemExit("Shipment status history is duplicated by the UI")
logistics_migration = next((root / "supabase" / "migrations").glob("*_industry_operations_logistics.sql"))
logistics_sql = logistics_migration.read_text(encoding="utf-8").lower()
if "logistics_record_status_event" not in logistics_sql or "logistics_shipments_status_event" not in logistics_sql:
    raise SystemExit("Database shipment status-event trigger is missing")

# Tracking history should not silently truncate to only eight events per shipment.
if "const history=events.filter(e=>e.shipment_id===x.id).slice(0,8);" in workspace_code:
    raise SystemExit("Shipment tracking history is truncated to eight events")
if "const history=eventsByShipment.get(x.id)||[];" in workspace_code:
    raise SystemExit("Tracking history must not be eagerly assembled for every shipment")

# Shipment tracking status-transition guard coverage.
for marker in [
    "const SF_SHIPMENT_TRANSITIONS={booked:['collected','exception']",
    "if(status===shipment.status)return;",
    "Invalid shipment status transition:",
    "if(!(SF_SHIPMENT_TRANSITIONS[shipment.status]||[]).includes(status))",
]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing shipment status transition safeguard: {marker}")

# Shipment creation input validation and duplicate-submit lock.
for marker in [
    "const SF_SHIPMENT_CREATE_LOCK={active:false}",
    "if(SF_SHIPMENT_CREATE_LOCK.active)return;",
    "Number.isInteger(packageCount)",
    "Number.isFinite(weight)",
    "finally{SF_SHIPMENT_CREATE_LOCK.active=false;}"
]:
    if marker not in workspace_code:
        raise SystemExit(f"Missing shipment creation safeguard: {marker}")


# Database-level shipment lifecycle guard, with delivery gated by signed POD.
transition_migration = next((root / "supabase" / "migrations").glob("*_logistics_status_transition_guard.sql"))
transition_sql = transition_migration.read_text(encoding="utf-8").lower()
for marker in [
    "guard_logistics_shipment_status_transition",
    "logistics_shipments_status_transition_guard",
    "invalid shipment status transition",
    "old.status='out_for_delivery' and new.status in ('delivered','at_depot','exception')",
    "old.status='exception' and new.status in ('booked','collected','in_transit','at_depot','out_for_delivery','returned')",
    "shipment delivery requires a valid signed proof of delivery",
    "from public.logistics_pod_signoffs p",
    "p.receiver_consent=true",
    "p.signed_at=new.delivered_at",
    "btrim(p.receiver_name)=btrim(new.pod_recipient_name)",
    "p.reference is not distinct from nullif(btrim(new.pod_reference),'')",
    "p.notes is not distinct from nullif(btrim(new.pod_notes),'')",
]:
    if marker not in transition_sql:
        raise SystemExit(f"Missing database shipment transition safeguard: {marker}")
# Signed POD RPC inserts signoff before setting delivered; transition guard validates that order.
pod_impl = pod_sql[pod_sql.find("record_logistics_pod_signoff_impl"):]
if pod_impl.find("insert into public.logistics_pod_signoffs") < 0 or pod_impl.find("update public.logistics_shipments") < 0 or pod_impl.find("insert into public.logistics_pod_signoffs") > pod_impl.find("update public.logistics_shipments"):
    raise SystemExit("POD must persist receiver signoff before delivery status update")


# Concurrent POD submissions are serialized by locking the shipment row before status checks.
pod_lock_migration = next((root / "supabase" / "migrations").glob("*_logistics_pod_submission_lock.sql"))
pod_lock_sql = pod_lock_migration.read_text(encoding="utf-8").lower()
if "for update;" not in pod_lock_sql:
    raise SystemExit("Concurrent POD submission must lock its shipment row")
lock_select = pod_lock_sql.find("from public.logistics_shipments s")
signoff_insert = pod_lock_sql.find("insert into public.logistics_pod_signoffs")
if lock_select < 0 or signoff_insert < 0 or lock_select > signoff_insert:
    raise SystemExit("POD shipment row must be locked before signoff insert")


# Logistics database safeguards: POD row-lock syntax and scan-only user event writes.
pod_lock_migration = next((root / "supabase" / "migrations").glob("*_logistics_pod_submission_lock.sql"))
pod_lock_sql = pod_lock_migration.read_text(encoding="utf-8").lower()
lock_select_start = pod_lock_sql.find("from public.logistics_shipments s")
lock_select_end = pod_lock_sql.find("for update;", lock_select_start)
if lock_select_start < 0 or lock_select_end < 0:
    raise SystemExit("POD submission must lock the shipment row with SELECT ... FOR UPDATE")
lock_statement = pod_lock_sql[lock_select_start:lock_select_end]
if ";" in lock_statement:
    raise SystemExit("POD shipment SELECT must not terminate before FOR UPDATE")
compact_lock = re.sub(r"\s+", "", lock_statement)
if "wheres.id=p_shipment_idands.company_id=v_company" not in compact_lock:
    raise SystemExit("POD row lock must scope the shipment to its company")
if "for update;" not in pod_lock_sql:
    raise SystemExit("POD shipment row lock missing statement terminator")

scan_guard_migration = next((root / "supabase" / "migrations").glob("*_logistics_tracking_scan_insert_guard.sql"))
scan_guard_sql = scan_guard_migration.read_text(encoding="utf-8").lower()
for marker in [
    "event_type = 'scan'",
    "location is not null",
    "length(btrim(location)) > 0",
    "length(notes) <= 2000",
    "logistics_tracking_events.shipment_id",
    "logistics_tracking_events.company_id",
    "logistics_tracking_events.site_id",
    "logistics_tracking_events.status",
]:
    if marker not in scan_guard_sql:
        raise SystemExit(f"Missing logistics tracking scan insert restriction: {marker}")
if "event_type = 'status_change'" in scan_guard_sql or "event_type = 'pod'" in scan_guard_sql:
    raise SystemExit("User tracking event policy must not allow status-change or POD inserts")


# Tracking scan locations are bounded at the database boundary and validated in the UI.
scan_location_guard = root / "supabase" / "migrations" / "20261121220000_logistics_scan_location_length_guard.sql"
if not scan_location_guard.exists():
    raise SystemExit("Missing Logistics scan-location length guard migration")
scan_location_sql = scan_location_guard.read_text(encoding="utf-8").lower()
if "length(btrim(location)) between 1 and 200" not in scan_location_sql:
    raise SystemExit("Tracking scan locations must be bounded to 200 characters")
if "if(location.length>200)" not in workspace_code.replace(" ", ""):
    raise SystemExit("Tracking scan UI must reject locations longer than 200 characters")

# Shipment identity guard: immutable booking/company/site attribution and waybill.
identity_guard_migration = next((root / "supabase" / "migrations").glob("*_logistics_shipment_identity_guard.sql"))
identity_guard_sql = identity_guard_migration.read_text(encoding="utf-8").lower()
for marker in [
    "create or replace function public.guard_logistics_shipment_identity",
    "new.id is distinct from old.id",
    "new.company_id is distinct from old.company_id",
    "new.site_id is distinct from old.site_id",
    "new.waybill_no is distinct from old.waybill_no",
    "new.created_by is distinct from old.created_by",
    "new.created_at is distinct from old.created_at",
    "shipment identity and waybill cannot be changed after booking",
    "before update on public.logistics_shipments",
]:
    if marker not in identity_guard_sql:
        raise SystemExit(f"Missing shipment identity safeguard: {marker}")


# Logistics tracking history must be on-demand and paged per shipment.
industry_text = (root / "industry_workspaces.js").read_text(encoding="utf-8")
logistics_workspace = industry_text[industry_text.index("async function sfLogisticsWorkspace()"):industry_text.index("const SF_SHIPMENT_CREATE_LOCK")]
lazy_history = industry_text[industry_text.index("async function sfLoadShipmentHistory"):industry_text.index("async function sfLogisticsWorkspace")]
if "logistics_tracking_events').select('*')" in logistics_workspace:
    raise SystemExit("Logistics workspace must not eagerly load all tracking events")
for marker in ["pageSize=50", "eq('company_id',me.company_id)", "eq('site_id',site)", "eq('shipment_id',id)", ".range(offset,offset+pageSize-1)", "order('event_at',{ascending:false}).order('id',{ascending:false})"]:
    if marker not in lazy_history:
        raise SystemExit(f"Logistics per-shipment history paging missing: {marker}")
if "Load tracking history" not in logistics_workspace or "Load more scans" not in lazy_history:
    raise SystemExit("Logistics history load controls are missing")


# Logistics shipment edit-role guard: technicians/storemen cannot mutate booking fields.
role_guard_migration = next((root / "supabase" / "migrations").glob("*_logistics_role_update_guard.sql"))
role_guard_sql = role_guard_migration.read_text(encoding="utf-8").lower()
for marker in [
    "guard_logistics_shipment_role_updates",
    "v_role in ('owner','manager')",
    "v_role not in ('technician','storeman')",
    "new.recipient_name is distinct from old.recipient_name",
    "new.origin_address is distinct from old.origin_address",
    "new.destination_address is distinct from old.destination_address",
    "new.delivered_at is distinct from old.delivered_at",
    "new.status='delivered'",
    "public.logistics_pod_signoffs p",
    "new.pod_recipient_name is distinct from old.pod_recipient_name",
    "old.status is distinct from 'delivered'",
    "p.signed_at=new.delivered_at",
    "btrim(p.receiver_name)=btrim(new.pod_recipient_name)",
    "p.reference is not distinct from nullif(btrim(new.pod_reference),'')",
    "p.notes is not distinct from nullif(btrim(new.pod_notes),'')",
    "new.package_count is distinct from old.package_count",
    "only owners and managers may edit shipment booking details",
    "before update on public.logistics_shipments",
]:
    if marker not in role_guard_sql:
        raise SystemExit(f"Missing shipment edit-role safeguard: {marker}")

# Null/unknown auth roles must not bypass Logistics shipment edit restrictions.
null_role_guard = root / "supabase" / "migrations" / "20261122100000_logistics_role_null_guard.sql"
if not null_role_guard.exists():
    raise SystemExit("Missing null-role Logistics guard migration")
null_role_sql = null_role_guard.read_text(encoding="utf-8").lower()
if "if v_role is null or v_role not in ('technician','storeman')" not in null_role_sql:
    raise SystemExit("Null/unknown Logistics roles must be rejected")

# Logistics database booking-validation guard: reject blank required fields and oversized booking inputs.
booking_validation_migration = next((root / "supabase" / "migrations").glob("*_logistics_booking_validation_guard.sql"))
booking_validation_sql = booking_validation_migration.read_text(encoding="utf-8").lower()
for marker in [
    "nullif(btrim(new.waybill_no),'') is null",
    "nullif(btrim(new.recipient_name),'') is null",
    "nullif(btrim(new.origin_address),'') is null",
    "nullif(btrim(new.destination_address),'') is null",
    "new.package_count>10000",
    "new.weight_kg>1000000",
    "new.updated_at:=now()",
]:
    if marker not in re.sub(r"\\s+", "", booking_validation_sql) and marker not in booking_validation_sql:
        raise SystemExit(f"Missing Logistics booking validation: {marker}")


# Unknown/null operational roles must be explicitly rejected (SQL NULL semantics).
role_null_guard = root / "supabase" / "migrations" / "20261122100000_logistics_role_null_guard.sql"
if not role_null_guard.exists():
    raise SystemExit("Missing Logistics null-role guard migration")
role_null_sql = role_null_guard.read_text(encoding="utf-8").lower()
for marker in [
    "if v_role is null or v_role not in ('technician','storeman')",
    "raise exception 'you are not allowed to update this shipment'",
]:
    if marker not in role_null_sql:
        raise SystemExit(f"Missing Logistics null-role rejection: {marker}")

# Terminal shipments cannot receive user-created scan events.
terminal_scan_guard = root / "supabase" / "migrations" / "20261121182000_logistics_terminal_scan_guard.sql"
if not terminal_scan_guard.exists():
    raise SystemExit("Missing terminal shipment scan guard migration")
terminal_scan_sql = terminal_scan_guard.read_text(encoding="utf-8").lower()
for marker in [
    "drop policy if exists logistics_tracking_events_insert",
    "create policy logistics_tracking_events_insert",
    "s.status not in ('delivered','returned')",
]:
    if marker not in terminal_scan_sql:
        raise SystemExit(f"Missing terminal scan restriction: {marker}")

# Collection status must stamp dispatched_at at database level.
dispatch_timestamp_guard = root / "supabase" / "migrations" / "20261121190000_logistics_dispatch_timestamp.sql"
if not dispatch_timestamp_guard.exists():
    raise SystemExit("Missing logistics dispatch timestamp migration")
dispatch_timestamp_sql = dispatch_timestamp_guard.read_text(encoding="utf-8").lower()
for marker in [
    "create or replace function public.set_logistics_dispatch_timestamp",
    "old.status is distinct from new.status and new.status='collected'",
    "new.dispatched_at:=coalesce(new.dispatched_at,now())",
    "before update of status on public.logistics_shipments",
]:
    if marker not in dispatch_timestamp_sql:
        raise SystemExit(f"Missing dispatch timestamp safeguard: {marker}")

# Terminal shipment UI actions must not offer tracking scans or POD capture.
logistics_ui = (root / "industry_workspaces.js").read_text(encoding="utf-8")
for marker in [
    "const allowed=[x.status,...(SF_SHIPMENT_TRANSITIONS[x.status]||[])]",
    "returned'].includes(x.status)?",
    '<button onclick="sfAddShipmentScan',
    '<button onclick="sfCapturePOD',
]:
    if marker not in logistics_ui:
        raise SystemExit(f"Missing Logistics UI lifecycle restriction: {marker}")


# Logistics shipment list must paginate beyond the Supabase default row cap.
shipment_workspace = logistics_ui[logistics_ui.index("async function sfLogisticsWorkspace()"):logistics_ui.index("const SF_SHIPMENT_CREATE_LOCK")]
for marker in [
    "const shipments=[];const shipmentPageSize=500;let shipmentOffset=0",
    "while(true){",
    ".order('created_at',{ascending:false}).order('id',{ascending:false}).range(shipmentOffset,shipmentOffset+shipmentPageSize-1)",
    "shipments.push(...page)",
    "if(page.length<shipmentPageSize)break",
    "SF_LOGISTICS_SHIPMENTS=shipments;",
]:
    if marker not in shipment_workspace:
        raise SystemExit(f"Logistics shipment pagination missing: {marker}")
if ".limit(500)" in shipment_workspace or "SF_LOGISTICS_SHIPMENTS=sr.data||[]" in shipment_workspace:
    raise SystemExit("Logistics shipment list still has a capped/unpaginated fetch")


# Logistics tracking history is lazy-loaded by shipment, never fetched globally.

# AI assistant memory reads and deletes must remain company-scoped.
assistant_backend = (root / "supabase" / "functions" / "smart-endpoint" / "index.ts").read_text(encoding="utf-8")
for marker in [
    'from("assistant_memory").delete().eq("id", String(input.id)).eq("company_id", ctx.company_id)',
    'from("assistant_memory").select("id,note").eq("company_id", company_id).order("created_at", { ascending: true }).limit(60)',
]:
    if marker not in assistant_backend:
        raise SystemExit(f"Assistant memory company isolation missing: {marker}")

for marker in [
    "async function sfLoadShipmentHistory",
    "sfShipmentHistory_",
    "eq('company_id',me.company_id)",
    "eq('site_id',site)",
    "eq('shipment_id',id)",
    "pageSize=50",
    ".range(offset,offset+pageSize-1)",
    "Load tracking history",
    "Load more scans",
]:
    if marker not in industry_text:
        raise SystemExit(f"Missing lazy Logistics history safeguard: {marker}")
if "logistics_tracking_events').select('*')" in shipment_workspace:
    raise SystemExit("Logistics workspace must not load all tracking events on open")

# First-page tracking history load replaces its initial placeholder rather than leaving stale copy beside results.
history_loader = industry_text[industry_text.index("async function sfLoadShipmentHistory"):industry_text.index("async function sfLogisticsWorkspace")]
if "if(offset===0)container.innerHTML=''" not in history_loader:
    raise SystemExit("Logistics tracking history first page must clear the initial placeholder")

# Latest scan insert policy must retain the terminal-shipment restriction after later policy replacements.
latest_scan_policy = (root / "supabase" / "migrations" / "20261121220000_logistics_scan_location_length_guard.sql").read_text(encoding="utf-8").lower()
if "s.status not in ('delivered','returned')" not in latest_scan_policy:
    raise SystemExit("Latest Logistics scan insert policy allows terminal shipments")

# POD RPC must reject a missing role (SQL NULL makes NOT IN evaluate to NULL).
pod_lock_guard = root / "supabase" / "migrations" / "20261121112000_logistics_pod_submission_lock.sql"
if not pod_lock_guard.exists():
    raise SystemExit("Missing Logistics POD submission lock migration")
pod_lock_guard_sql = pod_lock_guard.read_text(encoding="utf-8").lower()
if "if v_role is null or v_role not in ('owner','manager','technician','storeman')" not in pod_lock_guard_sql:
    raise SystemExit("Logistics POD RPC must reject null/unknown roles")
