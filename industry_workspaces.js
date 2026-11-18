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
    'logistics-transport':[['🚛','Fleet & GPS tracking','Vehicle locations, movement and alerts','fleet'],['🧰','Depot maintenance','Work orders for vehicles, depots and equipment','work_orders'],['🔁','Maintenance schedules','Planned maintenance','pm_schedules'],['📦','Stock & supplies','Depot stock and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['☑️','Inspections','Vehicle and facility checks','chk'],['📊','Reports','Operations and maintenance reporting','rep']],
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
  if(slug==='logistics-transport')html+='<div class="p"><b>Logistics extension</b><div class="note">Dedicated parcel tracking, waybills and proof-of-delivery are not in the current base modules yet. Existing fleet GPS tracking and maintenance tools are available now; parcel and waybill workflows need their own build.</div></div>';
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

const SF_BASE_DRAW=draw;
draw=async function(){
  if(LOCK&&!['sub','sup','set','inbox','act'].includes(cur)){cur='sub';return SF_BASE_DRAW()}
  if(cur==='industry_hub'){V.innerHTML='Loading…';try{V.innerHTML=await sfIndustryHub()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='industry_workspace'){V.innerHTML='Loading…';try{V.innerHTML=await sfIndustryWorkspace()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='service_contracts'){V.innerHTML='Loading…';try{V.innerHTML=await sfServiceContracts()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  return SF_BASE_DRAW();
};

const SF_BASE_MOD=mod;
mod=async function(id){
  const original=MOD[id],automation=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug==='automation';
  if(automation&&id==='work_orders'){
    MOD[id]={...original,l:'Automation service job cards',note:'Create one service job card for every copier or office-equipment call. Link the customer and device, assign a technician, record the reported fault, diagnosis, work performed, page meter, labour hours, approval and parts used.',f:[
      F('job_number','Job card number','t'),F('title','Service call / job title','t'),F('customer_id','Customer','r',['customers','name']),F('asset_id','Copier / office device','r',['assets','name']),
      F('service_type','Service type','s',['callout','onsite','workshop','installation','preventive']),F('reported_problem','Problem reported','x'),F('diagnosis','Diagnosis','x'),F('work_performed','Work performed','x'),
      F('assigned_to','Assigned technician','r',['profiles','full_name']),F('priority','Priority','s',PR),F('status','Progress','s',['open','in_progress','waiting_parts','awaiting_customer','quality_check','done','cancelled']),
      F('due_date','Due date','d'),F('meter_reading','Meter reading (pages)','n'),F('labour_hours','Labour hours','n'),F('customer_approval_status','Customer approval','s',['pending','approved','declined','not_required']),F('lines','Parts and consumables used','li',{tot:'parts_cost'})
    ]};
  }else if(automation&&id==='assets'){
    MOD[id]={...original,l:'Customer equipment',note:'Register each copier, multifunction printer or office device. Link it to a customer and record make, model, serial number and page meter.',f:[
      F('name','Equipment name','t'),F('category','Equipment type','t'),F('customer_id','Customer','r',['customers','name']),F('manufacturer','Manufacturer','t'),F('model','Model','t'),F('serial_no','Serial number','t'),
      F('meter_reading','Current meter reading','n'),F('meter_unit','Meter unit','s',['pages','prints','copies']),F('installed_on','Installed on','d'),F('status','Status','s',['running','faulty','stopped','retired'])
    ]};
  }
  try{
    let html=await SF_BASE_MOD(id);
    if(automation&&id==='work_orders')html=html.replace(/(<button class="eb" onclick="tg\('([^']+)'\)">Edit<\/button>)/g,(m,edit,rid)=>edit+'<button onclick="sfPrintServiceJobCard(\''+rid+'\')">Print job card</button>');
    return html;
  }finally{if(original)MOD[id]=original}
};
