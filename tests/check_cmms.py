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
    "else if(slug)chooseIndustryWorkspace(slug)",
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
    "const standardIndustries=new Set(['hospitality-tourism','property-management-facilities','construction-project-management'])",
    "const workspaceRoutes=new Set(typeof sfIndustryModules==='function'?sfIndustryModules(slug).map(m=>m[3]):[])",
    "cur=='logistics_ops'?await sfLogisticsWorkspace()",
    "cur=='service_contracts'?await sfServiceContracts()",
    "['logistics_ops','Parcel operations']",
    "['service_contracts','Service contracts']",
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

# Shared live operational sync for web and desktop clients.
live_sync = root / "company-live-sync.js"
if not live_sync.exists():
    raise SystemExit("Missing company-wide live sync client module")
subprocess.run(["node", "--check", str(live_sync)], check=True)
live_code = live_sync.read_text(encoding="utf-8")
for marker in [
    "startCompanyLiveSync",
    "broadcast",
    "cmms_change",
    "config: { private: true }",
    "refreshActiveView",
    "refreshInFlight",
    "visibilitychange",
    "window.addEventListener('online'",
    "focusout",
    "stopCompanyLiveSync",
]:
    if marker not in live_code:
        raise SystemExit(f"Missing shared live-sync behaviour: {marker}")
for marker in [
    'company-live-sync.js',
    "startCompanyLiveSync();draw()",
]:
    if marker not in html:
        raise SystemExit(f"CMMS boot does not start shared live sync: {marker}")

live_migration = next((root / "supabase" / "migrations").glob("*_company_live_sync.sql"))
live_sql = live_migration.read_text(encoding="utf-8").lower()
for marker in [
    "private.broadcast_cmms_company_change",
    "realtime.send",
    "cmms_company_live_sync_read",
    "realtime.topic()",
    "p.active = true",
    "a.attname = 'company_id'",
    "c.relrowsecurity",
    "after insert or update or delete",
    "messages','notifications','company_conversations','conversation_members",
]:
    if marker.lower() not in live_sql:
        raise SystemExit(f"Missing tenant-safe live publication setup: {marker}")


# Industry-specific colour identity is applied to the entire shared CMMS.
industry_js = root / "industry_workspaces.js"
if not industry_js.exists():
    raise SystemExit("Missing industry workspace module")
subprocess.run(["node", "--check", str(industry_js)], check=True)
industry_code = industry_js.read_text(encoding="utf-8")
for marker in [
    "SF_INDUSTRY_THEMES",
    "function applyIndustryTheme()",
    "document.body.dataset.industryTheme",
    "meta[name=\"theme-color\"]",
    "automation: {",
    "'fleet-management':",
    "workshops:",
    "'logistics-transport':",
    "'hospitality-tourism':",
    "'food-beverage':",
    "'property-management-facilities':",
    "'construction-project-management':",
    "'manufacturing-industrial':",
    "'general-maintenance':",
]:
    if marker not in industry_code:
        raise SystemExit(f"Missing industry visual identity: {marker}")
for marker in [
    "applyIndustryTheme==='function'",
    "border-bottom:3px solid var(--ac)",
    "color-mix(in srgb,var(--am)",
]:
    if marker not in html:
        raise SystemExit(f"Industry palette is not applied in the CMMS UI: {marker}")


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
    "async function sfGetRestoredSession()",
    "const session=await sfGetRestoredSession()",
    "Your session is still active",
    "profileRetry",
]:
    if marker not in login_html:
        raise SystemExit(f"Missing login session recovery marker: {marker}")
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
    'id="industrySaveBtn"',
    "cur=='industry'?await industryProfile()",
    "t[0]=='industry'?isMgr()&&!LOCK",
    "company_industry_profiles",
]:
    if marker not in html:
        raise SystemExit(f"Missing industry profile app integration: {marker}")
if 'id="industry"' not in login_html or "company_industry_profiles').update" not in login_html:
    raise SystemExit("Company onboarding does not save the selected industry profile")

