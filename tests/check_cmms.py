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

# Company-scoped document analytics and exports.
for fn, end_marker in [
    ("async function progDocs()", "async function exportDocs("),
    ("async function exportDocs(kind)", "function "),
]:
    start = html.find(fn)
    end = html.find(end_marker, start + len(fn))
    if start < 0 or end < 0:
        raise SystemExit(f"Missing document report/export function: {fn}")
    if ".eq('company_id',me.company_id)" not in html[start:end]:
        raise SystemExit(f"Document report/export is missing company scoping: {fn}")
    if fn.startswith("async function progDocs"):
        report_code = html[start:end]
        for marker in ["if(r.error)", "eq('company_id',me.company_id)", "const cr=await sb.from('customers').select('*').eq('company_id',me.company_id)", "if(cr.error)"]:
            if marker not in report_code:
                raise SystemExit("Invoice report missing tenant/error guard: " + marker)
    if fn.startswith("async function exportDocs") and "customers').select('*').eq('company_id',me.company_id)" not in html[start:end]:
        raise SystemExit("Document export customer lookup is missing company scoping")

# Document editor validates numeric inputs before totals or database writes.
save_start = html.index("async function saveDoc(pr)")
save_end = html.index("async function setDoc(", save_start)
if save_start < 0 or save_end < 0:
    raise SystemExit("Missing document save function")
save_code = html[save_start:save_end]
for marker in [
    "Add a document number.",
    "Invalid document type",
    "Number.isFinite(+l.q)",
    "+l.q<=0",
    "+l.p<0",
    "(+l.x||0)>100",
    "vat<0||vat>100",
    "dp<0||dp>100",
    "paid>t.tot+0.01",
    ".eq('company_id',me.company_id)",
]:
    if marker not in save_code:
        raise SystemExit("Missing document save validation: " + marker)



# Document numbering fails closed if the company/kind lookup errors.
number_start = html.find("async function nextNum(kind)")
number_end = html.find("function invNew(kind)", number_start)
if number_start < 0 or number_end < 0:
    raise SystemExit("Missing safe document numbering function")
number_code = html[number_start:number_end]
for marker in ["if(error)", "return null"]:
    if marker not in number_code:
        raise SystemExit("Document numbering must fail closed on lookup errors")
for marker in ["Could not safely generate a document number", "Could not safely generate an invoice number"]:
    if marker not in html:
        raise SystemExit("Missing safe numbering UI failure message: " + marker)
# Document status and duplication action safeguards.
status_start = html.find("async function setDoc(")
status_end = html.find("async function dupDoc(", status_start)
dup_end = html.find("async function toInvoice(", status_end)
if status_start < 0 or status_end < 0 or dup_end < 0:
    raise SystemExit("Missing document status or duplication functions")
status_code = html[status_start:status_end]
dup_code = html[status_end:dup_end]
for marker in ["d.company_id!==me.company_id", "st==='paid'&&d.kind!=='invoice'", ".eq('kind',d.kind)"]:
    if marker not in status_code:
        raise SystemExit(f"Missing document status guard: {marker}")
for marker in ["d.company_id!==me.company_id", "company_id:me.company_id", "status:'draft'"]:
    if marker not in dup_code:
        raise SystemExit(f"Missing document duplication guard: {marker}")

# Quote-to-invoice validation and failure handling guards.
convert_start = html.find("async function toInvoice(")
convert_end = html.find("async function delDoc(", convert_start)
if convert_start < 0 or convert_end < 0:
    raise SystemExit("Missing quote-to-invoice conversion function")
convert_code = html[convert_start:convert_end]
for marker in [
    "q.company_id!==me.company_id",
    "q.kind!=='quote'",
    "q.status==='cancelled'",
    "x.company_id===me.company_id&&x.kind=='invoice'&&x.converted_from==q.id",
    ".eq('kind','quote')",
    "converted_from==q.id",
    "upd.error",
    "Invoice was created, but the quote status could not be updated",
]:
    if marker not in convert_code:
        raise SystemExit(f"Missing quote conversion guard: {marker}")

# Print and email actions validate the document and company scope before rendering.
action_start = html.index("function printDoc(id)")
action_end = html.index("async function poDoc(", action_start)
action_code = html[action_start:action_end]
for marker in ["d.company_id!==me.company_id", "Document unavailable or outside your company."]:
    if marker not in action_code:
        raise SystemExit("Missing document action guard: " + marker)

# PDF document renderer regression guards.
share_start = html.find("async function shareHtml(")
share_end = html.find("function docPreview(", share_start)
if share_start < 0 or share_end < 0:
    raise SystemExit("Missing quote/invoice PDF sharing renderer")
