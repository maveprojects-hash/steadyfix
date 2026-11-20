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
    "align-items:center",
    "Create a new company, or join one with an invite code.",
    "window.location.replace('maintdesk_app.html')",
]:
    if marker not in login_html:
        raise SystemExit(f"Missing streamlined login flow: {marker}")
if "Your sites</b>" in login_html or "Open the app →" in login_html:
    raise SystemExit("Intermediate post-login company landing screen remains")

# Startup intro/splash is deliberately removed; login/invite should route directly to setup or app.
for marker in ["#intro", "function intro()", "introgo", "sf_intro"]:
    if marker in login_html:
        raise SystemExit(f"Removed login intro popup was reintroduced: {marker}")
for marker in ["#intro", "introgo"]:
    if marker in html:
        raise SystemExit(f"Removed CMMS startup intro popup styles were reintroduced: {marker}")

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


# Logistics shipment lifecycle: UI and database guard must remain in agreement.
transition_ui = industry_workspaces.read_text(encoding="utf-8")
logistics_workspace_ui = transition_ui[transition_ui.index("async function sfLogisticsWorkspace"):transition_ui.index("const SF_SHIPMENT_TRANSITIONS")]
for marker in [
    "const pageSize=1000,shipments=[],events=[];let shipmentOffset=0,eventOffset=0",
    "while(true){const sr=await sb.from('logistics_shipments')",
    ".range(shipmentOffset,shipmentOffset+pageSize-1)",
    "shipments.push(...(sr.data||[]))",
    ".range(eventOffset,eventOffset+pageSize-1)",
    "eventOffset+=pageSize",
    "SF_LOGISTICS_SHIPMENTS=shipments",
]:
    if marker not in logistics_workspace_ui:
        raise SystemExit(f"Missing Logistics scan pagination safeguard: {marker}")
# Fleet vehicle assignment is site/company scoped, visible on waybills, and audited.
fleet_logistics_ui = transition_ui[transition_ui.index("async function sfLogisticsWorkspace"):transition_ui.index("async function sfCreateShipment")]
for marker in [
    "const vr=await sb.from('vehicles').select('id,name,make_model,reg_no,status')",
    ".eq('company_id',me.company_id).eq('site_id',site)",
    "Assign Fleet vehicle",
    "sfLogisticsVehicles.map(v=>",
    "Assigned vehicle",
]:
    if marker not in fleet_logistics_ui:
        raise SystemExit(f"Missing Fleet/Logistics vehicle integration: {marker}")
assignment_handler = transition_ui[transition_ui.index("async function sfAssignLogisticsVehicle"):transition_ui.index("async function sfCreateShipment")]
for marker in [
    "delivered','returned",
    "sfLogisticsVehicles.some(v=>v.id===vehicleId)",
    "update({vehicle_id:vehicleId})",
    ".eq('company_id',me.company_id).eq('site_id',site)",
]:
    if marker not in assignment_handler:
        raise SystemExit(f"Missing assignment UI validation: {marker}")
fleet_assignment_migration = next((root / "supabase" / "migrations").glob("*_logistics_fleet_vehicle_assignments.sql"))
fleet_assignment_sql = fleet_assignment_migration.read_text(encoding="utf-8").lower()
for marker in [
    "add column if not exists vehicle_id uuid references public.vehicles(id)",
    "validate_logistics_vehicle_assignment",
    "assigned vehicle must belong to the same company and site",
    "logistics_tracking_events_event_type_check",
    "vehicle_assignment",
    "exception_note",
    "return_note",
    "logistics_record_vehicle_assignment_event",
    "delivered or returned consignments cannot change vehicle assignment",
]:
    if marker not in fleet_assignment_sql:
        raise SystemExit(f"Missing Fleet/Logistics assignment database safeguard: {marker}")

# POD must only open after the UI validates the shipment's legal transition.
status_handler = transition_ui[transition_ui.index("async function sfUpdateShipmentStatus"):transition_ui.index("async function sfAddShipmentScan")]
if status_handler.index("sfShipmentTransitionAllowed") == -1 or status_handler.index("sfCapturePOD(id)") == -1 or status_handler.index("sfShipmentTransitionAllowed") > status_handler.index("sfCapturePOD(id)"):
    raise SystemExit("POD UI bypasses shipment transition validation")
scan_handler = transition_ui[transition_ui.index("async function sfAddShipmentScan"):transition_ui.index("function sfCapturePOD")]
for marker in ["if(scanLocation.length>200)", "if(notes&&notes.length>2000)", "notes=rawNotes.trim()||null"]:
    if marker not in scan_handler:
        raise SystemExit(f"Missing scan input validation: {marker}")

for marker in [
    "const SF_SHIPMENT_TRANSITIONS=",
    "booked:['collected','exception']",
    "out_for_delivery:['exception']",
    "if(status==='delivered'){sfCapturePOD(id);return;}",
    "exception:['collected','in_transit','at_depot','out_for_delivery','delivered','returned']",
    "async function sfUpdateShipmentStatus(id,status)",
    "if(shipment.status===status)return;",
    "if(!sfShipmentTransitionAllowed(shipment.status,status)",
    "const next=SF_SHIPMENT_TRANSITIONS[x.status]||[],available=[x.status,...next]",
    "while(true){const ev=await sb.from('logistics_tracking_events')",
]:
    if marker not in transition_ui:
        raise SystemExit(f"Missing logistics UI lifecycle safeguard: {marker}")