# Company onboarding must provide a return path to the login form for existing users.
for marker in ['id="loginBack"', "Already registered? Back to log in", "mode='login';auth()"]:
    if marker not in login_html:
        raise SystemExit(f"Missing setup return-to-login navigation: {marker}")

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
    "'construction-project-management':[['🏗️','Project work packages'",
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
custom_views = {"service_contracts", "logistics_ops", "ohs", "fleet", "inv", "chk", "rep", "bud"}
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


# Assistant saved memory is strictly company-scoped (prevents cross-tenant context leakage).
assistant_endpoint = (root / "supabase" / "functions" / "smart-endpoint" / "index.ts").read_text(encoding="utf-8")
for marker in [
    'sb.from("assistant_memory").select("id,note").eq("company_id", company_id)',
    'sb.from("assistant_memory").delete().eq("id", String(input.id)).eq("company_id", ctx.company_id).select("id")',
    'if (!data || !data.length) return "No matching memory found for this company.";',
    'st.memory = st.memory.filter((m) => String(m.id) !== String(input.id)); return "Removed.";',
    'sb.from("assistant_memory").insert({ company_id: ctx.company_id, note, created_by: ctx.user_id })',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"Missing assistant company-memory isolation: {marker}")

# Quick Access dropdown must expose departments and industry workspace selection.
quick_access_markers = [
    'id="industryQuickAccessBtn"', 'id="industryQuickAccessMenu"',
    'function sfIndustryQuickPick()', 'function toggleIndustryQuickAccess()',
    'function sfCloseIndustryQuickAccess()', 'function sfBindIndustryQuickAccess()',
    'role="listbox"', 'role="option"', 'aria-selected="false"',
    'data-quick-tab=', 'data-industry-slug=',
    'role="group" aria-label="Departments"',
    'role="group" aria-label="Industry workspaces"',
    "event.key==='ArrowDown'", "event.key==='ArrowUp'",
    "event.key==='Home'", "event.key==='End'", "e.key==='Escape'",
    "menu.querySelector('[data-quick-tab],[data-industry-slug]')?.focus()",
]
for marker in quick_access_markers:
    if marker not in html:
        raise SystemExit(f"Quick Access dropdown regression marker missing: {marker}")
print("Industry Quick Access dropdown rendering, navigation, keyboard and dismissal: PASS")
# Quick Access industry changes must verify persistence and rebuild industry-dependent navigation.
choose_start = workspace_code.index("async function chooseIndustryWorkspace(slug){")
choose_end = workspace_code.index("\nasync function sfIndustryHub()", choose_start)
choose_function = workspace_code[choose_start:choose_end]
for marker in ["select('company_id,primary_industry_slug').maybeSingle()", "data.primary_industry_slug!==slug", "await loadIndustryProfile();renderIndustrySelector();", "buildNav();", "cur='industry_workspace';draw();"]:
    if marker not in choose_function:
        raise SystemExit(f"Quick Access industry-switch regression marker missing: {marker}")
print("Quick Access industry persistence verification and navigation refresh: PASS")

# Changing a primary industry must refresh dashboard-dependent industry content.
save_start = html.index("async function savePrimaryIndustry(slug){")
save_end = html.index("\nasync function saveIndustryProfile()", save_start)
save_function = html[save_start:save_end]
if "await loadIndustryProfile();renderIndustrySelector();buildNav();draw();" not in save_function:
    raise SystemExit("Industry switch must reload profile and redraw dashboard after saving")
print("Industry switch dashboard refresh regression guard: PASS")

# Industry switch must confirm a database row was updated and surface failures.
for marker in [
    "select('company_id,primary_industry_slug').maybeSingle()",
    "No company profile row was updated",
    "Industry switch failed:",
    "finally{if(btn)btn.disabled=false}",
]:
    if marker not in html:
        raise SystemExit(f"Industry switch save-confirmation marker missing: {marker}")
print("Industry switch confirmation, error feedback and button recovery: PASS")

