/* STEADYFIX CMMS: industry workspaces and Automation service operations. */

/* Industry identity palettes: shared across the browser app and desktop wrapper. */
const SF_INDUSTRY_THEMES = {
  automation: { accent:'#d62828', highlight:'#2878c8', nav:'#172b4d', bg:'#eaf0f8', panel:'#ffffff', line:'#c8d5e6', ink:'#1d2d46', muted:'#586b86' },
  'fleet-management': { accent:'#c46a13', highlight:'#f2b84b', nav:'#352311', bg:'#f8f0e5', panel:'#fffdf9', line:'#e7d5bc', ink:'#35291c', muted:'#766451' },
  workshops: { accent:'#c04472', highlight:'#f39abb', nav:'#351b2a', bg:'#f7edf2', panel:'#fffdfc', line:'#e8cbd8', ink:'#382330', muted:'#78606b' },
  'logistics-transport': { accent:'#0d9488', highlight:'#5eead4', nav:'#102d2b', bg:'#e8f3f1', panel:'#ffffff', line:'#c6dfda', ink:'#193632', muted:'#58736d' },
  'hospitality-tourism': { accent:'#7954b8', highlight:'#c4a7f4', nav:'#271e39', bg:'#f0edf6', panel:'#ffffff', line:'#d8cde8', ink:'#30263f', muted:'#6c617b' },
  'food-beverage': { accent:'#47864b', highlight:'#9bd18e', nav:'#203322', bg:'#edf3eb', panel:'#ffffff', line:'#cfddca', ink:'#263528', muted:'#617363' },
  'property-management-facilities': { accent:'#2878c8', highlight:'#8ec5ff', nav:'#192c42', bg:'#eaf0f6', panel:'#ffffff', line:'#cbd8e6', ink:'#203246', muted:'#5c6f82' },
  'construction-project-management': { accent:'#b7791f', highlight:'#f6c453', nav:'#342a18', bg:'#f4f0e6', panel:'#fffefa', line:'#e2d6bd', ink:'#332b1e', muted:'#75684f' },
  'manufacturing-industrial': { accent:'#52647f', highlight:'#9fb4d4', nav:'#202b3b', bg:'#edf0f5', panel:'#fffefa', line:'#d1d9e5', ink:'#273449', muted:'#64748b' },
  'general-maintenance': { accent:'#167caa', highlight:'#e59f0f', nav:'#18313d', bg:'#e9f1f4', panel:'#ffffff', line:'#cbdde3', ink:'#1b3038', muted:'#58717a' }
};

function applyIndustryTheme() {
  const slug = INDUSTRY_PROFILE?.primary_industry_slug || 'hospitality-tourism';
  const theme = SF_INDUSTRY_THEMES[slug] || SF_INDUSTRY_THEMES['general-maintenance'];
  const root = document.documentElement;
  root.style.setProperty('--ac', theme.accent);
  root.style.setProperty('--am', theme.highlight);
  root.style.setProperty('--nav', theme.nav);
  root.style.setProperty('--bg', theme.bg);
  root.style.setProperty('--pn', theme.panel);
  root.style.setProperty('--ln', theme.line);
  root.style.setProperty('--ink', theme.ink);
  root.style.setProperty('--mut', theme.muted);
  document.body.dataset.industryTheme = slug;
  const themeMeta = document.querySelector('meta[name="theme-color"]');
  if (themeMeta) themeMeta.setAttribute('content', theme.nav);
}
let SF_SERVICE_CONTRACTS = [], SF_SERVICE_CUSTOMERS = [], SF_EDITING_CONTRACT_ID = null;

function openIndustryHub(){cur='industry_hub';draw()}

async function chooseIndustryWorkspace(slug){
  const target=(INDUSTRIES||[]).find(x=>x.slug===slug); if(!target)return;
  const current=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug;
  if(slug!==current){
    if(!isMgr()){alert('Only a company owner or manager can change the company industry workspace.');return}
    if(!confirm('Switch the company workspace to '+target.name+'? The current industry will be kept as a secondary activity where possible.'))return;
    const secondary=[...new Set((INDUSTRY_PROFILE?.secondary_industry_slugs||[]).filter(x=>x!==slug))];
    if(current&&!secondary.includes(current)&&secondary.length<8)secondary.push(current);
    try{
      const {data,error}=await sb.from('company_industry_profiles').update({primary_industry_slug:slug,secondary_industry_slugs:secondary}).eq('company_id',me.company_id).select('company_id,primary_industry_slug').maybeSingle();
      if(error)throw error;
      if(!data||data.primary_industry_slug!==slug)throw new Error('No company industry profile row was updated. Check manager access and company profile setup.');
      await loadIndustryProfile();renderIndustrySelector();
      buildNav();
    }catch(error){alert('Could not switch industry: '+(error?.message||'Unknown error'));await loadIndustryProfile().catch(()=>{});renderIndustrySelector();buildNav();return}
  }
  cur='industry_workspace';draw();
}

async function sfIndustryHub(){
  if(!INDUSTRIES||!INDUSTRIES.length)await loadIndustryProfile();
  const current=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug;
  let html='<h2>Choose your industry workspace</h2><div class="p"><b>One STEADYFIX CMMS. Different industry setups.</b><div class="note">Choose the type of business you operate. STEADYFIX keeps one secure base application and organises its departments, terminology and day-to-day tools around that industry. Owners and managers can change the company primary workspace.</div></div><div class="dg">';
  (INDUSTRIES||[]).forEach(ind=>{
    const focus=(ind.default_configuration&&ind.default_configuration.focus_areas)||[], examples=ind.business_examples||[], active=ind.slug===current;
    const theme=SF_INDUSTRY_THEMES[ind.slug]||SF_INDUSTRY_THEMES['general-maintenance'];
    html+='<div class="card" data-industry-card="'+esc(ind.slug)+'" style="border-left:6px solid '+theme.ac+';background:linear-gradient(110deg,'+theme.bg+' 0%,var(--pn) 72%)"><div class="ct"><div style="color:'+theme.ac+'">'+esc(ind.name)+'</div><span class="chip" style="background:'+theme.nav+';color:#fff">'+esc(ind.slug.replace(/-/g,' '))+'</span>'+(active?'<span class="chip g">Current workspace</span>':'')+'</div>';
    html+='<div class="note">'+esc(ind.description||'')+'</div>';
    if(examples.length)html+='<div class="rl"><b>Typical businesses:</b> '+esc(examples.slice(0,4).join(' · '))+'</div>';
    if(focus.length)html+='<div class="rl"><b>Day-to-day focus:</b> '+esc(focus.slice(0,5).join(' · '))+'</div>';
    html+='<div class="ca"><button class="b" onclick="chooseIndustryWorkspace(\''+esc(ind.slug)+'\')">'+(active?'Open workspace':'Choose this industry')+'</button></div></div>';
  });
  return html+'</div>';
}