share_code = html[share_start:share_end]
for marker in [
    "window.html2pdf",
    "html2canvas:{scale:1.5",
    "outputPdf('blob')",
    "blob.slice(0,5).text()",
    "pdfHeader!=='%PDF-'",
    "sheetPrint(html)",
    "brokenImages=imgs.filter(img=>!img.naturalWidth||!img.naturalHeight)",
    "docNode.scrollWidth>docNode.clientWidth+2",
]:
    if marker not in share_code:
        raise SystemExit(f"Missing PDF renderer safety behavior: {marker}")
if "contain:layout style" in share_code:
    raise SystemExit("PDF render staging element still uses layout/style containment")

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

# Legacy invoice PDFs clamp paid and balance figures to the document total.
for marker in [
    "M2(Math.min(t.tot,Math.max(0,m.paid)))",
    "M2(Math.max(0,t.tot-m.paid))",
]:
    if marker not in html:
        raise SystemExit(f"Missing invoice PDF amount clamp: {marker}")

# Legacy invoice status must not claim Paid/Partial without recorded payment.
for marker in [
    "const dstat=d=>{if(d.kind!='invoice')return d.status",
    "if(total>0&&paid>=total)return'paid'",
    "if(paid>0)return'partial'",
    "['paid','partial'].includes(d.status)?'sent':d.status",
]:
    if marker not in html:
        raise SystemExit(f"Missing legacy invoice status normalization: {marker}")

# Print mode must be cleaned after browser printing so the live UI is not left hidden.
for marker in [
    "document.body.classList.remove('one')",
    "window.addEventListener('afterprint',cleanup)",
    "window.removeEventListener('afterprint',cleanup)",
    "sh.innerHTML=''",
    "setTimeout(cleanup,60000)",
]:
    if marker not in html:
        raise SystemExit(f"Missing print cleanup safeguard: {marker}")

# Document numbers are checked for duplicates within company + document kind before save.
for marker in [
    "select('id,number').eq('company_id',me.company_id).eq('kind',e.kind).eq('number',row.number)",
    "Could not verify document number uniqueness",
    "That number is already used for this document type in your company",
]:
    if marker not in html:
        raise SystemExit(f"Missing company-scoped document-number uniqueness guard: {marker}")

# Invoice partial payments must remain visible, editable, and included in balance calculations.
for marker in [
    "'partial'",
    "Record payment",
    "Math.max(0,+d.total-(+d.paid_amount||0))",
    "['sent','overdue','partial']",
]:
    if marker not in html:
        raise SystemExit(f"Missing invoice partial-payment safeguard: {marker}")

# Invoice status is derived from recorded payment, preventing zero-paid "paid" invoices.
for marker in [
    "paid>=t.tot&&t.tot>0?'paid':paid>0?'partial'",
    "['paid','partial'].includes(e.status)?'sent'",
]:
    if marker not in html:
        raise SystemExit(f"Missing invoice payment/status consistency guard: {marker}")


# Document layout rows must wrap and constrain nested blocks to avoid long-field overflow.
for marker in [
    ".dxrow{display:flex;gap:22px;align-items:flex-start;flex-wrap:wrap}",
    ".dxrow>div{min-width:0;max-width:100%;overflow-wrap:anywhere}",
]:
    if marker not in html:
        raise SystemExit(f"Missing PDF layout overflow safeguard: {marker}")

# Copies must not retain quote-conversion lineage; copied invoices are independent.
dup_start = html.find("async function dupDoc(")
dup_end = html.find("async function toInvoice(", dup_start)
if dup_start < 0 or dup_end < 0:
    raise SystemExit("Missing document copy function")
dup_code = html[dup_start:dup_end]
if "delete rest.converted_from" not in dup_code:
    raise SystemExit("Copied documents must not retain quote conversion linkage")

# Document export must surface query failures instead of silently exporting empty data.
export_start = html.find("async function exportDocs(kind)")
export_end = html.find("async function exportCust()", export_start)
if export_start < 0 or export_end < 0:
    raise SystemExit("Missing document export function")
export_code = html[export_start:export_end]
for marker in ["if(r.error)", "Could not load company documents for export", "const cr=await sb.from('customers').select('*').eq('company_id',me.company_id)", "if(cr.error)", "Could not load company customers for export"]:
    if marker not in export_code:
        raise SystemExit("Document export missing query-error guard: " + marker)

# Expense export must be tenant-scoped and fail visibly on query errors.
expense_start = html.find("async function exportExp()")
expense_end = html.find("const val=", expense_start)
if expense_start < 0 or expense_end < 0:
    raise SystemExit("Missing expense export function")