# Full industry profile editor validates and confirms the saved company row.
profile_start = html.index("async function saveIndustryProfile(){")
profile_end = html.index("\nasync function industryProfile()", profile_start)
profile_save = html[profile_start:profile_end]
for marker in [
    "secondary.some(x=>!INDUSTRIES.some(i=>i.slug===x))",
    ".select('company_id,primary_industry_slug').maybeSingle()",
    "No company profile row was updated",
    "finally{if(saveBtn)saveBtn.disabled=false}",
]:
    if marker not in profile_save:
        raise SystemExit(f"Industry profile save safeguard missing: {marker}")

print("Industry profile editor save confirmation and validation: PASS")

# PDF downloads and shares must contain a real PDF header, terminal marker and page object.
pdf_start = html.index("async function shareHtml(")
pdf_end = html.index("\nfunction docPreview(", pdf_start)
pdf_share = html[pdf_start:pdf_end]
for marker in [
    "await blob.arrayBuffer()",
    "pdfText.startsWith('%PDF-')",
    "pdfText.includes('%%EOF')",
    "Page(?!s)",
    "generated PDF is incomplete or contains no readable page",
]:
    if marker not in pdf_share:
        raise SystemExit(f"PDF structure validation missing: {marker}")
print("PDF structure validation and blank-document fallback: PASS")


# Industry profiles must drive real workspace navigation, not only the dashboard banner.
for marker in [
    "config.dashboard_priority_tabs",
    "config.disabled_modules",
    "config.module_labels",
    "buildNav();draw();",
    "renderIndustrySelector();buildNav();if(cur==='dash')await draw();",
]:
    if marker not in html:
        raise SystemExit(f"Industry workspace navigation marker missing: {marker}")
print("Industry workspace module order, visibility and terminology: PASS")

# Header cleanup: only one Quick Access trigger exists, with responsive compact layout.
if html.count('id="industryQuickAccessBtn"') != 1:
    raise SystemExit("Expected exactly one Quick Access button; remove legacy duplicate")
header_markup = html.split("<header>", 1)[1].split("</header>", 1)[0]
if ('href="maintdesk_app.html"' in header_markup or "href='maintdesk_app.html'" in header_markup or "Manager CMMS application" in header_markup or "Manager application" in header_markup):
    raise SystemExit("Legacy Manager CMMS application button is still present in the header")
for marker in [
    "sf-industry-quick{flex-direction:row",
    "@media(max-width:700px)",
    "header #site{min-width:130px;max-width:220px}",
    ".sf-industry-quick{flex-direction:row;flex-wrap:nowrap;align-items:center",
    ".sf-industry-quick-wrap{width:auto;flex:0 0 auto;max-width:none}",
    ".sf-industry-quick-btn{width:auto;min-width:0;justify-content:center;gap:6px",
]:
    if marker not in html:
        raise SystemExit(f"Quick Access header layout regression marker missing: {marker}")
print("Single Quick Access button, legacy Manager button removal, and mobile inline header layout: PASS")

# Mobile dropdown must be portaled out of the header stacking context and remain topmost.
for marker in [
    "document.body.appendChild(menu)",
    "z-index:2147483647",
    "pointer-events:auto",
    "transform:none",
    'id="site" hidden aria-hidden="true" tabindex="-1"',
]:
    if marker not in html:
        raise SystemExit(f"Quick Access overlay regression marker missing: {marker}")
print("Header site selector hidden; industry dropdown portal and top-layer overlay: PASS")

# Authentication resilience: retry a transient local session read and avoid false logout on profile fetch failure.
for marker in [
    "async function sfGetRestoredSession()",
    "const session=await sfGetRestoredSession()",
    "Your session is intact",
    "setTimeout(resolve,300)",
]:
    if marker not in html:
        raise SystemExit(f"Missing CMMS session recovery marker: {marker}")
print("CMMS session restore retry and profile-load failure handling: PASS")

# Atomic quote conversion regression markers and transactional migration safeguards.
quote_conversion_start = html.find("async function toInvoice(")
quote_conversion_end = html.find("async function delDoc(", quote_conversion_start)
quote_conversion_code = html[quote_conversion_start:quote_conversion_end]
for marker in ["q.company_id!==me.company_id", "q.kind!=='quote'", "q.status==='cancelled'", "sb.rpc('convert_quote_to_invoice'", "p_quote_id:id", "p_invoice_number:number", "r.data.already_converted"]:
    if marker not in quote_conversion_code:
        raise SystemExit(f"Missing quote conversion safeguard: {marker}")