status_guard = next((root / "supabase" / "migrations").glob("*_logistics_status_transition_guard.sql"))
status_guard_sql = status_guard.read_text(encoding="utf-8").lower()
for marker in [
    "logistics_validate_status_transition",
    "new.status is not distinct from old.status",
    "old.status = 'booked' and new.status in ('collected','exception')",
    "old.status = 'out_for_delivery' and new.status in ('delivered','exception')",
    "old.status = 'exception' and new.status in ('collected','in_transit','at_depot','out_for_delivery','delivered','returned')",
    "delivered shipments require delivery timestamp and receiver name",
    "shipments may only be returned from exception status",
    "for each row execute function public.logistics_validate_status_transition",
]:
    if marker not in status_guard_sql:
        raise SystemExit(f"Missing logistics database lifecycle safeguard: {marker}")

print("CMMS syntax, notifications, industry profiles, Automation operations, logistics and tenant safeguards: PASS")


# Fleet client-side GPS validation must reject corrupt or future telemetry.
app_html = html

# Quotes and invoices: validate workflow transitions and company/site-scoped mutations.
quote_card_actions = app_html[app_html.index("const cards=D.map"):app_html.index("const pb=")]
if "DOCS.some(x=>x.kind==='invoice'&&x.converted_from===d.id)" not in quote_card_actions:
    raise SystemExit("Quote list still offers invoice conversion after conversion")
conversion_guard_migration = root / "supabase" / "migrations" / "20261120230000_document_quote_conversion_unique.sql"
if not conversion_guard_migration.exists():
    raise SystemExit("Missing unique quote-conversion migration")
conversion_guard_sql = conversion_guard_migration.read_text(encoding="utf-8").lower()
for marker in ["documents_one_invoice_per_quote_idx", "on public.documents(company_id,converted_from)", "group by company_id,converted_from", "kind='invoice' and converted_from is not null", "having count(*)>1", "reconcile them before applying"]:
    if marker not in conversion_guard_sql:
        raise SystemExit(f"Missing duplicate quote-conversion database safeguard: {marker}")

document_workflow = app_html[app_html.index("async function setDoc"):app_html.index("// ---------- accounting export")]
for marker in [
    "const d=DOCS.find(x=>x.id===id);if(!d)return;",
    "const allowed=d.kind==='invoice'?['sent','paid','cancelled']:['sent','accepted','declined','cancelled']",
    "Only issued invoices can be marked paid.",
    ".eq('id',id).eq('company_id',me.company_id).eq('site_id',site)",
    "Only managers can delete company documents.",
    "Only sent or accepted quotes can be converted.",
    "This quote already has an invoice.",
    "Create an invoice from this quote?",
    "const{error:quoteUpdateError}",
    "documents_one_invoice_per_quote_idx",
    "This quote already has an invoice. Refresh the list to open it.",
    "Invoice '+r.data.number+' was created, but the quote status could not be updated",
]:
    if marker not in document_workflow:
        raise SystemExit(f"Missing Quotes/Invoices workflow safeguard: {marker}")
for marker in [
    "const validPos=r=>",
    "r.lat!=null&&r.lat!==''",
    "r.lng!=null&&r.lng!==''",
    "r.speed_kmh!=null&&r.speed_kmh!==''",
    "t<=nowMs+120000",
    "Math.abs(+r.lat)<=90",
    "Math.abs(+r.lng)<=180",
    "+r.speed_kmh<=300",
    "age>=0&&age<864e5",
    "seen<=nowMs+120000",
]:
    if marker not in app_html:
        raise SystemExit(f"Missing Fleet telemetry validation: {marker}")

# Fleet GPS integrity migration regression markers.
fleet_guard = next((root / "supabase" / "migrations").glob("*_fleet_gps_integrity_guards.sql"))
fleet_guard_sql = fleet_guard.read_text(encoding="utf-8").lower()
for marker in [
    "validate_vehicle_position_integrity",
    "invalid gps coordinates",
    "invalid gps speed",
    "invalid gps heading",
    "gps timestamp is invalid or too far in the future",
    "vehicle must belong to the same company",
    "vehicle_positions_company_recent_idx",
    "vehicles_company_last_seen_idx",
]:
    if marker not in fleet_guard_sql:
        raise SystemExit(f"Missing Fleet GPS integrity safeguard: {marker}")


