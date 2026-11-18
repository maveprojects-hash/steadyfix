/* STEADYFIX CMMS: industry workspaces and Automation service operations. */
let SF_SERVICE_CONTRACTS = [], SF_SERVICE_CUSTOMERS = [], SF_EDITING_CONTRACT_ID = null;

function openIndustryHub(){cur='industry_hub';draw()}

async function chooseIndustryWorkspace(slug){
  const target=(INDUSTRIES||[]).find(x=>x.slug===slug); if(!target)return;
  const current=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug;
  if(slug!==current){
    if(!isMgr()){alert('Only a company owner or manager can change the company industry workspace.');return}
    if(!confirm('Switch the company workspace to '+target.name+'? The current industry will be kept as a secondary activity where possible.'))return;
    const secondary=[...new Set((INDUSTRY_PROFILE.secondary_industry_slugs||[]).filter(x=>x!==slug))];
    if(current&&!secondary.includes(current)&&secondary.length<8)secondary.push(current);
    const {error}=await sb.from('company_industry_profiles').update({primary_industry_slug:slug,secondary_industry_slugs:secondary}).eq('company_id',me.company_id);
    if(error){alert('Could not switch industry: '+error.message);return}
    await loadIndustryProfile();renderIndustrySelector();
  }
  cur='industry_workspace';draw();
}

async function sfIndustryHub(){
  if(!INDUSTRIES||!INDUSTRIES.length)await loadIndustryProfile();
  const current=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug;
  let html='<h2>Choose your industry workspace</h2><div class="p"><b>One STEADYFIX CMMS. Different industry setups.</b><div class="note">Choose the type of business you operate. STEADYFIX keeps one secure base application and organises its departments, terminology and day-to-day tools around that industry. Owners and managers can change the company primary workspace.</div></div><div class="dg">';
  (INDUSTRIES||[]).forEach(ind=>{
    const focus=(ind.default_configuration&&ind.default_configuration.focus_areas)||[], examples=ind.business_examples||[], active=ind.slug===current;
    html+='<div class="card"><div class="ct"><div>'+esc(ind.name)+'</div>'+(active?'<span class="chip g">Current workspace</span>':'')+'</div>';
    html+='<div class="note">'+esc(ind.description||'')+'</div>';
    if(examples.length)html+='<div class="rl"><b>Typical businesses:</b> '+esc(examples.slice(0,4).join(' · '))+'</div>';
    if(focus.length)html+='<div class="rl"><b>Day-to-day focus:</b> '+esc(focus.slice(0,5).join(' · '))+'</div>';
    html+='<div class="ca"><button class="b" onclick="chooseIndustryWorkspace(\''+esc(ind.slug)+'\')">'+(active?'Open workspace':'Choose this industry')+'</button></div></div>';
  });
  return html+'</div>';
}