if "sb.from('documents').insert(row)" in quote_conversion_code or "sb.from('documents').update({status:'accepted'})" in quote_conversion_code:
    raise SystemExit("Quote conversion must use a single database transaction")
conversion_migration = root / "supabase" / "migrations" / "20261123110000_quote_conversion_atomic_rpc.sql"
if not conversion_migration.exists(): raise SystemExit("Missing quote conversion RPC migration")
conversion_sql = conversion_migration.read_text(encoding="utf-8").lower()
for marker in ["security invoker", "for update", "public.auth_company()", "public.auth_site_ok(v_quote.site_id)", "on conflict (company_id, converted_from)", "already_converted"]:
    if marker not in conversion_sql: raise SystemExit(f"Missing transactional quote guard: {marker}")

# Stock adjustment buttons must use the atomic delta RPC, never stale client-side upserts.
stock_adjust_source = html.split("async function adjStock(", 1)[1].split("\n\nasync function mod(", 1)[0]
for marker in ["sb.rpc('adjust_stock_level'", "p_item_id:rid", "p_site_id:site", "p_delta:d"]:
    if marker not in stock_adjust_source:
        raise SystemExit(f"Missing atomic stock adjustment behavior: {marker}")
stock_adjust_migration = root / "supabase" / "migrations" / "20261123170000_atomic_stock_adjustments.sql"
if not stock_adjust_migration.exists():
    raise SystemExit("Missing atomic stock adjustment RPC migration")
stock_adjust_sql = stock_adjust_migration.read_text(encoding="utf-8").lower()
for marker in ["for update", "auth_role()", "auth_site_ok", "stock_levels", "on conflict(item_id,site_id)", "stock adjustment would make inventory negative"]:
    if marker not in stock_adjust_sql:
        raise SystemExit(f"Missing stock adjustment safeguard: {marker}")


# Logistics scalability: shipment list is paged and tracking history is lazy/paged per shipment.
logistics_js = (root / "industry_workspaces.js").read_text(encoding="utf-8")
workspace = logistics_js[logistics_js.index("async function sfLogisticsWorkspace"):logistics_js.index("async function sfCreateShipment")]
history_loader = logistics_js[logistics_js.index("async function sfLoadShipmentHistory"):logistics_js.index("async function sfLogisticsWorkspace")]
for marker in [
    "const shipments=[];const shipmentPageSize=500;let shipmentOffset=0",
    "while(true){",
    ".range(shipmentOffset,shipmentOffset+shipmentPageSize-1)",
    "shipments.push(...page)",
    "if(page.length<shipmentPageSize)break",
    "sfLoadShipmentHistory",
    "Load tracking history",
]:
    if marker not in workspace:
        raise SystemExit(f"Logistics shipment paging regression missing: {marker}")
for marker in [
    "pageSize=50",
    "eq('company_id',me.company_id)",
    "eq('site_id',site)",
    "eq('shipment_id',id)",
    ".range(offset,offset+pageSize-1)",
    "if(offset===0)container.innerHTML='';",
    "Load more scans",
]:
    if marker not in history_loader:
        raise SystemExit(f"Logistics tracking-history paging regression missing: {marker}")
if "logistics_tracking_events').select('*')" in workspace:
    raise SystemExit("Logistics workspace must not fetch all tracking events on initial render")
print("Logistics shipment pagination and lazy tracking history: PASS")

# Quotes and invoices: enforce active company/site scope in document lists and exports.
doc_list_start = html.find("async function docList(kind)")
doc_list_end = html.find("async function invNew(kind)", doc_list_start)
doc_list_code = html[doc_list_start:doc_list_end]
for marker in [
    "eq('company_id',me.company_id)",
    "eq('site_id',site)",
    "sb.from('customers').select('*').eq('company_id',me.company_id)",
]:
    if marker not in doc_list_code:
        raise SystemExit(f"Quote/invoice list is missing tenant/site scope: {marker}")