expense_code = html[expense_start:expense_end]
for marker in ["eq('company_id',me.company_id)", "if(r.error)", "Could not load company expenses for export"]:
    if marker not in expense_code:
        raise SystemExit("Expense export missing tenant/error guard: " + marker)

# Customer export must be company-scoped and fail visibly on query errors.
cust_start = html.find("async function exportCust()")
cust_end = html.find("async function exportExp(", cust_start)
if cust_start < 0 or cust_end < 0:
    raise SystemExit("Missing customer export function")
cust_code = html[cust_start:cust_end]
for marker in ["eq('company_id',me.company_id)", "if(r.error)", "Could not load company customers for export"]:
    if marker not in cust_code:
        raise SystemExit("Customer export missing tenant/error guard: " + marker)


# Generic company and site queries must be tenant scoped, including reference tables.
if "const q=(t,c)=>sb.from(t).select(c).eq('company_id',me.company_id).eq('site_id',site)" not in html:
    raise SystemExit("Dashboard/company site helper missing company scope")
if "let q=sb.from(id).select('*').eq('company_id',me.company_id)" not in html:
    raise SystemExit("Generic records list missing company scope")
if "let q=sb.from(f.o[0]).select('id,'+f.o[1]).eq('company_id',me.company_id)" not in html:
    raise SystemExit("Reference table query missing company scope")

# Dashboard invoice summaries must use the signed-in company scope.
dashboard_start = html.find("isMgr()?sb.from('documents').select('kind,status,total,due_date')")
dashboard_end = html.find("Promise.resolve({data:[]})", dashboard_start)
if dashboard_start < 0 or dashboard_end < 0:
    raise SystemExit("Missing dashboard document summary query")
dashboard_code = html[dashboard_start:dashboard_end]
if "eq('company_id',me.company_id)" not in dashboard_code:
    raise SystemExit("Dashboard invoice summary query must be company-scoped")

# Classic invoice inclusive line totals account for document-level discounts.
layout_start = html.find("function tableHtml(m,mode)")
layout_end = html.find("function totHtml(m)", layout_start)
if layout_start < 0 or layout_end < 0:
    raise SystemExit("Missing invoice line-table renderer")
layout_code = html[layout_start:layout_end]
if "1-(+m.d.discount_pct||0)/100" not in layout_code:
    raise SystemExit("Classic invoice inclusive line totals must include document discount")

# Database-level uniqueness protects concurrent quote-to-invoice conversions.
conversion_migration = next((root / "supabase" / "migrations").glob("*_invoice_quote_conversion_unique.sql"))
conversion_sql = conversion_migration.read_text(encoding="utf-8").lower()
for marker in [
    "documents_invoice_converted_from_company_uidx",
    "unique index",
    "where kind = 'invoice' and converted_from is not null",
    "duplicate quote conversions exist",
]:
    if marker not in conversion_sql:
        raise SystemExit(f"Missing invoice conversion database uniqueness safeguard: {marker}")

print("CMMS syntax, notifications, industry profiles, Automation operations, logistics and tenant safeguards: PASS")

# Generic updates and deletes must enforce tenant and (where applicable) site scope.
upd_start = html.find("async function upd(tb,rid,k,t,v,virt)")
upd_end = html.find("async function ins(id)", upd_start)
if upd_start < 0 or upd_end < 0:
    raise SystemExit("Missing generic update function")
upd_code = html[upd_start:upd_end]
for marker in [".eq('id',rid).eq('company_id',me.company_id)", "if(MOD[tb]?.s)q=q.eq('site_id',site)"]:
    if marker not in upd_code:
        raise SystemExit("Generic update missing tenant/site filter: " + marker)
del_start = html.find("async function del(tb,rid)")
del_end = html.find("const STARTER=", del_start)
if del_start < 0 or del_end < 0:
    raise SystemExit("Missing generic delete function")
del_code = html[del_start:del_end]
for marker in [".eq('id',rid).eq('company_id',me.company_id)", "if(MOD[tb]?.s)q=q.eq('site_id',site)"]:
    if marker not in del_code:
        raise SystemExit("Generic delete missing tenant/site filter: " + marker)

# Purchase-order document creation must verify the order and supplier belong to the current tenant.
po_start = html.find("async function poDoc(rid,mode)")
po_end = html.find("// ---------- accounting export ----------", po_start)
if po_start < 0 or po_end < 0:
    raise SystemExit("Missing purchase order document function")
po_code = html[po_start:po_end]
for marker in ["x.id==rid&&x.company_id==me.company_id", ".eq('id',r.supplier_id).eq('company_id',me.company_id)"]:
    if marker not in po_code:
        raise SystemExit("Purchase order document missing tenant check: " + marker)