const SF_CONFIGURABLE_MODULES=new Set(['work_orders','assets','service_contracts','stock_items','purchase_orders','customers','inv','suppliers','pm_schedules','chk','fleet','rep','ohs','damage_reports','shutdowns','logistics_ops']);
function sfIndustryModuleOverrides(){const o=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.configuration_overrides||{};return{disabled:new Set(Array.isArray(o.disabled_modules)?o.disabled_modules:[]),labels:o.module_labels&&typeof o.module_labels==='object'?o.module_labels:{}}}
function sfIndustryModules(slug){
  const all={
    automation:[['🧰','Service job cards','Create service calls, assign technicians, record labour, progress, faults and parts used','work_orders'],['🖨️','Customer equipment','Register copiers and devices, serial numbers and page meter readings','assets'],['📑','Service contracts','Manage covered devices, service levels, meter allowances and contract dates','service_contracts'],['📦','Stock & consumables','Track toner, drums, staples, spares and reorder levels','stock_items'],['🛒','Parts purchasing','Create supplier purchase orders','purchase_orders'],['👥','Customers','Manage customer accounts and service contacts','customers'],['💳','Quotes & invoicing','Prepare quotes, invoices and customer billing','inv'],['🤝','Suppliers','Manage parts suppliers and service partners','suppliers'],['🔁','Preventive maintenance','Schedule recurring device servicing','pm_schedules'],['☑️','Service checklists','Use repeatable callout, installation and service checklists','chk']],
    'fleet-management':[['🚚','Fleet & tracking','Vehicles, GPS positions, utilisation and alerts','fleet'],['🧰','Maintenance work','Create and assign vehicle maintenance work','work_orders'],['🔁','Service schedules','Plan recurring vehicle maintenance','pm_schedules'],['📦','Parts & stock','Manage workshop parts and consumables','stock_items'],['🛒','Purchasing','Order parts and supplies','purchase_orders'],['☑️','Inspections','Vehicle and fleet checklists','chk'],['📊','Reports','Fleet and maintenance reporting','rep']],
    workshops:[['🔧','Workshop & job cards','Workshop bookings, vehicle job cards and repair progress','fleet'],['🧰','Work orders','Assign maintenance and repair tasks','work_orders'],['📦','Workshop stock','Parts and materials','stock_items'],['🛒','Parts purchasing','Supplier orders','purchase_orders'],['👥','Customers','Customer records','customers'],['💳','Quotes & invoicing','Customer billing','inv'],['☑️','Quality checklists','Inspection and sign-off lists','chk']],
    'logistics-transport':[['📦','Parcel operations','Create waybills, track consignments, record depot scans and capture proof of delivery','logistics_ops'],['🚛','Fleet & GPS tracking','Vehicle locations, movement and alerts','fleet'],['🧰','Depot maintenance','Work orders for vehicles, depots and equipment','work_orders'],['🔁','Maintenance schedules','Planned maintenance','pm_schedules'],['📦','Stock & supplies','Depot stock and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['☑️','Inspections','Vehicle and facility checks','chk'],['📊','Reports','Operations and maintenance reporting','rep']],
    'hospitality-tourism':[['🏨','Property assets','Rooms, plant, equipment and facilities','assets'],['🛠️','Maintenance requests','Guest and staff maintenance tasks','work_orders'],['🔁','Preventive maintenance','Recurring room, plant and facility tasks','pm_schedules'],['☑️','Operating checklists','Daily, weekly and monthly checks','chk'],['📦','Stores & stock','Maintenance stock and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['🦺','Safety & fire','Inspections, incidents and fire equipment','ohs']],
    'food-beverage':[['🍽️','Venue equipment','Kitchen, refrigeration and dining equipment','assets'],['🛠️','Maintenance tasks','Repairs and breakdowns','work_orders'],['🔁','Planned servicing','Recurring equipment maintenance','pm_schedules'],['☑️','Hygiene & operating checks','Repeatable operating and maintenance checklists','chk'],['📦','Stock & supplies','Maintenance consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['🦺','Safety','Workplace and fire safety','ohs']],
    'property-management-facilities':[['🏢','Properties & assets','Buildings, blocks, campuses and facility assets','assets'],['🛠️','Service requests','Tenant, occupant and facilities work orders','work_orders'],['🔁','Preventive maintenance','Recurring building and plant maintenance','pm_schedules'],['☑️','Inspections','Property and facilities checklists','chk'],['⚠️','Damage reports','Record damage and corrective actions','damage_reports'],['📦','Stock & supplies','Maintenance stock','stock_items'],['🤝','Suppliers','Contractors and service providers','suppliers']],
    'construction-project-management':[['🏗️','Project work packages','Plan and assign construction tasks, site work and delivery responsibilities','work_orders'],['🏢','Plant, tools & equipment','Register site plant, tools and construction equipment','assets'],['📅','Planned works','Schedule recurring and milestone-related maintenance activities','pm_schedules'],['💰','Project budgets & costs','Review budgets, cost lines and recorded expenses','bud'],['🛒','Materials procurement','Order construction materials and supplier services','purchase_orders'],['📦','Materials & stock','Track consumables, spares and site stock','stock_items'],['🤝','Contractors & suppliers','Manage subcontractors, trades and suppliers','suppliers'],['🦺','Site safety','Manage site safety inspections and incidents','ohs'],['☑️','Quality & site inspections','Run site checklists and quality inspections','chk'],['⚠️','Site issues & damage','Record site damage, defects and corrective actions','damage_reports']],
    'manufacturing-industrial':[['🏭','Plant & equipment','Production assets and utilities','assets'],['🛠️','Maintenance work','Breakdown and planned maintenance tasks','work_orders'],['🔁','Preventive maintenance','Recurring plant servicing','pm_schedules'],['📦','Parts & stock','Spare parts and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['⏸️','Shutdowns','Planned shutdown records','shutdowns'],['🦺','Safety','Inspections and incidents','ohs']],
    'general-maintenance':[['🛠️','Work orders','General maintenance and service tasks','work_orders'],['🏢','Assets','Equipment and facilities register','assets'],['🔁','Preventive maintenance','Recurring maintenance schedules','pm_schedules'],['📦','Stock','Parts and consumables','stock_items'],['🛒','Purchasing','Supplier orders','purchase_orders'],['☑️','Checklists','Repeatable inspections and checks','chk'],['🤝','Suppliers','Suppliers and contractors','suppliers']]
  };
  return all[slug]||all['general-maintenance'];
}

async function sfAddIndustryStarterChecklists(){
  const slug=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug;
  const packs={
    'food-beverage':[
      ['Kitchen equipment opening checks','daily',['Confirm refrigeration and freezer units are running and free from visible damage','Check cooking equipment, extraction and ventilation for visible faults','Check dishwashing and sanitation equipment is operational','Check floors, drains and work areas are clean and unobstructed','Record defects and raise a maintenance work order','Confirm urgent equipment faults have been escalated']],
      ['Food venue weekly maintenance walk-through','weekly',['Inspect refrigeration door seals, hinges and condensate drains','Inspect cooking equipment, controls and safety guards','Inspect extraction filters and ventilation access','Inspect taps, sinks, drains and hot-water equipment','Inspect cold-room doors, lighting and floor condition','Review open maintenance tasks and overdue servicing']]
    ],
    'manufacturing-industrial':[
      ['Production shift-start equipment checks','daily',['Inspect machine guards, interlocks and emergency stops before operation','Check for abnormal noise, vibration, leaks or visible damage','Confirm critical utilities and services are available','Check lubrication points and levels against the equipment instructions','Record defects and isolate unsafe equipment under site procedures','Raise or update a maintenance work order for every defect']],
      ['Plant weekly preventive maintenance walk-through','weekly',['Inspect motors, pumps, belts and couplings for visible wear','Inspect electrical enclosures for visible damage; do not open live equipment','Check compressed air, water and other utility lines for leaks','Inspect safety guards, access routes and emergency stop labels','Review breakdowns, repeat faults and outstanding corrective work','Confirm planned maintenance and shutdown tasks have owners and dates']],
      ['Planned shutdown readiness review','weekly',['Confirm shutdown scope and affected production areas','Confirm required permits, isolations and lockout procedures are planned','Confirm maintenance personnel and specialist contractors are assigned','Confirm critical spares, tools and lifting equipment are available','Confirm restart checks and responsible sign-off roles are defined']]
    ],
    'construction-project-management':[
      ['Construction site daily opening and access readiness','daily',['Confirm the active work areas and site access routes for the shift','Check that site access controls and visitor sign-in arrangements are operating','Review planned deliveries, lifting activities and work-area interfaces','Check welfare facilities, temporary lighting and housekeeping','Confirm work teams know the current site instructions and escalation contacts','Record site issues and assign corrective work to a responsible person']],
      ['Construction plant, tools and temporary facilities walk-through','weekly',['Inspect visible condition of site plant and mobile equipment','Check that tools and equipment are stored securely and defects are reported','Review inspection and service due dates recorded for site equipment','Check temporary power leads and distribution equipment for visible damage; do not open live equipment','Inspect access routes, storage areas, barriers and temporary facilities','Record defects and raise work orders for repair or removal from use']],
      ['Construction work package quality and completion review','other',['Confirm the work package scope and latest approved drawings or instructions are available','Check completed work against the stated acceptance criteria and record evidence references','List incomplete items, defects and responsible corrective-action owners','Record materials or supplier issues affecting completion','Confirm required client, consultant or supervisor inspections are recorded before concealment or handover','Record completion status and outstanding handover documents']]
    ]
  };
  const pack=packs[slug];
  if(!pack)return alert('There are no industry starter checklists for this workspace yet.');
  const button=document.getElementById('sfIndustryChecklistBtn');if(button)button.disabled=true;
  try{
    const existingResult=await sb.from('checklist_templates').select('name').eq('site_id',site);
    if(existingResult.error)throw existingResult.error;
    const existing=new Set((existingResult.data||[]).map(x=>x.name));
    const additions=pack.filter(([name])=>!existing.has(name)).map(([name,frequency,items])=>({company_id:me.company_id,site_id:site,name,frequency,items}));
    if(!additions.length){alert('These industry starter checklists are already set up for this site. Open Checklists to use or edit them.');return;}
    const result=await sb.from('checklist_templates').insert(additions);
    if(result.error)throw result.error;
    alert(additions.length+' industry-specific checklist(s) added. Open Checklists to complete, edit and sign them off.');
  }catch(error){alert('Could not add the industry checklists: '+(error?.message||'Unknown error'));}
  finally{if(button)button.disabled=false;}
}

async function sfIndustryWorkspace(){
  if(!INDUSTRIES||!INDUSTRIES.length)await loadIndustryProfile();
  const slug=INDUSTRY_PROFILE&&INDUSTRY_PROFILE.primary_industry_slug||'hospitality-tourism';
  const ind=(INDUSTRIES||[]).find(x=>x.slug===slug);if(!ind)return sfIndustryHub();
  let html='<div class="bar2 noprint"><button onclick="openIndustryHub()">← All industries</button><button onclick="goTab(\'dash\')">Main dashboard</button></div>';
  const theme=SF_INDUSTRY_THEMES[slug]||SF_INDUSTRY_THEMES['general-maintenance'];
  html+='<h2 style="color:'+theme.ac+'">'+esc(ind.name)+' workspace</h2><div class="p" style="border-top:4px solid '+theme.ac+';background:linear-gradient(110deg,'+theme.bg+' 0%,var(--pn) 75%)"><b>'+esc(ind.description||'')+'</b><div class="note">This workspace uses the selected industry identity and its relevant operating shortcuts. Shared CMMS records, permissions and billing remain in the core application; only the industry-specific workflows listed below are presented as specialist operations.</div>';
  const config=Object.assign({},ind.default_configuration||{},INDUSTRY_PROFILE?.configuration_overrides||{});
  const focus=Array.isArray(config.focus_areas)?config.focus_areas:[];
  const examples=Array.isArray(ind.business_examples)?ind.business_examples:[];
  const terminology=config.terminology&&typeof config.terminology==='object'?config.terminology:{};
  if(focus.length)html+='<div class="rl"><b>Industry operating scope:</b> '+esc(focus.join(' · '))+'</div>';
  if(examples.length)html+='<div class="rl"><b>Business types:</b> '+esc(examples.join(' · '))+'</div>';
  const terms=Object.entries(terminology);
  if(terms.length)html+='<div class="rl"><b>Industry terminology:</b> '+terms.map(([key,value])=>'<span>'+esc(key.replace(/_/g,' '))+': '+esc(value)+'</span>').join(' · ')+'</div>';
  html+='</div><div class="dg">';
  const overrides=sfIndustryModuleOverrides();
  sfIndustryModules(slug).filter(m=>!overrides.disabled.has(m[3])).forEach(m=>{const label=overrides.labels[m[3]]||m[1];html+='<div class="card" style="border-left-color:'+theme.ac+'"><div class="ct"><div style="color:'+theme.ac+'">'+m[0]+' '+esc(label)+'</div></div><div class="note">'+esc(m[2])+'</div><div class="ca"><button class="b" style="background:'+theme.ac+';border-color:'+theme.ac+'" onclick="goTab(\''+m[3]+'\')">Open</button></div></div>'});
  if(!sfIndustryModules(slug).some(m=>!overrides.disabled.has(m[3])))html+='<div class="p">All workspace shortcuts are currently hidden. A company manager can restore them in Industry profile.</div>';
  html+='</div>';
  if(['food-beverage','manufacturing-industrial','construction-project-management'].includes(slug))html+='<div class="p"><b>Industry starter checklists</b><div class="note">'+(slug==='food-beverage'?'Kitchen equipment opening checks and a weekly food-venue maintenance walk-through.':slug==='manufacturing-industrial'?'Production shift-start checks, plant preventive maintenance and shutdown readiness.':'Daily site opening and access readiness, weekly plant and tools walk-through, and work package quality and completion review.')+' These editable operational checklists support site routines; they do not replace approved project procedures, competent inspections or statutory requirements.</div><div class="ca"><button class="b" id="sfIndustryChecklistBtn" onclick="sfAddIndustryStarterChecklists()">Add starter checklists</button><button onclick="goTab(\'chk\')">Open Checklists</button></div></div>';
  if(slug==='workshops')html+='<div class="p"><b>Workshop job-card checklists</b><div class="note">Add a vehicle intake and condition assessment for vehicles arriving at the workshop, plus a repair quality-control and customer handover checklist. Templates are added only when a manager opts in; complete a fresh checklist for each relevant job.</div><div class="ca"><button class="b" id="sfWorkshopChecklistBtn" onclick="seedWorkshop()">Add workshop checklists</button><button onclick="goTab(\'fleet\')">Open job cards</button><button onclick="goTab(\'chk\')">Open Checklists</button></div></div>';
  if(slug==='fleet-management')html+='<div class="p"><b>Fleet inspection checklists</b><div class="note">Add a daily vehicle pre-trip inspection, weekly vehicle walk-round and weekly workshop safety check. Templates are site-scoped and can be edited after setup.</div><div class="ca"><button class="b" id="sfFleetChecklistBtn" onclick="seedFleet()">Add fleet checklists</button><button onclick="goTab(\'fleet\')">Open fleet & tracking</button><button onclick="goTab(\'chk\')">Open Checklists</button></div></div>';
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

async function sfResetIndustryCustomizations(){if(!isMgr()||!confirm('Restore the default industry workspace shortcuts and labels?'))return;const{error}=await sb.from('company_industry_profiles').update({configuration_overrides:{}}).eq('company_id',me.company_id);if(error)return alert('Could not reset customizations: '+error.message);await loadIndustryProfile();await draw()}

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
async function sfPrintServiceJobCard(id){
  const r=(LAST&&LAST.rows||[]).find(x=>x.id===id);if(!r)return;
  const signed=await sb.from('work_order_customer_signoffs').select('*').eq('work_order_id',id).eq('site_id',site).order('signed_at',{ascending:false}).limit(1);SF_JOB_SIGNOFFS=signed.data||[];const latestSignoff=SF_JOB_SIGNOFFS[0];
  const find=(t,k)=>((LAST&&LAST.refs&&LAST.refs[t])||[]).find(x=>x.id===k);
  const customer=find('customers',r.customer_id),asset=find('assets',r.asset_id),tech=find('profiles',r.assigned_to);
  let sh=$('sheet');if(!sh){sh=document.createElement('div');sh.id='sheet';document.body.appendChild(sh)}
  const row=(l,v)=>'<tr><th style="width:32%">'+l+'</th><td>'+esc(v==null||v===''?'-':String(v))+'</td></tr>';
  const parts=Array.isArray(r.lines)?r.lines.map(x=>'<tr><td>'+esc(x.d||'')+'</td><td>'+esc(x.q||0)+'</td><td>'+R(x.p||0)+'</td><td>'+R((+x.q||0)*(+x.p||0))+'</td></tr>').join(''):'';
  sh.innerHTML='<h2>'+esc(CS.label||CO)+' · Automation service job card</h2><p><b>Job card '+esc(r.job_number||'')+'</b> · '+esc(r.title||'')+'</p><table class="pt">'+row('Customer',customer&&customer.name)+row('Equipment',asset&&asset.name)+row('Assigned technician',(tech&&tech.full_name)||r.assigned_name)+row('Service type',r.service_type)+row('Priority',r.priority)+row('Progress',r.status)+row('Due date',r.due_date)+row('Meter reading',r.meter_reading)+row('Labour hours',r.labour_hours)+row('Customer approval',r.customer_approval_status)+'</table><p><b>Problem reported</b></p><div class="box">'+esc(r.reported_problem||'')+'</div><p><b>Diagnosis</b></p><div class="box">'+esc(r.diagnosis||'')+'</div><p><b>Work performed</b></p><div class="box">'+esc(r.work_performed||'')+'</div><p><b>Parts and consumables used</b></p><table class="pt"><tr><th>Item</th><th>Qty</th><th>Unit cost</th><th>Total</th></tr>'+(parts||'<tr><td colspan="4">No parts recorded</td></tr>')+'</table><p style="margin-top:28px"><b>Customer sign-off</b></p>'+(latestSignoff?'<p>Approved by: '+esc(latestSignoff.signer_name)+' · '+esc(new Date(latestSignoff.signed_at).toLocaleString('en-ZA'))+'</p>'+sfSignatureSvg(latestSignoff.signature_points)+'<p>'+esc(latestSignoff.notes||'')+'</p>':'<p>Customer signature: _______________________ Date: __________</p>')+'<p>Technician signature: _____________________ Date: __________</p>';
  document.body.classList.add('one');setTimeout(()=>window.print(),120);
}



// ---------- Job card labour and controlled stock issue ----------
async function sfOpenJobOperations(id){
  SF_JOB_OPERATIONS_ID=id;cur='job_operations';draw();
}
let SF_JOB_OPERATIONS_ID=null;
let SF_JOB_SIGNOFFS=[];
let SF_SIGNATURE_STROKES=[];
async function sfJobOperations(){
  const id=SF_JOB_OPERATIONS_ID;if(!id)return '<h2>Job operations</h2><div class="p">Choose a service job card first.</div>';
  const [wr,tm,mi,st,lv,ps,sg]=await Promise.all([
    sb.from('work_orders').select('*').eq('id',id).eq('company_id',me.company_id).eq('site_id',site).maybeSingle(),
    sb.from('work_order_time_entries').select('*').eq('work_order_id',id).eq('site_id',site).order('work_date',{ascending:false}).order('created_at',{ascending:false}),
    sb.from('work_order_material_issues').select('*').eq('work_order_id',id).eq('site_id',site).order('issued_at',{ascending:false}),
    sb.from('stock_items').select('id,name,sku,unit,unit_cost').eq('company_id',me.company_id).order('name'),
    sb.from('stock_levels').select('item_id,on_hand').eq('company_id',me.company_id).eq('site_id',site),
    sb.from('profiles').select('id,full_name,role').eq('company_id',me.company_id).eq('active',true).order('full_name'),
    sb.from('work_order_customer_signoffs').select('*').eq('work_order_id',id).eq('site_id',site).order('signed_at',{ascending:false})
  ]);
  if(wr.error)throw wr.error;if(!wr.data)return '<h2>Job operations</h2><div class="p">This job card is not available at the selected site.</div>';
  for(const x of [tm,mi,st,lv,ps,sg])if(x.error)throw x.error;
  const w=wr.data,items=st.data||[],levels=Object.fromEntries((lv.data||[]).map(x=>[x.item_id,+x.on_hand||0]));
  const staff=(ps.data||[]).filter(p=>isMgr()||p.id===me.id);
  const chosen=staff.some(p=>p.id===w.assigned_to)?w.assigned_to:me.id;
  const timeRows=tm.data||[],materialRows=mi.data||[];SF_JOB_SIGNOFFS=sg.data||[];SF_SIGNATURE_STROKES=[];
  const timeTotal=timeRows.reduce((a,x)=>a+(+x.hours||0),0),labourCost=timeRows.reduce((a,x)=>a+(+x.hours||0)*(+x.hourly_rate||0),0);
  const timeHtml=timeRows.map(x=>'<div class="rl"><b>'+esc((ps.data||[]).find(p=>p.id===x.technician_id)?.full_name||'Technician')+'</b> · '+esc(x.work_date)+' · '+esc(x.hours)+' h'+(x.hourly_rate?' · '+R((+x.hours||0)*(+x.hourly_rate||0)):'')+(x.notes?'<div class="note">'+esc(x.notes)+'</div>':'')+'</div>').join('')||'<div class="note">No labour entries recorded yet.</div>';
  const matHtml=materialRows.map(x=>'<div class="rl"><b>'+esc(x.item_name||items.find(i=>i.id===x.stock_item_id)?.name||'Stock item')+'</b> · '+esc(x.quantity)+' '+esc(x.unit||'units')+' · '+R(x.total_cost||0)+'<div class="note">'+esc(new Date(x.issued_at).toLocaleString('en-ZA'))+(x.notes?' · '+esc(x.notes):'')+'</div></div>').join('')||'<div class="note">No stock has been issued to this job card yet.</div>';
  const signHtml=SF_JOB_SIGNOFFS.map(x=>'<div class="rl"><b>'+esc(x.signer_name)+'</b> · '+esc(new Date(x.signed_at).toLocaleString('en-ZA'))+(x.notes?'<div class="note">'+esc(x.notes)+'</div>':'')+'</div>').join('')||'<div class="note">No customer sign-off has been captured yet.</div>';
  const staffOptions=staff.map(p=>'<option value="'+p.id+'" '+(p.id===chosen?'selected':'')+'>'+esc(p.full_name)+' · '+esc(p.role)+'</option>').join('');
  const itemOptions=items.map(i=>'<option value="'+i.id+'">'+esc(i.name)+(i.sku?' · '+esc(i.sku):'')+' — '+levels[i.id]+' '+esc(i.unit||'units')+' available</option>').join('');
  return '<div class="bar2 noprint"><button onclick="goTab(\'work_orders\')">← Back to job cards</button><button onclick="sfPrintServiceJobCard(\''+id+'\')">Print job card</button></div>'+
    '<h2>Job operations · '+esc(w.job_number||w.title||'Service job')+'</h2>'+
    '<div class="p"><b>'+esc(w.title||'Service job')+'</b><div class="note">'+esc(w.reported_problem||w.description||'No fault description recorded')+'</div><div class="kv"><span>Status</span><b>'+esc(cap(w.status))+'</b><span>Assigned technician</span><b>'+esc(w.assigned_name||'-')+'</b><span>Customer approval</span><b>'+esc(cap(w.customer_approval_status||'pending'))+'</b><span>Labour logged</span><b>'+timeTotal.toFixed(2)+' hours</b><span>Labour value</span><b>'+R(labourCost)+'</b><span>Parts issued</span><b>'+materialRows.length+' issue entries</b></div></div>'+
    '<div class="dg"><div class="p"><b>Record technician labour</b><div class="note">Record actual time spent against this job card. Technicians can record their own time; managers can record time for the team.</div>'+
    '<label class="el">Technician<select id="sfTimeTech" '+(!isMgr()?'disabled':'')+'>'+staffOptions+'</select></label>'+
    '<label class="el">Work date<input id="sfTimeDate" type="date" value="'+today+'"></label><label class="el">Hours worked<input id="sfTimeHours" type="number" min="0.01" max="24" step="0.25" placeholder="e.g. 1.5"></label>'+
    '<label class="el">Hourly rate (optional)<input id="sfTimeRate" type="number" min="0" step="0.01" value="0"></label><label class="el">Work notes<textarea id="sfTimeNotes" placeholder="What work was completed during this time?"></textarea></label>'+
    '<button class="b" onclick="sfSaveJobTime(\''+id+'\')">Save labour entry</button></div>'+
    '<div class="p"><b>Issue parts and consumables</b><div class="note">Stock is deducted from this site only. The issue is recorded against the job card, with the quantity and cost retained in the audit record.</div>'+
    '<label class="el">Stock item<select id="sfIssueItem">'+itemOptions+'</select></label><label class="el">Quantity<input id="sfIssueQty" type="number" min="0.001" step="0.001" value="1"></label>'+
    '<label class="el">Issue note<input id="sfIssueNotes" placeholder="e.g. Black toner cartridge"></label><button class="b" onclick="sfIssueJobStock(\''+id+'\')">Issue stock to job</button></div></div>'+
    '<div class="dg"><div class="p"><b>Labour history</b><div class="g"><div class="k"><b>'+timeTotal.toFixed(2)+'</b><span>Total hours</span></div><div class="k"><b>'+R(labourCost)+'</b><span>Labour value</span></div></div>'+timeHtml+'</div>'+
    '<div class="p"><b>Parts issued to this job</b>'+matHtml+'</div></div>'+
    '<div class="p"><b>Customer sign-off</b><div class="note">Let the customer sign on this phone or tablet with a finger, stylus or mouse. The signed record is stored against this job card and marks customer approval as approved.</div>'+signHtml+
    '<label class="el">Customer / authorised receiver name<input id="sfSignerName" maxlength="160" placeholder="Full name"></label>'+
    '<canvas id="sfSignaturePad" width="900" height="260" aria-label="Customer signature pad" style="display:block;width:100%;height:150px;background:#fff;border:1px solid #9aa7b2;border-radius:8px;touch-action:none"></canvas>'+
    '<div class="ca noprint"><button onclick="sfClearSignature()">Clear signature</button></div>'+
    '<label class="el"><span><input id="sfSignerConsent" type="checkbox"> I confirm that the customer has approved the work recorded on this job card.</span></label>'+
    '<label class="el">Customer comments<textarea id="sfSignerNotes" placeholder="Optional customer comments or conditions"></textarea></label>'+
    '<button class="b" onclick="sfSaveCustomerSignoff(\''+id+'\')">Save signed customer approval</button></div>';
}
function sfInitSignaturePadFor(canvasId){
  const canvas=$(canvasId);if(!canvas)return;SF_SIGNATURE_STROKES=[];const ctx=canvas.getContext('2d');if(!ctx)return;
  const redraw=()=>{ctx.clearRect(0,0,canvas.width,canvas.height);ctx.strokeStyle='#15232d';ctx.lineWidth=5;ctx.lineCap='round';ctx.lineJoin='round';SF_SIGNATURE_STROKES.forEach(st=>{if(!st.length)return;ctx.beginPath();ctx.moveTo(st[0].x*canvas.width,st[0].y*canvas.height);st.slice(1).forEach(p=>ctx.lineTo(p.x*canvas.width,p.y*canvas.height));ctx.stroke()})};
  canvas.onpointerdown=e=>{e.preventDefault();canvas.setPointerCapture(e.pointerId);const r=canvas.getBoundingClientRect(),p={x:Math.max(0,Math.min(1,(e.clientX-r.left)/r.width)),y:Math.max(0,Math.min(1,(e.clientY-r.top)/r.height))};SF_SIGNATURE_STROKES.push([p]);redraw()};
  canvas.onpointermove=e=>{if(!e.buttons)return;const r=canvas.getBoundingClientRect(),st=SF_SIGNATURE_STROKES[SF_SIGNATURE_STROKES.length-1];if(!st)return;st.push({x:Math.max(0,Math.min(1,(e.clientX-r.left)/r.width)),y:Math.max(0,Math.min(1,(e.clientY-r.top)/r.height))});redraw()};
  canvas.onpointerup=()=>{};canvas.onpointercancel=()=>{};redraw();
}
function sfInitSignaturePad(){sfInitSignaturePadFor('sfSignaturePad')}
function sfInitPODSignaturePad(){sfInitSignaturePadFor('sfPODSignaturePad')}
function sfClearSignature(canvasId){SF_SIGNATURE_STROKES=[];const c=$(canvasId||'sfSignaturePad');if(c){const x=c.getContext('2d');x.clearRect(0,0,c.width,c.height)}}
async function sfSaveCustomerSignoff(id){
  const name=$('sfSignerName').value.trim(),consent=$('sfSignerConsent').checked,strokes=SF_SIGNATURE_STROKES.filter(s=>s.length>1);
  const points=strokes.reduce((a,s)=>a+s.length,0);
  if(!name)return alert('Enter the customer’s full name.');
  if(!consent)return alert('The customer must confirm approval before signing.');
  if(!strokes.length||points<3)return alert('Capture the customer’s signature in the box first.');
  if(strokes.length>12||points>1000)return alert('The signature is too detailed. Clear it and sign again.');
  const {data,error}=await sb.rpc('record_work_order_customer_signoff',{p_work_order_id:id,p_signer_name:name,p_signature_points:strokes,p_notes:$('sfSignerNotes').value.trim()||null,p_customer_consent:true});
  if(error)return alert('Could not save customer sign-off: '+error.message);
  alert('Customer approval saved to the job card.');draw();
}
function sfSignatureSvg(strokes){
  if(!Array.isArray(strokes)||!strokes.length)return '';
  const paths=strokes.map(st=>{if(!Array.isArray(st)||st.length<2)return '';const pts=st.map(p=>{const x=Math.max(0,Math.min(1,Number(p.x)||0))*400,y=Math.max(0,Math.min(1,Number(p.y)||0))*110;return x.toFixed(1)+','+y.toFixed(1)}).join(' ');return '<polyline points="'+pts+'" fill="none" stroke="#15232d" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'}).join('');
  return '<svg viewBox="0 0 400 110" style="width:100%;max-width:400px;height:110px;border:1px solid #aaa">'+paths+'</svg>';
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
async function sfLoadShipmentHistory(id){
  const container=document.getElementById('sfShipmentHistory_'+id);if(!container)return;
  const pageSize=50,offset=Number(container.dataset.offset||0),button=container.previousElementSibling?.querySelector('button');
  if(container.dataset.loading==='true')return;container.dataset.loading='true';if(button)button.disabled=true;
  try{
    const result=await sb.from('logistics_tracking_events').select('*').eq('company_id',me.company_id).eq('site_id',site).eq('shipment_id',id).order('event_at',{ascending:false}).order('id',{ascending:false}).range(offset,offset+pageSize-1);
    if(result.error)throw result.error;
    const rows=result.data||[];
    if(offset===0)container.innerHTML='';
    const html=rows.map(e=>'<div class="rl">'+esc(new Date(e.event_at).toLocaleString('en-ZA'))+' · <b>'+esc(cap(e.status||e.event_type))+'</b>'+(e.location?' · '+esc(e.location):'')+(e.notes?'<div class="note">'+esc(e.notes)+'</div>':'')+'</div>').join('');
    container.insertAdjacentHTML('beforeend',html||(offset===0?'<div class="note">No scans recorded yet.</div>':''));container.dataset.offset=String(offset+rows.length);container.dataset.loaded='true';
    if(button){button.textContent=rows.length===pageSize?'Load more scans':'History loaded';button.disabled=rows.length<pageSize;}
  }catch(error){alert('Could not load tracking history: '+(error.message||error));if(button)button.disabled=false;}
  finally{container.dataset.loading='false';}
}
async function sfLogisticsWorkspace(){
  const shipments=[];const shipmentPageSize=500;let shipmentOffset=0;
  while(true){
    const sr=await sb.from('logistics_shipments').select('*').eq('company_id',me.company_id).eq('site_id',site).order('created_at',{ascending:false}).order('id',{ascending:false}).range(shipmentOffset,shipmentOffset+shipmentPageSize-1);
    if(sr.error)throw sr.error;
    const page=sr.data||[];shipments.push(...page);
    if(page.length<shipmentPageSize)break;
    shipmentOffset+=shipmentPageSize;
  }
  SF_LOGISTICS_SHIPMENTS=shipments;
  const count=s=>SF_LOGISTICS_SHIPMENTS.filter(x=>x.status===s).length;
  const cards=SF_LOGISTICS_SHIPMENTS.map(x=>{
    const opts=SF_SHIPMENT_STATUSES.map(s=>'<option value="'+s+'" '+(s===x.status?'selected':'')+'>'+esc(cap(s))+'</option>').join('');
    return '<div class="card"><div class="ct"><div>'+esc(x.waybill_no)+' · '+esc(x.recipient_name)+'</div><div class="chips">'+chip(x.status,cap(x.status))+'</div></div>'+
      '<div class="kv"><span>Tracking number</span><b>'+esc(x.tracking_no||x.waybill_no)+'</b><span>From</span><b>'+esc(x.origin_address)+'</b><span>To</span><b>'+esc(x.destination_address)+'</b><span>Parcel</span><b>'+esc(x.package_count)+' package(s) · '+esc(x.parcel_description||'-')+'</b><span>Expected delivery</span><b>'+esc(x.expected_delivery||'-')+'</b></div>'+
      (x.status==='delivered'?'<div class="p"><b>Proof of delivery</b><div class="kv"><span>Received by</span><b>'+esc(x.pod_recipient_name||'-')+'</b><span>Delivered at</span><b>'+esc(x.delivered_at?new Date(x.delivered_at).toLocaleString('en-ZA'):'-')+'</b><span>Reference</span><b>'+esc(x.pod_reference||'-')+'</b><span>Notes</span><b>'+esc(x.pod_notes||'-')+'</b></div></div>':'')+
      '<div class="ca noprint"><button onclick="sfPrintWaybill(\''+x.id+'\')">Print waybill</button>'+(['delivered','returned'].includes(x.status)?'':'<button onclick="sfAddShipmentScan(\''+x.id+'\')">Add tracking scan</button><button onclick="sfCapturePOD(\''+x.id+'\')">Proof of delivery</button>')+(isMgr()?'<button class="x2" onclick="sfDeleteShipment(\''+x.id+'\')">Delete</button>':'')+'</div>'+
      '<label class="el noprint">Update shipment status<select onchange="sfUpdateShipmentStatus(\''+x.id+'\',this.value)">'+opts+'</select></label>'+
      '<div class="rl"><b>Tracking history</b> <button class="noprint" onclick="sfLoadShipmentHistory(\''+x.id+'\')">Load tracking history</button></div><div id="sfShipmentHistory_'+x.id+'" data-offset="0" data-loaded="false"><div class="note">Tracking scans load when requested.</div></div>'+
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
function sfCapturePOD(id){SF_POD_SHIPMENT_ID=id;cur='logistics_pod';draw()}
let SF_POD_SHIPMENT_ID=null;
async function sfLogisticsPODPage(){
  const id=SF_POD_SHIPMENT_ID;if(!id)return '<h2>Proof of delivery</h2><div class="p">Choose a consignment first.</div>';
  const [sr,pr]=await Promise.all([
    sb.from('logistics_shipments').select('*').eq('id',id).eq('company_id',me.company_id).eq('site_id',site).maybeSingle(),
    sb.from('logistics_pod_signoffs').select('*').eq('shipment_id',id).eq('site_id',site).maybeSingle()
  ]);
  if(sr.error)throw sr.error;if(pr.error)throw pr.error;if(!sr.data)return '<h2>Proof of delivery</h2><div class="p">This consignment is not available at this site.</div>';
  const x=sr.data,p=pr.data;
  if(x.status==='delivered')return '<div class="bar2 noprint"><button onclick="goTab(\'logistics_ops\')">← Back to consignments</button><button onclick="sfPrintWaybill(\''+id+'\')">Print waybill</button></div><h2>Proof of delivery · '+esc(x.waybill_no)+'</h2><div class="p"><b>Delivered to '+esc(x.pod_recipient_name||'Receiver')+'</b><div class="kv"><span>Delivered at</span><b>'+esc(x.delivered_at?new Date(x.delivered_at).toLocaleString('en-ZA'):'-')+'</b><span>Reference</span><b>'+esc(x.pod_reference||'-')+'</b><span>Notes</span><b>'+esc(x.pod_notes||'-')+'</b></div>'+(p?'<div class="rl"><b>Electronic signature captured</b> · '+esc(p.receiver_name)+' · '+esc(new Date(p.signed_at).toLocaleString('en-ZA'))+'</div>'+sfSignatureSvg(p.signature_points):'<div class="note">This consignment was marked delivered before electronic signature capture was enabled.</div>')+'</div>';
  return '<div class="bar2 noprint"><button onclick="goTab(\'logistics_ops\')">← Back to consignments</button><button onclick="sfPrintWaybill(\''+id+'\')">Print waybill</button></div><h2>Proof of delivery · '+esc(x.waybill_no)+'</h2><div class="p"><b>'+esc(x.recipient_name)+'</b><div class="note">'+esc(x.destination_address)+'</div><label class="el">Name of person receiving parcel<input id="sfPODReceiver" maxlength="160" value="'+esc(x.recipient_name||'')+'"></label><label class="el">Delivery reference (optional)<input id="sfPODReference" maxlength="200" placeholder="Delivery code or signed slip reference"></label><canvas id="sfPODSignaturePad" width="900" height="260" aria-label="Receiver signature pad" style="display:block;width:100%;height:150px;background:#fff;border:1px solid #9aa7b2;border-radius:8px;touch-action:none"></canvas><div class="ca noprint"><button onclick="sfClearSignature(\'sfPODSignaturePad\')">Clear signature</button></div><label class="el"><span><input id="sfPODConsent" type="checkbox"> I confirm I have received this consignment.</span></label><label class="el">Delivery notes<textarea id="sfPODNotes" placeholder="Optional delivery notes"></textarea></label><button class="b" onclick="sfSaveLogisticsPOD(\''+id+'\')">Confirm delivery and save signature</button></div>';
}
async function sfSaveLogisticsPOD(id){
  const name=$('sfPODReceiver').value.trim(),consent=$('sfPODConsent').checked,strokes=SF_SIGNATURE_STROKES.filter(s=>s.length>1),points=strokes.reduce((a,s)=>a+s.length,0);
  if(!name)return alert('Enter the receiver name.');if(!consent)return alert('The receiver must confirm receipt.');if(!strokes.length||points<3)return alert('Capture the receiver signature first.');if(strokes.length>12||points>1000)return alert('Signature is too detailed. Clear it and sign again.');
  const {error}=await sb.rpc('record_logistics_pod_signoff',{p_shipment_id:id,p_receiver_name:name,p_signature_points:strokes,p_reference:$('sfPODReference').value.trim()||null,p_notes:$('sfPODNotes').value.trim()||null,p_receiver_consent:true});
  if(error)return alert('Could not save proof of delivery: '+error.message);alert('Proof of delivery saved.');cur='logistics_ops';draw();
}
async function sfDeleteShipment(id){
  if(!isMgr()||!confirm('Delete this consignment and its tracking history?'))return;
  const {error}=await sb.from('logistics_shipments').delete().eq('id',id).eq('company_id',me.company_id).eq('site_id',site);
  if(error)alert(error.message);else draw();
}
async function sfPrintWaybill(id){
  const x=SF_LOGISTICS_SHIPMENTS.find(s=>s.id===id);if(!x)return;
  const pod=await sb.from('logistics_pod_signoffs').select('*').eq('shipment_id',id).eq('site_id',site).maybeSingle();const signed=pod.data;
  const row=(l,v)=>'<tr><th style="width:32%">'+l+'</th><td>'+esc(v==null||v===''?'-':String(v))+'</td></tr>';
  sheetPrint(ph('Transport waybill')+'<br><table class="pt">'+row('Waybill number',x.waybill_no)+row('Tracking number',x.tracking_no)+row('Service level',cap(x.service_level))+row('Status',cap(x.status))+row('Sender',x.sender_name)+row('Recipient',x.recipient_name)+row('Recipient phone',x.recipient_phone)+row('Origin',x.origin_address)+row('Destination',x.destination_address)+row('Contents',x.parcel_description)+row('Packages',x.package_count)+row('Weight (kg)',x.weight_kg)+row('Expected delivery',x.expected_delivery)+'</table>'+(signed?'<h3>Electronic proof of delivery</h3><p>Received by: '+esc(signed.receiver_name)+' · '+esc(new Date(signed.signed_at).toLocaleString('en-ZA'))+'</p>'+sfSignatureSvg(signed.signature_points)+'<p>'+esc(signed.notes||'')+'</p>':'')+'<p><b>Driver / collection signature</b> ___________________________</p><p><b>Receiver signature / name</b> ___________________________ Date: __________</p>');
}

// Extend the existing navigation without creating a second app or changing shared base records.

const SF_BASE_DRAW=draw;
draw=async function(){
  if(LOCK&&!['sub','sup','set','inbox','act'].includes(cur)){cur='sub';return SF_BASE_DRAW()}
  if(cur==='industry_hub'){V.innerHTML='Loading…';try{V.innerHTML=await sfIndustryHub()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='industry_workspace'){V.innerHTML='Loading…';try{V.innerHTML=await sfIndustryWorkspace()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='service_contracts'){V.innerHTML='Loading…';try{V.innerHTML=await sfServiceContracts()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='job_operations'){V.innerHTML='Loading…';try{V.innerHTML=await sfJobOperations();sfInitSignaturePad()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='logistics_ops'){V.innerHTML='Loading…';try{V.innerHTML=await sfLogisticsWorkspace()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
  if(cur==='logistics_pod'){V.innerHTML='Loading…';try{V.innerHTML=await sfLogisticsPODPage();sfInitPODSignaturePad()}catch(e){V.innerHTML='<p class="bad">'+esc(e.message)+'</p>'}return}
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