number_code = html[html.find("async function nextNum(kind)"):html.find("async function docList(kind)")]
if "eq('company_id',me.company_id)" not in number_code:
    raise SystemExit("Quote/invoice numbering is not scoped to the active company")
export_start = html.find("async function progDocs()")
export_end = html.find("async function exportXero()", export_start)
export_code = html[export_start:export_end]
for marker in ["eq('company_id',me.company_id)", "eq('site_id',site)", "eq('kind','invoice')"]:
    if marker not in export_code:
        raise SystemExit(f"Invoice accounting export is missing tenant/site scope: {marker}")
for marker in [
    "cu:(await sb.from('customers').select('*').eq('company_id',me.company_id))",
    "async function exportDocs(kind){const r=await sb.from('documents').select('*').eq('company_id',me.company_id).eq('site_id',site)",
    "async function exportCust(){const D=(await sb.from('customers').select('*').eq('company_id',me.company_id)",
    "async function exportExp(){const D=(await sb.from('expenses').select('*').eq('company_id',me.company_id).eq('site_id',site)",
]:
    if marker not in html:
        raise SystemExit(f"Accounting export tenant/site regression missing: {marker}")
print("Quote/invoice lists, customer data and accounting exports company/site scope: PASS")

# Quote/invoice mutations must remain constrained to the active tenant and site.
save_doc_start = html.index("async function saveDoc(pr)")
save_doc_end = html.index("async function toInvoice(", save_doc_start)
doc_mutations = html[save_doc_start:html.index("function docSheet(d)", save_doc_start)]
for marker in [
    ".update(row).eq('id',e.id).eq('company_id',me.company_id).eq('site_id',site)",
    "async function setDoc(id,st)",
    ".update(u).eq('id',id).eq('company_id',me.company_id).eq('site_id',site)",
    "async function dupDoc(id)",
    "d.company_id!==me.company_id||d.site_id!==site",
    "async function delDoc(id)",
    ".delete().eq('id',id).eq('company_id',me.company_id).eq('site_id',site)",
]:
    if marker not in doc_mutations:
        raise SystemExit(f"Quote/invoice write is missing company/site scope: {marker}")
print("Quote/invoice edits, status changes, duplication and deletion company/site scope: PASS")



# iAssistant data reads and approved writes must be explicitly tenant/site scoped.
assistant_endpoint = (root / "supabase/functions/smart-endpoint/index.ts").read_text(encoding="utf-8")
for marker in [
    'const selectedColumns = table === "sensors"',
    'table === "vehicles"',
    'table === "assets"',
    'id,name,category,status,wear_pct,replace_cost,installed_on,life_years',
    'get("asset_attention", "assets"',
    'asset.wear_pct',
    'faulty_assets: faulty.length',
    'stopped_assets: stopped.length',
    '.select(selectedColumns).eq("company_id", ctx.company_id).limit(200)',
    'const columns = table === "sensors"',
    'table === "vehicles"',
    '.select(columns).eq("company_id", ctx.company_id).limit(500)',
    '.eq("company_id", company_id).order("created_at"',
    '.eq("company_id", ctx.company_id).select("id")',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"iAssistant server tenant scope missing: {marker}")

for marker in [
    "update(ch).eq('id',p.rowId).eq('company_id',me.company_id)",
    "if(sc.site&&site)q=q.eq('site_id',site)",
    "select('id,note').eq('company_id',me.company_id)",
    "delete().eq('id',id).eq('company_id',me.company_id)",
    "update(u).eq('id',c.rid).eq('company_id',me.company_id)",
]:
    if marker not in html:
        raise SystemExit(f"iAssistant browser tenant/site safeguard missing: {marker}")
print("iAssistant search, attention, memory and approved-write tenant/site scope: PASS")


# iAssistant must derive site context from the authenticated, RLS-filtered database session.
profile_anchor = assistant_endpoint.find('const prof = await sb.from("profiles")')
site_anchor = assistant_endpoint.find('const requestedSiteId = typeof body.site_id')
context_anchor = assistant_endpoint.find('const ctx = {')
if min(profile_anchor, site_anchor, context_anchor) < 0 or not profile_anchor < site_anchor < context_anchor:
    raise SystemExit("iAssistant must verify the authenticated profile before resolving the selected site")