# Fleet GPS history must paginate instead of silently capping analytics at 5,000 rows.
fleet_fn = app_html[app_html.index("async function fleetData()"):app_html.index("async function fleetOverview()", app_html.index("async function fleetData()"))]
for marker in [
    "const pageSize=1000,positions=[]",
    "while(true)",
    ".range(offset,offset+pageSize-1)",
    "offset+=pageSize",
    "rows.length<pageSize",
    ".lte('recorded_at',until)",
    ".order('vehicle_id',{ascending:true}).order('id',{ascending:true})",
    "String(a.vehicle_id).localeCompare(String(b.vehicle_id))",
    "String(a.id).localeCompare(String(b.id))",
]:
    if marker not in fleet_fn:
        raise SystemExit(f"Missing Fleet GPS pagination safeguard: {marker}")
if ".limit(5000)" in fleet_fn:
    raise SystemExit("Fleet GPS history still silently caps at 5,000 records")

# Tracker launch URLs must never contain the device bearer key.
tracker_page = (root / "tracker.html").read_text(encoding="utf-8")
if "$('key').value=q.get('key')" in tracker_page or "tracker.html?key=" in app_html:
    raise SystemExit("Tracker device key is being exposed through URL query parameters")
if "Never accept tracker credentials from URL query strings" not in tracker_page:
    raise SystemExit("Missing tracker URL credential guard")

# Fleet keys stay masked in the UI while preserving manager copy access.
if '<b>${s.device_key}</b>' in app_html or 'Device key: <b>••••••••</b>' not in app_html or 'copyTxt(\'dk${s.id}\')' not in app_html:
    raise SystemExit("Fleet device key must be masked with a working copy-key action")

# Fleet sample commands must use a placeholder, never render real vehicle bearer keys.
fleet_track_fn = app_html[app_html.index("async function fleetTrack()"):]
if '"p_key":"${x.device_key}"' in fleet_track_fn or '<TRACKER_KEY>' not in fleet_track_fn:
    raise SystemExit("Fleet sample curl command must redact the tracker key")

# Smart sensor curl examples must not embed actual device keys.
if 'p_key":"${s.device_key}' in app_html:
    raise SystemExit("Smart sensor sample curl command exposes a real device key")
if '<DEVICE_KEY>' not in app_html:
    raise SystemExit("Smart sensor sample curl command must use a redacted key placeholder")

# Tracker credentials are discarded when a driver stops sharing location.
stop_fn = tracker_page[tracker_page.index('function stop()'):tracker_page.index("$('go').onclick")]
if "$('key').value=''" not in stop_fn or 'Tracker key cleared' not in stop_fn:
    raise SystemExit('Stopping GPS must clear the tracker credential from the phone page')

# Fleet tracker concurrency and stale-position regression guards.
ordered_positions = root / "supabase" / "migrations" / "20261120213000_fleet_out_of_order_position_guard.sql"
if not ordered_positions.exists():
    raise SystemExit("Missing Fleet out-of-order telemetry migration")
ordered_sql = ordered_positions.read_text(encoding="utf-8").lower()
for marker in [
    "for update",
    "v.last_seen is null or t > v.last_seen",
    "only newer telemetry may update",
    "current_updated",
    "odometer cannot move backwards",
    "grant execute on function public.ingest_position",
]:
    if marker not in ordered_sql:
        raise SystemExit(f"Missing Fleet concurrent telemetry safeguard: {marker}")


# The unnecessary company/worker invite startup popup must remain removed.
if "function intro()" in app_html or "\nintro();\n" in app_html:
    raise SystemExit("Unnecessary startup intro popup has been reintroduced")
# Logistics waybill creation validation and site-scoped duplicate check.
create_handler = transition_ui[transition_ui.index("async function sfCreateShipment"):transition_ui.index("const SF_SHIPMENT_TRANSITIONS")]
for marker in [
    "waybill.length>100||tracking.length>100",
    "origin.length>1000||destination.length>1000",
    "Number.isInteger(packages)||packages<1||packages>500",
    "This waybill number already exists at this site",
    ".eq('company_id',me.company_id).eq('site_id',site).eq('waybill_no',waybill)",
    "if(duplicate.error)",
]:
    if marker not in create_handler:
        raise SystemExit(f"Missing waybill creation validation: {marker}")
# Waybill printouts must inherit the company logo/details and saved document colour.
waybill_print = transition_ui[transition_ui.index("async function sfPrintWaybill"):transition_ui.index("// Extend the existing navigation")]
for marker in [
    "async function sfPrintWaybill",
    "ph('Transport waybill')",
    "CS.doc_color",
    "border-top:4px solid ",
]:
    if marker not in waybill_print:
        raise SystemExit(f"Missing company branding on waybill: {marker}")
# Logistics exception/return status changes must capture a required reason and action.
status_handler = transition_ui[transition_ui.index("async function sfUpdateShipmentStatus"):transition_ui.index("async function sfAddShipmentScan")]
for marker in [
    "status==='exception'||status==='returned'",
    "Describe the delivery exception and next action",
    "Describe the return reason and next action",
    "A reason is required to record this status",
    "eventNotes.length>2000",
    "eventType=status==='exception'?'exception_note':'return_note'",
    "eventNotes",
    "Status was saved, but its reason could not be recorded",
]:
    if marker not in status_handler:
        raise SystemExit(f"Missing Logistics exception/return reason workflow: {marker}")