function sfIndustryModules(slug){
  const all={
    automation:[['🧰','Service job cards','Create service calls, assign technicians, record labour, progress, faults and parts used','work_orders'],['🖨️','Customer equipment','Register copiers and devices, serial numbers and page meter readings','assets'],['📑','Service contracts','Manage covered devices, service levels, meter allowances and contract dates','service_contracts'],['📦','Stock & consumables','Track toner, drums, staples, spares and reorder levels','stock_items'],['🛒','Parts purchasing','Create supplier purchase orders','purchase_orders'],['👥','Customers','Manage customer accounts and service contacts','customers'],['💳','Quotes & invoicing','Prepare quotes, invoices and customer billing','inv'],['🤝','Suppliers','Manage parts suppliers and service partners','suppliers'],['🔁','Preventive maintenance','Schedule recurring device servicing','pm_schedules'],['☑️','Service checklists','Use repeatable callout, installation and service checklists','chk']],
    'fleet-management':[['🚚','Fleet & tracking','Vehicles, GPS positions, utilisation and alerts','fleet'],['🧰','Maintenance work','Create and assign vehicle maintenance work','work_orders'],['🔁','Service schedules','Plan recurring vehicle maintenance','pm_schedules'],['📦','Parts & stock','Manage workshop parts and consumables','stock_items'],['🛒','Purchasing','Order parts and supplies','purchase_orders'],['☑️','Inspections','Vehicle and fleet checklists','chk'],['📊','Reports','Fleet and maintenance reporting','rep']],
    workshops:[['🔧','Workshop & job cards','Workshop bookings, vehicle job cards and repair progress','fleet'],['🧰','Work orders','Assign maintenance and repair tasks','work_orders'],['📦','Workshop stock','Parts and materials','stock_items'],['🛒','Parts purchasing','Supplier orders','purchase_orders'],['👥','Customers','Customer records','customers'],['💳','Quotes & invoicing','Customer billing','inv'],['☑️','Quality checklists','Inspection and sign-off lists','chk']],
    'logistics-transport':[['📦','Parcel operations','Create waybills, track consignments, record depot scans and capture proof of delivery','logistics_ops'],['🚛','Fleet & GPS tracking','Vehicle locations, movement and alerts','fleet'],['🧰','Depot maintenance','Work orders for vehicles, depots and equipment','work_orders'],['🔁','Maintenance schedules','Planned maintenance','pm_schedules'],['📦','Stock & supplies','Depot stock and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['☑️','Inspections','Vehicle and facility checks','chk'],['📊','Reports','Operations and maintenance reporting','rep']],
    'hospitality-tourism':[['🏨','Property assets','Rooms, plant, equipment and facilities','assets'],['🛠️','Maintenance requests','Guest and staff maintenance tasks','work_orders'],['🔁','Preventive maintenance','Recurring room, plant and facility tasks','pm_schedules'],['☑️','Operating checklists','Daily, weekly and monthly checks','chk'],['📦','Stores & stock','Maintenance stock and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['🦺','Safety & fire','Inspections, incidents and fire equipment','ohs']],
    'food-beverage':[['🍽️','Venue equipment','Kitchen, refrigeration and dining equipment','assets'],['🛠️','Maintenance tasks','Repairs and breakdowns','work_orders'],['🔁','Planned servicing','Recurring equipment maintenance','pm_schedules'],['☑️','Hygiene & operating checks','Repeatable operating and maintenance checklists','chk'],['📦','Stock & supplies','Maintenance consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['🦺','Safety','Workplace and fire safety','ohs']],
    'property-management-facilities':[['🏢','Properties & assets','Buildings, blocks, campuses and facility assets','assets'],['🛠️','Service requests','Tenant, occupant and facilities work orders','work_orders'],['🔁','Preventive maintenance','Recurring building and plant maintenance','pm_schedules'],['☑️','Inspections','Property and facilities checklists','chk'],['⚠️','Damage reports','Record damage and corrective actions','damage_reports'],['📦','Stock & supplies','Maintenance stock','stock_items'],['🤝','Suppliers','Contractors and service providers','suppliers']],
    'manufacturing-industrial':[['🏭','Plant & equipment','Production assets and utilities','assets'],['🛠️','Maintenance work','Breakdown and planned maintenance tasks','work_orders'],['🔁','Preventive maintenance','Recurring plant servicing','pm_schedules'],['📦','Parts & stock','Spare parts and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['⏸️','Shutdowns','Planned shutdown records','shutdowns'],['🦺','Safety','Inspections and incidents','ohs']],
    'general-maintenance':[['🛠️','Work orders','General maintenance and service tasks','work_orders'],['🏢','Assets','Equipment and facilities register','assets'],['🔁','Preventive maintenance','Recurring maintenance schedules','pm_schedules'],['📦','Stock','Parts and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['☑️','Checklists','Repeatable inspections and checks','chk'],['🤝','Suppliers','Suppliers and contractors','suppliers']]
  };
  return all[slug]||all['general-maintenance'];
}

async function sfIndustryWorkspace(){
  if(!INDUSTRIES||!INDUSTRIES.length)await loadIndustryProfile();
  const slug=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug||'general-maintenance';
  const ind=(INDUSTRIES||[]).find(x=>x.slug===slug);if(!ind)return sfIndustryHub();
  let html='<div class="bar2 noprint"><button onclick="openIndustryHub()">← All industries</button><button onclick="goTab(\'dash\')">Main dashboard</button></div>';
  html+='<h2>'+esc(ind.name)+' workspace</h2><div class="p"><b>'+esc(ind.description||'')+'</b><div class="note">This is the company selected industry workspace. The base CMMS records and security remain shared; these shortcuts organise the functions most relevant to this type of operation.</div>';
  const focus=(ind.default_configuration&&ind.default_configuration.focus_areas)||[];
  if(focus.length)html+='<div class="rl"><b>Industry focus:</b> '+esc(focus.join(' · '))+'</div>';
  html+='</div><div class="dg">';
  sfIndustryModules(slug).forEach(m=>{html+='<div class="card"><div class="ct"><div>'+m[0]+' '+esc(m[1])+'</div></div><div class="note">'+esc(m[2])+'</div><div class="ca"><button class="b" onclick="goTab(\''+m[3]+'\')">Open</button></div></div>'});
  html+='</div>';
  if(slug==='logistics-transport')html+='<div class="p"><b>Connected logistics workflow</b><div class="note">Create a consignment, issue its waybill, record tracking scans as it moves through depots, and capture the receiving person and proof-of-delivery reference at delivery. Fleet GPS and vehicle maintenance remain available alongside parcel operations.</div></div>';
  return html;
}

async function sfServiceContracts(){
  if(!isMgr())return '<h2>Service contracts</h2><div class="p">Only company owners and managers can create or change customer service contracts.</div>';
  const [docs,customers]=await Promise.all([
    sb.from('documents').select('*').eq('company_id',me.company_id).eq('site_id',site).eq('kind','service_contract').order('created_at',{ascending:false}),
    sb.from('customers').select('id,name').eq('company_id',me.company_id).order('name')
  ]);
  if(docs.error)throw docs.error;if(customers.error)throw customers.error;
  SF_SERVICE_CONTRACTS=docs.data||[];SF_SERVICE_CUSTOMERS=customers.data||[];
  let options='<option value="">Choose customer</option>';
  SF_SERVICE_CUSTOMERS.forEach(c=>options+='<option value="'+esc(c.id)+'">'+esc(c.name)+'</option>');
  let cards='';
  SF_SERVICE_CONTRACTS.forEach(c=>{
    const devices=Array.isArray(c.covered_devices)?c.covered_devices.join(' · '):'';
    cards+='<div class="card"><div class="ct"><div>'+esc(c.number||'Service contract')+' · '+esc(c.customer_name||'')+'</div><div class="chips">'+chip(c.status||'draft',cap(c.status||'draft'))+'</div></div>';
    cards+='<div class="kv"><span>Type</span><b>'+esc(c.contract_type||'-')+'</b><span>Period</span><b>'+esc(c.start_date||c.issue_date||'-')+' to '+esc(c.end_date||c.due_date||'Open-ended')+'</b><span>Billing</span><b>'+esc(c.billing_cycle||'monthly')+' · '+R(c.monthly_fee||0)+' per cycle</b><span>Response target</span><b>'+esc(c.response_hours==null?'-':c.response_hours+' hours')+'</b><span>Included pages / month</span><b>'+esc(c.included_pages==null?'-':String(c.included_pages))+'</b><span>Overage rate</span><b>'+R(c.overage_rate||0)+' per extra page</b><span>Covered devices</span><b>'+esc(devices||'Not specified')+'</b></div>';
    if(c.notes)cards+='<div class="rl">'+esc(c.notes)+'</div>';
    cards+='<div class="ca noprint"><button onclick="sfEditServiceContract(\''+c.id+'\')">Edit</button><button onclick="sfPrintServiceContract(\''+c.id+'\')">Print</button><button class="x2" onclick="sfDeleteServiceContract(\''+c.id+'\')">Delete</button></div></div>';
  });
  if(!cards)cards='<div class="p">No service contracts yet. Create the first contract below.</div>';
  let html='<h2>Automation service contracts</h2><div class="bar2 noprint"><button onclick="goTab(\'industry_workspace\')">← Automation workspace</button><button onclick="goTab(\'inv\')">Quotes & invoices</button></div>';
  html+='<div class="note">Manage copier and office-equipment service agreements, covered devices, response targets, included page allowances and overage rates. Contract management is restricted to owners and managers.</div>';
  html+='<details class="p noprint" id="sfContractForm"><summary id="sfContractSummary">＋ Create service contract</summary><div class="f" style="margin-top:10px">';
  html+='<label class="el">Contract number<input id="sfContractNumber" placeholder="e.g. SVC-2026-001"></label><label class="el">Customer<select id="sfContractCustomer">'+options+'</select></label>';
  html+='<label class="el">Contract type<select id="sfContractType"><option value="full_service">Full service</option><option value="maintenance_only">Maintenance only</option><option value="rental">Equipment rental</option><option value="toner_inclusive">Toner inclusive</option><option value="metered">Metered / cost per page</option></select></label>';
  html+='<label class="el">Start date<input id="sfContractStart" type="date" value="'+today+'"></label><label class="el">End date<input id="sfContractEnd" type="date"></label>';
  html+='<label class="el">Status<select id="sfContractStatus"><option value="draft">Draft</option><option value="active">Active</option><option value="suspended">Suspended</option><option value="expired">Expired</option><option value="cancelled">Cancelled</option></select></label>';
  html+='<label class="el">Billing cycle<select id="sfContractCycle"><option value="monthly">Monthly</option><option value="quarterly">Quarterly</option><option value="annually">Annually</option><option value="per_page">Per page</option></select></label>';
  html+='<label class="el">Monthly / cycle fee<input id="sfContractFee" type="number" min="0" step="0.01" value="0"></label><label class="el">Response target (hours)<input id="sfContractResponse" type="number" min="0" step="0.5" value="4"></label>';
  html+='<label class="el">Included pages per month<input id="sfContractPages" type="number" min="0" step="1" value="0"></label><label class="el">Overage rate per extra page<input id="sfContractOverage" type="number" min="0" step="0.0001" value="0"></label>';
  html+='<label class="el">Covered devices (one per line)<textarea id="sfContractDevices" placeholder="Copier model · serial number"></textarea></label><label class="el">Contract scope and terms<textarea id="sfContractNotes" placeholder="Coverage, exclusions, service hours, consumables and renewal terms"></textarea></label>';
  html+='</div><div class="ca"><button class="b" onclick="sfSaveServiceContract()">Save contract</button><button onclick="sfResetServiceContract()">Cancel</button></div></details>'+cards;
  return html;
}

async function sfSaveServiceContract(){
  const customerId=$('sfContractCustomer').value,customer=SF_SERVICE_CUSTOMERS.find(c=>c.id===customerId);
  const number=$('sfContractNumber').value.trim(),startDate=$('sfContractStart').value,endDate=$('sfContractEnd').value||null;
  if(!customer||!number||!startDate)return alert('Choose a customer and enter a contract number and start date.');
  if(endDate&&endDate<startDate)return alert('The contract end date cannot be before its start date.');
  const fee=Math.max(0,Number($('sfContractFee').value)||0);
  const row={company_id:me.company_id,site_id:site,kind:'service_contract',number,customer_id:customer.id,customer_name:customer.name,issue_date:startDate,due_date:endDate,start_date:startDate,end_date:endDate,status:$('sfContractStatus').value,currency:(CS&&CS.currency)||'R',vat_rate:(CS&&CS.tax_rate)||15,contract_type:$('sfContractType').value,billing_cycle:$('sfContractCycle').value,monthly_fee:fee,subtotal:fee,vat_amount:0,total:fee,response_hours:Math.max(0,Number($('sfContractResponse').value)||0),included_pages:Math.max(0,Number($('sfContractPages').value)||0),overage_rate:Math.max(0,Number($('sfContractOverage').value)||0),covered_devices:$('sfContractDevices').value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean),notes:$('sfContractNotes').value.trim()};
  const result=SF_EDITING_CONTRACT_ID?await sb.from('documents').update(row).eq('id',SF_EDITING_CONTRACT_ID).eq('kind','service_contract'):await sb.from('documents').insert(row);
  if(result.error)return alert('Could not save the service contract: '+result.error.message);
  SF_EDITING_CONTRACT_ID=null;draw();
}
function sfEditServiceContract(id){
  const c=SF_SERVICE_CONTRACTS.find(x=>x.id===id);if(!c)return;SF_EDITING_CONTRACT_ID=id;
  $('sfContractNumber').value=c.number||'';$('sfContractCustomer').value=c.customer_id||'';$('sfContractType').value=c.contract_type||'full_service';
  $('sfContractStart').value=c.start_date||c.issue_date||'';$('sfContractEnd').value=c.end_date||c.due_date||'';$('sfContractStatus').value=c.status||'draft';
  $('sfContractCycle').value=c.billing_cycle||'monthly';$('sfContractFee').value=c.monthly_fee??c.total??0;$('sfContractResponse').value=c.response_hours??4;
  $('sfContractPages').value=c.included_pages??0;$('sfContractOverage').value=c.overage_rate??0;$('sfContractDevices').value=Array.isArray(c.covered_devices)?c.covered_devices.join('\n'):'';
  $('sfContractNotes').value=c.notes||'';$('sfContractSummary').textContent='Edit service contract';$('sfContractForm').open=true;$('sfContractForm').scrollIntoView({behavior:'smooth',block:'start'});
}
function sfResetServiceContract(){
  SF_EDITING_CONTRACT_ID=null;const f=$('sfContractForm');if(!f)return;
  f.querySelectorAll('input,select,textarea').forEach(el=>{if(el.id==='sfContractStart')el.value=today;else if(['sfContractFee','sfContractPages','sfContractOverage'].includes(el.id))el.value=0;else if(el.id==='sfContractResponse')el.value=4;else el.value=''});
  $('sfContractStatus').value='draft';$('sfContractType').value='full_service';$('sfContractCycle').value='monthly';$('sfContractSummary').textContent='＋ Create service contract';
}
async function sfDeleteServiceContract(id){
  if(!confirm('Delete this service contract?'))return;
  const {error}=await sb.from('documents').delete().eq('id',id).eq('kind','service_contract');if(error)alert(error.message);else draw();
}
function sfPrintServiceContract(id){
  const c=SF_SERVICE_CONTRACTS.find(x=>x.id===id);if(!c)return;let sh=$('sheet');if(!sh){sh=document.createElement('div');sh.id='sheet';document.body.appendChild(sh)}
  const row=(l,v)=>'<tr><th style="width:32%">'+l+'</th><td>'+esc(v==null||v===''?'-':String(v))+'</td></tr>';
  sh.innerHTML='<h2>'+esc(CS.label||CO)+' · Service contract</h2><p><b>Contract '+esc(c.number||'')+'</b></p><table class="pt">'+row('Customer',c.customer_name)+row('Type',c.contract_type)+row('Status',c.status)+row('Start date',c.start_date||c.issue_date)+row('End date',c.end_date||c.due_date)+row('Billing cycle',c.billing_cycle)+row('Fee',R(c.monthly_fee||0))+row('Response target',(c.response_hours||0)+' hours')+row('Included pages / month',c.included_pages)+row('Overage rate',R(c.overage_rate||0)+' per page')+'</table><p><b>Covered devices</b></p><div class="box">'+esc((c.covered_devices||[]).join('\n')||'Not specified')+'</div><p><b>Scope and terms</b></p><div class="box">'+esc(c.notes||'')+'</div><p style="margin-top:36px">Customer signature: _____________________ Date: __________</p><p>Service provider: ________________________ Date: __________</p>';
  document.body.classList.add('one');setTimeout(()=>window.print(),120);
}
function sfPrintServiceJobCard(id){
  const r=(LAST&&LAST.rows||[]).find(x=>x.id===id);if(!r)return;
  const find=(t,k)=>((LAST&&LAST.refs&&LAST.refs[t])||[]).find(x=>x.id===k);
  const customer=find('customers',r.customer_id),asset=find('assets',r.asset_id),tech=find('profiles',r.assigned_to);
  let sh=$('sheet');if(!sh){sh=document.createElement('div');sh.id='sheet';document.body.appendChild(sh)}
  const row=(l,v)=>'<tr><th style="width:32%">'+l+'</th><td>'+esc(v==null||v===''?'-':String(v))+'</td></tr>';
  const parts=Array.isArray(r.lines)?r.lines.map(x=>'<tr><td>'+esc(x.d||'')+'</td><td>'+esc(x.q||0)+'</td><td>'+R(x.p||0)+'</td><td>'+R((+x.q||0)*(+x.p||0))+'</td></tr>').join(''):'';
  sh.innerHTML='<h2>'+esc(CS.label||CO)+' · Automation service job card</h2><p><b>Job card '+esc(r.job_number||'')+'</b> · '+esc(r.title||'')+'</p><table class="pt">'+row('Customer',customer&&customer.name)+row('Equipment',asset&&asset.name)+row('Assigned technician',(tech&&tech.full_name)||r.assigned_name)+row('Service type',r.service_type)+row('Priority',r.priority)+row('Progress',r.status)+row('Due date',r.due_date)+row('Meter reading',r.meter_reading)+row('Labour hours',r.labour_hours)+row('Customer approval',r.customer_approval_status)+'</table><p><b>Problem reported</b></p><div class="box">'+esc(r.reported_problem||'')+'</div><p><b>Diagnosis</b></p><div class="box">'+esc(r.diagnosis||'')+'</div><p><b>Work performed</b></p><div class="box">'+esc(r.work_performed||'')+'</div><p><b>Parts and consumables used</b></p><table class="pt"><tr><th>Item</th><th>Qty</th><th>Unit cost</th><th>Total</th></tr>'+(parts||'<tr><td colspan="4">No parts recorded</td></tr>')+'</table><p style="margin-top:36px">Technician signature: _____________________ Date: __________</p><p>Customer approval: _______________________ Date: __________</p>';
  document.body.classList.add('one');setTimeout(()=>window.print(),120);
}



// ---------- Job card labour and controlled stock issue ----------
async function sfOpenJobOperations(id){
  SF_JOB_OPERATIONS_ID=id;cur='job_operations';draw();
}
let SF_JOB_OPERATIONS_ID=null;
async function sfJobOperations(){
  const id=SF_JOB_OPERATIONS_ID;if(!id)return '<h2>Job operations</h2><div class="p">Choose a service job card first.</div>';
  const [wr,tm,mi,st,lv,ps]=await Promise.all([
    sb.from('work_orders').select('*').eq('id',id).eq('company_id',me.company_id).eq('site_id',site).maybeSingle(),
    sb.from('work_order_time_entries').select('*').eq('work_order_id',id).eq('site_id',site).order('work_date',{ascending:false}).order('created_at',{ascending:false}),
    sb.from('work_order_material_issues').select('*').eq('work_order_id',id).eq('site_id',site).order('issued_at',{ascending:false}),
    sb.from('stock_items').select('id,name,sku,unit,unit_cost').eq('company_id',me.company_id).order('name'),
    sb.from('stock_levels').select('item_id,on_hand').eq('company_id',me.company_id).eq('site_id',site),
    sb.from('profiles').select('id,full_name,role').eq('company_id',me.company_id).eq('active',true).order('full_name')
  ]);
  if(wr.error)throw wr.error;if(!wr.data)return '<h2>Job operations</h2><div class="p">This job card is not available at the selected site.</div>';
  for(const x of [tm,mi,st,lv,ps])if(x.error)throw x.error;
  const w=wr.data,items=st.data||[],levels=Object.fromEntries((lv.data||[]).map(x=>[x.item_id,+x.on_hand||0]));
  const staff=(ps.data||[]).filter(p=>isMgr()||p.id===me.id);
  const chosen=staff.some(p=>p.id===w.assigned_to)?w.assigned_to:me.id;
  const timeRows=tm.data||[],materialRows=mi.data||[];
  const timeTotal=timeRows.reduce((a,x)=>a+(+x.hours||0),0),labourCost=timeRows.reduce((a,x)=>a+(+x.hours||0)*(+x.hourly_rate||0),0);
  const timeHtml=timeRows.map(x=>'<div class="rl"><b>'+esc((ps.data||[]).find(p=>p.id===x.technician_id)?.full_name||'Technician')+'</b> · '+esc(x.work_date)+' · '+esc(x.hours)+' h'+(x.hourly_rate?' · '+R((+x.hours||0)*(+x.hourly_rate||0)):'')+(x.notes?'<div class="note">'+esc(x.notes)+'</div>':'')+'</div>').join('')||'<div class="note">No labour entries recorded yet.</div>';
  const matHtml=materialRows.map(x=>'<div class="rl"><b>'+esc(x.item_name||items.find(i=>i.id===x.stock_item_id)?.name||'Stock item')+'</b> · '+esc(x.quantity)+' '+esc(x.unit||'units')+' · '+R(x.total_cost||0)+'<div class="note">'+esc(new Date(x.issued_at).toLocaleString('en-ZA'))+(x.notes?' · '+esc(x.notes):'')+'</div></div>').join('')||'<div class="note">No stock has been issued to this job card yet.</div>';
  const staffOptions=staff.map(p=>'<option value="'+p.id+'" '+(p.id===chosen?'selected':'')+'>'+esc(p.full_name)+' · '+esc(p.role)+'</option>').join('');
  const itemOptions=items.map(i=>'<option value="'+i.id+'">'+esc(i.name)+(i.sku?' · '+esc(i.sku):'')+' — '+levels[i.id]+' '+esc(i.unit||'units')+' available</option>').join('');
  return '<div class="bar2 noprint"><button onclick="goTab(\'work_orders\')">← Back to job cards</button><button onclick="sfPrintServiceJobCard(\''+id+'\')">Print job card</button></div>'+
    '<h2>Job operations · '+esc(w.job_number||w.title||'Service job')+'</h2>'+
    '<div class="p"><b>'+esc(w.title||'Service job')+'</b><div class="note">'+esc(w.reported_problem||w.description||'No fault description recorded')+'</div><div class="kv"><span>Status</span><b>'+esc(cap(w.status))+'</b><span>Assigned technician</span><b>'+esc(w.assigned_name||'-')+'</b><span>Labour logged</span><b>'+timeTotal.toFixed(2)+' hours</b><span>Labour value</span><b>'+R(labourCost)+'</b><span>Parts issued</span><b>'+materialRows.length+' issue entries</b></div></div>'+
    '<div class="dg"><div class="p"><b>Record technician labour</b><div class="note">Record actual time spent against this job card. Technicians can record their own time; managers can record time for the team.</div>'+
    '<label class="el">Technician<select id="sfTimeTech" '+(!isMgr()?'disabled':'')+'>'+staffOptions+'</select></label>'+
    '<label class="el">Work date<input id="sfTimeDate" type="date" value="'+today+'"></label><label class="el">Hours worked<input id="sfTimeHours" type="number" min="0.01" max="24" step="0.25" placeholder="e.g. 1.5"></label>'+
    '<label class="el">Hourly rate (optional)<input id="sfTimeRate" type="number" min="0" step="0.01" value="0"></label><label class="el">Work notes<textarea id="sfTimeNotes" placeholder="What work was completed during this time?"></textarea></label>'+
    '<button class="b" onclick="sfSaveJobTime(\''+id+'\')">Save labour entry</button></div>'+
    '<div class="p"><b>Issue parts and consumables</b><div class="note">Stock is deducted from this site only. The issue is recorded against the job card, with the quantity and cost retained in the audit record.</div>'+
    '<label class="el">Stock item<select id="sfIssueItem">'+itemOptions+'</select></label><label class="el">Quantity<input id="sfIssueQty" type="number" min="0.001" step="0.001" value="1"></label>'+
    '<label class="el">Issue note<input id="sfIssueNotes" placeholder="e.g. Black toner cartridge"></label><button class="b" onclick="sfIssueJobStock(\''+id+'\')">Issue stock to job</button></div></div>'+
    '<div class="dg"><div class="p"><b>Labour history</b><div class="g"><div class="k"><b>'+timeTotal.toFixed(2)+'</b><span>Total hours</span></div><div class="k"><b>'+R(labourCost)+'</b><span>Labour value</span></div></div>'+timeHtml+'</div>'+
    '<div class="p"><b>Parts issued to this job</b>'+matHtml+'</div></div>';
}
async function sfSaveJobTime(id){
  const hours=Number($('sfTimeHours').value),rate=Number($('sfTimeRate').value)||0,tech=$('sfTimeTech').value;
  if(!tech||!Number.isFinite(hours)||hours<=0||hours>24||rate<0)return alert('Enter a valid technician, hours (up to 24) and non-negative hourly rate.');
  const {error}=await sb.from('work_order_time_entries').insert({company_id:me.company_id,site_id:site,work_order_id:id,technician_id:tech,work_date:$('sfTimeDate').value||today,hours,hourly_rate:rate,notes:$('sfTimeNotes').value.trim()||null,created_by:me.id});
  if(error)return alert('Could not save labour entry: '+error.message);
  draw();
}
async function sfIssueJobStock(id){
  const item=$('sfIssueItem').value,qty=Number($('sfIssueQty').value);
  if(!item||!Number.isFinite(qty)||qty<=0)return alert('Choose a stock item and enter a quantity greater than zero.');
  const {data,error}=await sb.rpc('issue_work_order_stock',{p_work_order_id:id,p_stock_item_id:item,p_quantity:qty,p_notes:$('sfIssueNotes').value.trim()||null});
  if(error)return alert('Stock was not issued: '+error.message);
  alert('Stock issued successfully. Remaining site quantity: '+(data?.remaining_quantity??'updated'));
  draw();
}

// ---------- Logistics parcel, waybill and proof-of-delivery workspace ----------
let SF_LOGISTICS_SHIPMENTS=[];
const SF_SHIPMENT_STATUSES=['booked','collected','in_transit','at_depot','out_for_delivery','delivered','exception','returned'];
async function sfLogisticsWorkspace(){
  const [sr,ev]=await Promise.all([
    sb.from('logistics_shipments').select('*').eq('company_id',me.company_id).eq('site_id',site).order('created_at',{ascending:false}),
    sb.from('logistics_tracking_events').select('*').eq('company_id',me.company_id).eq('site_id',site).order('event_at',{ascending:false}).limit(500)
  ]);
  if(sr.error)throw sr.error;if(ev.error)throw ev.error;
  SF_LOGISTICS_SHIPMENTS=sr.data||[];const events=ev.data||[];
  const count=s=>SF_LOGISTICS_SHIPMENTS.filter(x=>x.status===s).length;
  const cards=SF_LOGISTICS_SHIPMENTS.map(x=>{
    const history=events.filter(e=>e.shipment_id===x.id).slice(0,8);
    const opts=SF_SHIPMENT_STATUSES.map(s=>'<option value="'+s+'" '+(s===x.status?'selected':'')+'>'+esc(cap(s))+'</option>').join('');
    return '<div class="card"><div class="ct"><div>'+esc(x.waybill_no)+' · '+esc(x.recipient_name)+'</div><div class="chips">'+chip(x.status,cap(x.status))+'</div></div>'+
      '<div class="kv"><span>Tracking number</span><b>'+esc(x.tracking_no||x.waybill_no)+'</b><span>From</span><b>'+esc(x.origin_address)+'</b><span>To</span><b>'+esc(x.destination_address)+'</b><span>Parcel</span><b>'+esc(x.package_count)+' package(s) · '+esc(x.parcel_description||'-')+'</b><span>Expected delivery</span><b>'+esc(x.expected_delivery||'-')+'</b></div>'+
      (x.status==='delivered'?'<div class="p"><b>Proof of delivery</b><div class="kv"><span>Received by</span><b>'+esc(x.pod_recipient_name||'-')+'</b><span>Delivered at</span><b>'+esc(x.delivered_at?new Date(x.delivered_at).toLocaleString('en-ZA'):'-')+'</b><span>Reference</span><b>'+esc(x.pod_reference||'-')+'</b><span>Notes</span><b>'+esc(x.pod_notes||'-')+'</b></div></div>':'')+
      '<div class="ca noprint"><button onclick="sfPrintWaybill(\''+x.id+'\')">Print waybill</button><button onclick="sfAddShipmentScan(\''+x.id+'\')">Add tracking scan</button><button onclick="sfCapturePOD(\''+x.id+'\')">Proof of delivery</button>'+ (isMgr()?'<button class="x2" onclick="sfDeleteShipment(\''+x.id+'\')">Delete</button>':'')+'</div>'+
      '<label class="el noprint">Update shipment status<select onchange="sfUpdateShipmentStatus(\''+x.id+'\',this.value)">'+opts+'</select></label>'+
      '<div class="rl"><b>Tracking history</b></div>'+ (history.map(e=>'<div class="rl">'+esc(new Date(e.event_at).toLocaleString('en-ZA'))+' · <b>'+esc(cap(e.status||e.event_type))+'</b>'+(e.location?' · '+esc(e.location):'')+(e.notes?'<div class="note">'+esc(e.notes)+'</div>':'')+'</div>').join('')||'<div class="note">No scans recorded yet.</div>')+
      '</div>';
  }).join('')||'<div class="p">No consignments yet. Create your first waybill below.</div>';
  return '<div class="bar2 noprint"><button onclick="goTab(\'industry_workspace\')">← Logistics workspace</button><button onclick="goTab(\'fleet\')">Fleet & GPS</button><button onclick="goTab(\'rep\')">Reports</button></div>'+
    '<h2>Parcel operations & waybills</h2><div class="note">Create consignments, print waybills, track each depot hand-off and capture the receiving person and proof-of-delivery reference. All records are restricted to this company and site.</div>'+
    '<div class="g"><div class="k"><b>'+SF_LOGISTICS_SHIPMENTS.length+'</b><span>Total consignments</span></div><div class="k"><b>'+count('in_transit')+'</b><span>In transit</span></div><div class="k"><b>'+count('out_for_delivery')+'</b><span>Out for delivery</span></div><div class="k"><b>'+count('delivered')+'</b><span>Delivered</span></div><div class="k"><b>'+count('exception')+'</b><span>Exceptions</span></div></div>'+
    '<details class="p noprint" open><summary>＋ Create consignment / waybill</summary><div class="f" style="margin-top:10px">'+
    '<label class="el">Waybill number<input id="sfWaybill" placeholder="e.g. SF-2026-0001"></label><label class="el">Tracking number<input id="sfTracking" placeholder="Optional; defaults to waybill"></label>'+
    '<label class="el">Sender / account<input id="sfSender" placeholder="Sender name"></label><label class="el">Recipient name<input id="sfRecipient" placeholder="Receiving person or company"></label><label class="el">Recipient phone<input id="sfRecipientPhone" placeholder="Phone number"></label>'+
    '<label class="el">Origin / collection address<textarea id="sfOrigin"></textarea></label><label class="el">Destination / delivery address<textarea id="sfDestination"></textarea></label>'+
    '<label class="el">Parcel contents<input id="sfParcel" placeholder="Description of goods"></label><label class="el">Package count<input id="sfPackageCount" type="number" min="1" step="1" value="1"></label><label class="el">Weight (kg)<input id="sfWeight" type="number" min="0" step="0.01"></label>'+
    '<label class="el">Service level<select id="sfServiceLevel"><option value="standard">Standard</option><option value="express">Express</option><option value="overnight">Overnight</option><option value="same_day">Same day</option></select></label><label class="el">Expected delivery<input id="sfExpected" type="date"></label></div>'+
    '<button class="b" onclick="sfCreateShipment()">Create waybill</button></details>'+cards;
}
async function sfCreateShipment(){
  const waybill=$('sfWaybill').value.trim(),recipient=$('sfRecipient').value.trim(),origin=$('sfOrigin').value.trim(),destination=$('sfDestination').value.trim();
  if(!waybill||!recipient||!origin||!destination)return alert('Waybill number, recipient, origin and destination are required.');
  const row={company_id:me.company_id,site_id:site,waybill_no:waybill,tracking_no:$('sfTracking').value.trim()||waybill,sender_name:$('sfSender').value.trim()||null,recipient_name:recipient,recipient_phone:$('sfRecipientPhone').value.trim()||null,origin_address:origin,destination_address:destination,parcel_description:$('sfParcel').value.trim()||null,package_count:Math.max(1,parseInt($('sfPackageCount').value,10)||1),weight_kg:$('sfWeight').value===''?null:Number($('sfWeight').value),service_level:$('sfServiceLevel').value,expected_delivery:$('sfExpected').value||null,status:'booked',created_by:me.id};
  const {error}=await sb.from('logistics_shipments').insert(row);if(error)return alert('Could not create waybill: '+error.message);draw();
}
async function sfUpdateShipmentStatus(id,status){
  if(!SF_SHIPMENT_STATUSES.includes(status))return;
  if(status==='delivered'){sfCapturePOD(id);return;}
  const {error}=await sb.from('logistics_shipments').update({status,delivered_at:status==='delivered'?new Date().toISOString():null}).eq('id',id).eq('company_id',me.company_id).eq('site_id',site);
  if(error)alert('Could not update shipment: '+error.message);else draw();
}
async function sfAddShipmentScan(id){
  const location=prompt('Depot, town or scan location:');if(location===null)return;
  const notes=prompt('Scan notes (optional):')||null;
  const shipment=SF_LOGISTICS_SHIPMENTS.find(x=>x.id===id);if(!shipment)return;
  const {error}=await sb.from('logistics_tracking_events').insert({company_id:me.company_id,site_id:site,shipment_id:id,event_type:'scan',status:shipment.status,location:location.trim()||null,notes,created_by:me.id});
  if(error)alert('Could not save tracking scan: '+error.message);else draw();
}
async function sfCapturePOD(id){
  const recipient=prompt('Name of the person who received the parcel:');if(!recipient||!recipient.trim())return;
  const reference=prompt('Proof-of-delivery reference (signed slip, photo reference or delivery code):')||null;
  const notes=prompt('Delivery notes (optional):')||null;
  const {error}=await sb.from('logistics_shipments').update({status:'delivered',delivered_at:new Date().toISOString(),pod_recipient_name:recipient.trim(),pod_reference:reference&&reference.trim()||null,pod_notes:notes&&notes.trim()||null}).eq('id',id).eq('company_id',me.company_id).eq('site_id',site);
  if(error)alert('Could not save proof of delivery: '+error.message);else draw();
}
async function sfDeleteShipment(id){
  if(!isMgr()||!confirm('Delete this consignment and its tracking history?'))return;
  const {error}=await sb.from('logistics_shipments').delete().eq('id',id).eq('company_id',me.company_id).eq('site_id',site);
  if(error)alert(error.message);else draw();
}
function sfPrintWaybill(id){
  const x=SF_LOGISTICS_SHIPMENTS.find(s=>s.id===id);if(!x)return;
  const row=(l,v)=>'<tr><th style="width:32%">'+l+'</th><td>'+esc(v==null||v===''?'-':String(v))+'</td></tr>';
  sheetPrint(ph('Transport waybill')+'<br><table class="pt">'+row('Waybill number',x.waybill_no)+row('Tracking number',x.tracking_no)+row('Service level',cap(x.service_level))+row('Status',cap(x.status))+row('Sender',x.sender_name)+row('Recipient',x.recipient_name)+row('Recipient phone',x.recipient_phone)+row('Origin',x.origin_address)+row('Destination',x.destination_address)+row('Contents',x.parcel_description)+row('Packages',x.package_count)+row('Weight (kg)',x.weight_kg)+row('Expected delivery',x.expected_delivery)+'</table><p><b>Driver / collection signature</b> ___________________________</p><p><b>Receiver signature / name</b> ___________________________ Date: __________</p>');
}

// Extend the existing navigation without creating a second app or changing shared base records.

const SF_BASE_DRAW=draw;
draw=async function(){
  if(LOCK&&!['sub','sup','set','inbox','act'].includes(cur)){cur='sub';return SF_BASE_DRAW()}
  if(cur==='industry_hub'){V.innerHTML='Loading…';try{V.innerHTML=await sfIndustryHub()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='industry_workspace'){V.innerHTML='Loading…';try{V.innerHTML=await sfIndustryWorkspace()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='service_contracts'){V.innerHTML='Loading…';try{V.innerHTML=await sfServiceContracts()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='job_operations'){V.innerHTML='Loading…';try{V.innerHTML=await sfJobOperations()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='logistics_ops'){V.innerHTML='Loading…';try{V.innerHTML=await sfLogisticsWorkspace()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  return SF_BASE_DRAW();
};

const SF_BASE_MOD=mod;
const SF_ORIGINAL_WORK_ORDERS=MOD.work_orders, SF_ORIGINAL_ASSETS=MOD.assets;
function sfApplyAutomationModules(){
  const automation=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug==='automation';
  if(!automation){MOD.work_orders=SF_ORIGINAL_WORK_ORDERS;MOD.assets=SF_ORIGINAL_ASSETS;return}
  MOD.work_orders={...SF_ORIGINAL_WORK_ORDERS,l:'Automation service job cards',note:'Create one service job card for every copier or office-equipment call. Link the customer and device, assign a technician, record the reported fault, diagnosis, work performed, page meter, labour hours, approval and parts used.',f:[
    F('job_number','Job card number','t'),F('title','Service call / job title','t'),F('customer_id','Customer','r',['customers','name']),F('asset_id','Copier / office device','r',['assets','name']),
    F('service_type','Service type','s',['callout','onsite','workshop','installation','preventive']),F('reported_problem','Problem reported','x'),F('diagnosis','Diagnosis','x'),F('work_performed','Work performed','x'),
    F('assigned_to','Assigned technician','r',['profiles','full_name']),F('priority','Priority','s',PR),F('status','Progress','s',['open','in_progress','waiting_parts','awaiting_customer','quality_check','done','cancelled']),
    F('due_date','Due date','d'),F('meter_reading','Meter reading (pages)','n'),F('labour_hours','Labour hours','n'),F('customer_approval_status','Customer approval','s',['pending','approved','declined','not_required']),F('lines','Parts and consumables used','li',{tot:'parts_cost'})
  ]};
  MOD.assets={...SF_ORIGINAL_ASSETS,l:'Customer equipment',note:'Register each copier, multifunction printer or office device. Link it to a customer and record make, model, serial number and page meter.',f:[
    F('name','Equipment name','t'),F('category','Equipment type','t'),F('customer_id','Customer','r',['customers','name']),F('manufacturer','Manufacturer','t'),F('model','Model','t'),F('serial_no','Serial number','t'),
    F('meter_reading','Current meter reading','n'),F('meter_unit','Meter unit','s',['pages','prints','copies']),F('installed_on','Installed on','d'),F('status','Status','s',['running','faulty','stopped','retired'])
  ]};
}
mod=async function(id){
  sfApplyAutomationModules();
  const automation=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug==='automation';
  let html=await SF_BASE_MOD(id);
  if(automation&&id==='work_orders')html=html.replace(/(<button class="eb" onclick="tg\('([^']+)'\)">Edit<\/button>)/g,(m,edit,rid)=>edit+'<button onclick="sfPrintServiceJobCard(\''+rid+'\')">Print job card</button><button onclick="sfOpenJobOperations(\''+rid+'\')">Labour & parts</button>');
  return html;
};