for marker in [
    'sb.from("sites").select("id,name")',
    '.eq("id", requestedSiteId).maybeSingle()',
    'if (!siteResult.data) return json({ error: "The selected site is unavailable for this account.',
    'site_id: activeSite?.id || null',
    'site_name: String(activeSite?.name || "their site")',
    'today: new Date().toISOString().slice(0, 10)',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"iAssistant authoritative site-context safeguard missing: {marker}")
if 'body.site_name' in assistant_endpoint or 'body.today' in assistant_endpoint:
    raise SystemExit("iAssistant must not trust browser-supplied site names or dates")
print("iAssistant authenticated site-context verification: PASS")


# The assistant UI exposes workshop job cards, so the server allowlist must expose them too.
allowed_start = assistant_endpoint.find("const ALLOWED = [")
allowed_end = assistant_endpoint.find("];", allowed_start)
allowed_block = assistant_endpoint[allowed_start:allowed_end] if allowed_start >= 0 and allowed_end >= 0 else ""
if '"workshop_jobs"' not in allowed_block:
    raise SystemExit("iAssistant UI offers workshop job cards but the server tool allowlist blocks workshop_jobs")
print("iAssistant workshop job-card tool availability: PASS")

assistant_ui = (root / "maintdesk_app.html").read_text(encoding="utf-8")
if '"sensors"' not in allowed_block or '"readings"' not in allowed_block:
    raise SystemExit("iAssistant must be able to search sensor configuration and readings")
if 'const READ_ONLY_TABLES = ["stock_items", "sensors", "readings"]' not in assistant_endpoint:
    raise SystemExit("iAssistant must keep sensor configuration and readings read-only")
for marker in [
    'sb.from("sensors").select("id,name,kind,unit")',
    'sb.from("readings").select("id,sensor_id,value,read_at")',
    '.eq("company_id", ctx.company_id).in("sensor_id", ids)',
    'sensorQuery.eq("site_id", ctx.site_id)',
    'sensor_name: sensor.name',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"iAssistant sensor monitoring lookup is missing safe scoping: {marker}")
if "That feed is the next build step" in assistant_ui or "Live readings are received through each device private key" not in assistant_ui:
    raise SystemExit("Monitoring setup note must accurately describe the existing live reading ingestion path")
if "Sensor registrations and recorded measurements are searchable" not in assistant_endpoint:
    raise SystemExit("iAssistant must describe sensor monitoring as read-only and avoid claiming live ingestion")
if 'table === "stock_items" ? "Error: stock records can be searched' not in assistant_endpoint:
    raise SystemExit("iAssistant read-only errors must identify the correct table type")
if "T.readings={label:'Sensor readings'" not in assistant_ui:
    raise SystemExit("iAssistant sensor readings schema is missing")

for marker in [
    'const SERVER_FIELD_ALLOWLIST = {',
    'sensors: ["name", "kind", "unit", "alert_min", "alert_max"]',
    'readings: ["sensor_id", "sensor_name", "sensor_kind", "value", "unit", "read_at"]',
    'vehicles: ["name", "reg_no", "odometer_km", "next_service_km", "status", "make_model", "vin", "next_service_date", "license_expiry", "speed_limit", "last_lat", "last_lng", "last_speed", "last_seen"]',
    '.filter((field) => field && safe.has(field.k))',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"iAssistant sensor field privacy guard missing: {marker}")
if 'device_key' in assistant_endpoint[assistant_endpoint.index('const SERVER_FIELD_ALLOWLIST'):assistant_endpoint.index('const prof =')]:
    raise SystemExit("iAssistant sensor server allowlist must not expose device_key")
sensor_security_migration = root / "supabase" / "migrations" / "20261125090000_sensor_device_key_manager_access.sql"
if not sensor_security_migration.exists():
    raise SystemExit("Missing sensor device-key access-control migration")
sensor_security_sql = sensor_security_migration.read_text(encoding="utf-8").lower()
for marker in [
    "revoke select (device_key)",
    "drop policy if exists tenant_site on public.sensors",
    "create policy tenant_site_read",
    "create policy tenant_site_manager_write",
    "public.auth_role() in ('owner','manager')",
    "create or replace function public.get_sensor_device_keys",
    "grant execute on function public.get_sensor_device_keys(uuid) to authenticated",
    "revoke all on function public.get_sensor_device_keys(uuid) from public, anon",
]:
    if marker not in sensor_security_sql:
        raise SystemExit(f"Sensor credential access control is missing: {marker}")
for marker in [
    "select('id,site_id,name,kind,unit,alert_min,alert_max,created_at')",
    "sb.rpc('get_sensor_device_keys',{p_site_id:site})",
    "isMgr()?",
    "Connect this device",
    "async function addS(){if(!isMgr())return;",
    "async function updS(id,f,v,t){if(!isMgr())return;",
    "async function delS(id){if(!isMgr())return;",
]:
    if marker not in assistant_ui:
        raise SystemExit(f"Monitoring manager-only credential control is missing: {marker}")
if "sb.from('sensors').select('*')" in assistant_ui or "s.device_key" in assistant_ui:
    raise SystemExit("Monitoring UI must not fetch or render device keys from ordinary sensor rows")
if 'table === "sensors"' not in assistant_endpoint or 'alert_max,created_at' not in assistant_endpoint:
    raise SystemExit("iAssistant sensor queries must not select private device_key values")
if 'table === "vehicles"' not in assistant_endpoint or 'last_seen,created_at' not in assistant_endpoint:
    raise SystemExit("iAssistant vehicle queries must not select private GPS device_key values")
sensor_column_migration = root / "supabase" / "migrations" / "20261125090500_sensor_column_privileges.sql"
if not sensor_column_migration.exists():
    raise SystemExit("Missing sensor least-privilege column grant migration")
sensor_column_sql = sensor_column_migration.read_text(encoding="utf-8").lower()
for marker in [
    "revoke all privileges on table public.sensors from authenticated",
    "grant select (",
    "grant insert (",
    "grant update (",
    "grant delete on table public.sensors to authenticated",
]:
    if marker not in sensor_column_sql:
        raise SystemExit(f"Sensor column privilege hardening is missing: {marker}")
for grant in re.findall(r"grant (?:select|insert|update) \((.*?)\) on table public.sensors", sensor_column_sql, re.S):
    if "device_key" in grant:
        raise SystemExit("Sensor device_key must not be included in authenticated column grants")
vehicle_security_migration = root / "supabase" / "migrations" / "20261125091000_vehicle_device_key_manager_access.sql"
if not vehicle_security_migration.exists():
    raise SystemExit("Missing vehicle device-key access-control migration")
vehicle_security_sql = vehicle_security_migration.read_text(encoding="utf-8").lower()
for marker in [
    "revoke all privileges on table public.vehicles from authenticated",
    "add column if not exists license_expiry date",
    "grant select (",
    "grant insert (",
    "grant update (",
    "grant delete on table public.vehicles to authenticated",
    "create or replace function public.get_vehicle_device_keys",
    "public.auth_role() not in ('owner','manager')",
    "grant execute on function public.get_vehicle_device_keys(uuid) to authenticated",
    "revoke all on function public.get_vehicle_device_keys(uuid) from public, anon",
]:
    if marker not in vehicle_security_sql:
        raise SystemExit(f"Vehicle credential access control is missing: {marker}")
for grant in re.findall(r"grant (?:select|insert|update) \((.*?)\) on table public.vehicles", vehicle_security_sql, re.S):
    if "device_key" in grant:
        raise SystemExit("Vehicle device_key must not be included in authenticated column grants")
for marker in [
    "sb.from('vehicles').select('id,company_id,site_id,name,reg_no,odometer_km,next_service_km,status,make_model,vin,next_service_date,license_expiry,speed_limit,last_lat,last_lng,last_speed,last_seen,created_at')",
    "sb.rpc('get_vehicle_device_keys',{p_site_id:site})",
    "deviceKey=x.device_key||''",
]:
    if marker not in assistant_ui:
        raise SystemExit(f"Fleet manager-only device key retrieval is missing: {marker}")
if "sb.from('vehicles').select('*')" in assistant_ui or '"p_key":"${x.device_key}"' in assistant_ui:
    raise SystemExit("Fleet UI must not fetch or render vehicle keys from ordinary vehicle rows")
if "['sensors','readings'].includes(p.table)" not in assistant_ui:
    raise SystemExit("iAssistant UI must prevent sensor writes")
if '"assets"' not in allowed_block or '"stock_items"' not in allowed_block:
    raise SystemExit("iAssistant must be able to search assets and stock records")
if 'const READ_ONLY_TABLES = ["stock_items", "sensors", "readings"]' not in assistant_endpoint:
    raise SystemExit("iAssistant stock records must remain read-only outside the audited adjustment workflow")
if 'READ_ONLY_TABLES.includes(table)' not in assistant_endpoint:
    raise SystemExit("iAssistant server must reject direct stock create/update proposals")
if "Stock quantities and values must be changed through the audited Stock adjustment workflow." not in assistant_ui:
    raise SystemExit("iAssistant UI must prevent direct stock writes")
if "const AIT=['work_orders','assets','stock_items'" not in assistant_ui:
    raise SystemExit("iAssistant UI does not expose asset and stock lookup schemas")

for marker in [
    'sb.from("stock_levels").select("item_id,on_hand")',
    '.eq("company_id", ctx.company_id)',
    'levelsQuery.eq("site_id", ctx.site_id)',
    'derivedFields = table === "stock_items"',
    'row.on_hand',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"iAssistant stock lookup is missing scoped quantity support: {marker}")



# iAssistant must not report an approved update as successful when no scoped row was changed.
assistant_ui = (root / "maintdesk_app.html").read_text(encoding="utf-8")
approval_start = assistant_ui.find("async function aiApply(p){")
approval_end = assistant_ui.find("async function aiApprove(id,quiet)", approval_start)
approval_block = assistant_ui[approval_start:approval_end] if approval_start >= 0 and approval_end >= 0 else ""
for marker in [
    "await q.select('id').maybeSingle()",
    "if(!updated)throw new Error('The record was not found or is no longer available for this company/site. Nothing was changed.')",
]:
    if marker not in approval_block:
        raise SystemExit(f"iAssistant approval confirmation safeguard missing: {marker}")

if "F('unit','Unit','t')" not in assistant_ui:
    raise SystemExit("Assistant stock lookup schema must expose the stock unit")
for marker in [
    'table === "vehicles"',
    'id,name,reg_no,odometer_km,next_service_km,next_service_date,license_expiry,status',
    'get("fleet_attention", "vehicles"',
    'vehicle.next_service_km',
    'vehicle.license_expiry',
    'licence_expiring_30_days',
    'const columns = table === "sensors"',
    'get("sensor_alerts", "sensors"',
    'sb.from("readings")',
    '.in("sensor_id", sensorIds).order("read_at", { ascending: false }).limit(5000)',
    'sensor.alert_min',
    'sensor.alert_max',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"iAssistant attention summary is missing site-scoped sensor alert support: {marker}")
for marker in [
    'get("low_stock_items", "stock_items"',
    'await build(data || [])',
    'sb.from("stock_levels").select("item_id,on_hand")',
    'levelsQuery.eq("site_id", ctx.site_id)',
    'min_level',
]:
    if marker not in assistant_endpoint:
        raise SystemExit(f"Assistant attention summary is missing low-stock support: {marker}")

print("iAssistant approved-update database confirmation: PASS")


# Industry hub and selected workspace must be reachable through the main screen router.
main_app = (root / "maintdesk_app.html").read_text(encoding="utf-8")
for marker in [
    "cur=='industry_hub'?await sfIndustryHub()",
    "cur=='industry_workspace'?await sfIndustryWorkspace()",
]:
    if marker not in main_app:
        raise SystemExit(f"Industry workspace screen routing regression marker missing: {marker}")
print("Industry hub and selected workspace screen routing: PASS")
