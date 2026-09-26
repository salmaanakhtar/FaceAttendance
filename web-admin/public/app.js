const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const isoDate = (date = new Date()) => `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
const monthRange = (value = isoDate().slice(0,7)) => ({from:`${value}-01`,to:isoDate(new Date(Number(value.slice(0,4)),Number(value.slice(5,7)),0))});
const fmtTime = (value) => value ? new Intl.DateTimeFormat(undefined,{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : '—';
const hours = (minutes) => `${Math.floor(Number(minutes ?? 0)/60)}h ${Math.round(Number(minutes ?? 0)%60)}m`;
const money = (value) => value == null ? '—' : new Intl.NumberFormat('en-ZA',{style:'currency',currency:'ZAR'}).format(value);
const pill = (text, tone='') => `<span class="pill ${tone}">${esc(text)}</span>`;

const state = {
  server: sessionStorage.getItem('fa_server') || 'https://faceattendance-api.salmaan.dev',
  access: sessionStorage.getItem('fa_access'),
  refresh: sessionStorage.getItem('fa_refresh'),
  admin: JSON.parse(sessionStorage.getItem('fa_admin') || 'null'),
  page: 'dashboard',
  cache: {},
};

let toastTimer;
function toast(message, error=false){
  const el=$('#toast'); el.textContent=message; el.className=`toast show${error?' error':''}`;
  clearTimeout(toastTimer); toastTimer=setTimeout(()=>el.className='toast',3500);
}
function setLoading(value){ $('#loading').hidden=!value; }
function apiError(data,status){ return data?.error?.message || data?.message || `Request failed (${status})`; }

async function refreshAccess(){
  if(!state.refresh) return false;
  const response=await fetch(`${state.server}/api/v1/admin/refresh`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({refreshToken:state.refresh})});
  if(!response.ok) return false;
  const data=await response.json(); state.access=data.accessToken; sessionStorage.setItem('fa_access',state.access); return true;
}
async function api(path,{method='GET',body,download=false,retry=true}={}){
  const headers={Authorization:`Bearer ${state.access}`};
  if(body!==undefined) headers['Content-Type']='application/json';
  const response=await fetch(`${state.server}${path}`,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});
  if(response.status===401 && retry && await refreshAccess()) return api(path,{method,body,download,retry:false});
  if(!response.ok){ let data; try{data=await response.json()}catch{} throw new Error(apiError(data,response.status)); }
  if(download) return response.blob();
  if(response.status===204) return null;
  return response.json();
}

function saveSession(data){
  state.access=data.accessToken; state.refresh=data.refreshToken; state.admin=data.admin;
  sessionStorage.setItem('fa_server',state.server); sessionStorage.setItem('fa_access',state.access);
  sessionStorage.setItem('fa_refresh',state.refresh); sessionStorage.setItem('fa_admin',JSON.stringify(state.admin));
}
function clearSession(){
  state.access=null; state.refresh=null; state.admin=null;
  ['fa_access','fa_refresh','fa_admin'].forEach(k=>sessionStorage.removeItem(k));
}
function showLogin(){ $('#app-view').hidden=true; $('#login-view').hidden=false; $('#server-url').value=state.server; }
function showApp(){
  $('#login-view').hidden=true; $('#app-view').hidden=false; $('#admin-name').textContent=state.admin?.name||'Administrator'; renderPage();
}

$('#login-form').addEventListener('submit',async(event)=>{
  event.preventDefault(); const form=new FormData(event.currentTarget); const button=$('button[type=submit]',event.currentTarget);
  const error=$('#login-error'); error.hidden=true; button.disabled=true; button.textContent='Signing in…';
  state.server=String(form.get('server')).replace(/\/+$/,'');
  try{
    const response=await fetch(`${state.server}/api/v1/admin/login`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:form.get('username'),password:form.get('password')})});
    const data=await response.json(); if(!response.ok) throw new Error(apiError(data,response.status)); saveSession(data); showApp();
  }catch(err){ error.textContent=err.message; error.hidden=false; }
  finally{button.disabled=false; button.textContent='Sign in';}
});
$('#logout').addEventListener('click',async()=>{ try{if(state.refresh) await fetch(`${state.server}/api/v1/admin/logout`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({refreshToken:state.refresh})});}catch{} clearSession(); showLogin(); });
$('#nav').addEventListener('click',(event)=>{const button=event.target.closest('[data-page]');if(!button)return;state.page=button.dataset.page;$$('[data-page]').forEach(b=>b.classList.toggle('active',b===button));renderPage();});
$('#refresh').addEventListener('click',()=>renderPage());
$('#modal-close').addEventListener('click',()=>$('#modal').close());

const titles={dashboard:'Overview',employees:'Workers',attendance:'Attendance',leave:'Leave',payroll:'Payroll',audit:'Audit log'};
async function renderPage(){
  $('#page-title').textContent=titles[state.page]; setLoading(true);
  try{ await ({dashboard:renderDashboard,employees:renderEmployees,attendance:renderAttendance,leave:renderLeave,payroll:renderPayroll,audit:renderAudit}[state.page])(); }
  catch(err){ $('#page').innerHTML=`<div class="card empty"><p class="negative">${esc(err.message)}</p><button class="secondary" id="retry">Try again</button></div>`; $('#retry').onclick=renderPage; }
  finally{setLoading(false);}
}
function modal(title,html){$('#modal-title').textContent=title;$('#modal-body').innerHTML=html;$('#modal').showModal();}

async function renderDashboard(){
  const nowDate=new Date(); const today=isoDate(nowDate);
  const weekDate=new Date(nowDate); weekDate.setDate(nowDate.getDate()-((nowDate.getDay()+6)%7));
  const weekStart=isoDate(weekDate); const monthStart=`${today.slice(0,7)}-01`;
  const [now,stats,employees,dayAttendance,weekAttendance,monthAttendance]=await Promise.all([
    api('/api/v1/admin/attendance/now'),api(`/api/v1/admin/attendance/stats?from=${today}&to=${today}`),
    api('/api/v1/admin/employees?status=active&limit=200&offset=0'),
    api(`/api/v1/admin/attendance?from=${today}&to=${today}&limit=500`),
    api(`/api/v1/admin/attendance?from=${weekStart}&to=${today}&limit=500`),
    api(`/api/v1/admin/attendance?from=${monthStart}&to=${today}&limit=500`)
  ]);
  state.cache.employees=employees.employees||[]; const agg=stats.aggregate||{}; const current=now.currentlyIn||[];
  const daySessions=dayAttendance.sessions||[]; const weekSessions=weekAttendance.sessions||[]; const monthSessions=monthAttendance.sessions||[];
  const total=(id,rows)=>rows.filter(s=>s.employeeId===id).reduce((sum,s)=>sum+Number(s.workedMinutes||0),0);
  $('#page').innerHTML=`
    <div class="stats"><div class="stat"><span>Workers currently in</span><strong class="positive">${current.length}</strong></div><div class="stat"><span>Today's sessions</span><strong>${agg.sessions??daySessions.length}</strong></div><div class="stat"><span>Late today</span><strong class="warning">${agg.lateCount??0}</strong></div><div class="stat"><span>Incomplete</span><strong class="negative">${agg.incompleteCount??0}</strong></div></div>
    <section class="card"><div class="card-head"><div><h3>Worker hours</h3><p class="muted">Hours worked today, from Monday to today, and this calendar month.</p></div>${pill(`${state.cache.employees.length} active workers`)}</div><div class="table-wrap"><table><thead><tr><th>Worker</th><th>Status</th><th>Today</th><th>This week</th><th>This month</th><th></th></tr></thead><tbody>${state.cache.employees.map(worker=>{const open=current.find(s=>s.employeeId===worker.id);return `<tr><td><strong>${esc(worker.name)}</strong><br><span class="muted">#${esc(worker.employeeCode)}</span></td><td>${pill(open?'Clocked in':'Clocked out',open?'green':'')}</td><td><strong>${esc(hours(total(worker.id,daySessions)))}</strong></td><td><strong>${esc(hours(total(worker.id,weekSessions)))}</strong></td><td><strong>${esc(hours(total(worker.id,monthSessions)))}</strong></td><td><button class="link-button manage-worker" data-id="${esc(worker.id)}">Manage</button></td></tr>`}).join('')}</tbody></table></div></section>
    <div class="two-col"><section class="card"><div class="card-head"><h3>In right now</h3>${pill(`${current.length} workers`,'green')}</div>${current.length?`<div class="table-wrap"><table><thead><tr><th>Worker</th><th>Code</th><th>Clocked in</th></tr></thead><tbody>${current.map(s=>`<tr><td>${esc(s.employeeName)}</td><td>${esc(s.employeeCode)}</td><td>${esc(fmtTime(s.checkInAt))}</td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No workers are currently clocked in.</div>'}</section>
    <section class="card"><div class="card-head"><h3>Today</h3>${pill(`${daySessions.length} sessions`)}</div>${daySessions.length?`<div class="table-wrap"><table><thead><tr><th>Worker</th><th>In</th><th>Out</th><th>Hours</th><th></th></tr></thead><tbody>${daySessions.slice(0,12).map(s=>`<tr><td>${esc(s.employeeName)}</td><td>${esc(fmtTime(s.checkInAt))}</td><td>${esc(fmtTime(s.checkOutAt))}</td><td>${esc(hours(s.workedMinutes))}</td><td><button class="link-button edit-today-session" data-id="${esc(s.id)}">Edit times</button></td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No attendance recorded today.</div>'}</section></div>`;
  $$('.manage-worker').forEach(button=>button.onclick=()=>openWorkerActions(state.cache.employees.find(w=>w.id===button.dataset.id),current.find(s=>s.employeeId===button.dataset.id),weekSessions,monthSessions));
  $$('.edit-today-session').forEach(button=>button.onclick=()=>openSession(daySessions.find(s=>s.id===button.dataset.id),renderDashboard));
}

function openWorkerActions(worker,openSession,weekSessions,monthSessions){
  const recent=monthSessions.filter(s=>s.employeeId===worker.id).sort((a,b)=>b.workDate.localeCompare(a.workDate)).slice(0,8);
  modal(worker.name,`<div class="detail-grid"><div><span>Status</span><strong class="${openSession?'positive':''}">${openSession?'Clocked in':'Clocked out'}</strong></div><div><span>This week</span><strong>${esc(hours(weekSessions.filter(s=>s.employeeId===worker.id).reduce((n,s)=>n+Number(s.workedMinutes||0),0)))}</strong></div><div><span>This month</span><strong>${esc(hours(monthSessions.filter(s=>s.employeeId===worker.id).reduce((n,s)=>n+Number(s.workedMinutes||0),0)))}</strong></div></div><div class="modal-actions"><button id="worker-clock" class="primary">${openSession?'Clock out':'New clock in'}</button><button id="worker-edit" class="secondary">Edit worker</button></div><h3 class="section-title">Recent shifts</h3>${recent.length?`<div class="table-wrap"><table><thead><tr><th>Date</th><th>In</th><th>Out</th><th>Hours</th><th></th></tr></thead><tbody>${recent.map(s=>`<tr><td>${esc(s.workDate)}</td><td>${esc(fmtTime(s.checkInAt))}</td><td>${esc(fmtTime(s.checkOutAt))}</td><td>${esc(hours(s.workedMinutes))}</td><td><button class="link-button edit-recent-session" data-id="${esc(s.id)}">Edit times</button></td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No shifts this month.</div>'}`);
  $('#worker-edit').onclick=()=>{ $('#modal').close(); openWorker(worker); };
  $('#worker-clock').onclick=async()=>{try{if(openSession){await api('/api/v1/admin/corrections',{method:'POST',body:{employeeId:worker.id,sessionId:openSession.id,field:'check_out',value:new Date().toISOString(),reason:'Administrator clock out from web dashboard'}});}else{await api('/api/v1/admin/corrections/manual-session',{method:'POST',body:{employeeId:worker.id,checkInAt:new Date().toISOString(),reason:'Administrator clock in from web dashboard'}});}$('#modal').close();toast(openSession?'Worker clocked out.':'Worker clocked in.');renderDashboard();}catch(err){toast(err.message,true)}};
  $$('.edit-recent-session').forEach(button=>button.onclick=()=>{const session=recent.find(s=>s.id===button.dataset.id);$('#modal').close();openSession(session,renderDashboard);});
}

async function getEmployees(){const data=await api('/api/v1/admin/employees?status=all&limit=200&offset=0');state.cache.employees=data.employees||[];return state.cache.employees;}
async function renderEmployees(){
  const workers=await getEmployees();
  $('#page').innerHTML=`<div class="toolbar"><div class="filters"><input id="worker-search" placeholder="Search workers"></div><button id="add-worker" class="primary">Add worker</button></div><div id="worker-table"></div>`;
  const draw=()=>{const q=$('#worker-search').value.toLowerCase();const visible=workers.filter(w=>`${w.name} ${w.employeeCode} ${w.schedule?.department||''}`.toLowerCase().includes(q));$('#worker-table').innerHTML=visible.length?`<div class="table-wrap"><table><thead><tr><th>Worker</th><th>Code</th><th>Department</th><th>Hourly rate</th><th>Status</th><th></th></tr></thead><tbody>${visible.map(w=>`<tr><td><strong>${esc(w.name)}</strong><br><span class="muted">${esc(w.email||'')}</span></td><td>${esc(w.employeeCode)}</td><td>${esc(w.schedule?.department||'—')}</td><td class="money">${money(w.schedule?.hourlyRate??30.23)}</td><td>${pill(w.status,w.status==='active'?'green':'')}</td><td><button class="link-button edit-worker" data-id="${esc(w.id)}">Edit</button></td></tr>`).join('')}</tbody></table></div>`:'<div class="card empty">No matching workers.</div>';$$('.edit-worker').forEach(b=>b.onclick=()=>openWorker(workers.find(w=>w.id===b.dataset.id)));};
  $('#worker-search').addEventListener('input',draw);$('#add-worker').onclick=()=>openWorker(null);draw();
}
function openWorker(worker){
  const s=worker?.schedule||{}; const days=new Set(s.workDays||['mon','tue','wed','thu','fri']); const dayLabels={mon:'Mon',tue:'Tue',wed:'Wed',thu:'Thu',fri:'Fri',sat:'Sat',sun:'Sun'};
  modal(worker?'Edit worker':'Add worker',`<form id="worker-form" class="form-grid"><label>Full name<input name="name" required value="${esc(worker?.name||'')}"></label><label>Worker code<input name="code" inputmode="numeric" pattern="[0-9]+" ${worker?'disabled':''} required value="${esc(worker?.employeeCode||'')}"></label><label>Email<input name="email" type="email" value="${esc(worker?.email||'')}"></label><label>Department<input name="department" required value="${esc(s.department||'')}"></label><label>Weekly hours<input name="hours" type="number" min="0" max="168" step="0.25" required value="${esc(s.hoursPerWeek??40)}"></label><label>Normal hourly rate (R)<input name="rate" type="number" min="0" step="0.01" required value="${esc(s.hourlyRate??30.23)}"></label><label>First name<input name="firstName" value="${esc(s.firstName||'')}"></label><label>Surname<input name="surname" value="${esc(s.surname||'')}"></label><label>ID number<input name="identityNumber" inputmode="numeric" value="${esc(s.identityNumber||'')}"></label><label>Occupation<input name="occupation" value="${esc(s.occupation||'')}"></label><label>Start date<input name="startDate" type="date" value="${esc(s.startDate||'')}"></label><label>Payment method<input name="paymentMethod" value="${esc(s.paymentMethod||'')}"></label><label class="wide">Employer address<textarea name="employerAddress" rows="2">${esc(s.employerAddress||'')}</textarea></label><fieldset class="wide"><legend>Scheduled workdays</legend><div class="check-row">${Object.entries(dayLabels).map(([key,label])=>`<label><input type="checkbox" name="days" value="${key}" ${days.has(key)?'checked':''}>${label}</label>`).join('')}</div></fieldset><p id="worker-error" class="form-error wide" hidden></p>${worker?`<div class="wide worker-danger"><button type="button" class="secondary" id="deactivate-worker" ${worker.status!=='active'?'disabled':''}>Deactivate worker</button><button type="button" class="danger" id="delete-worker">Delete worker</button></div>`:''}<div class="modal-actions wide"><button type="button" class="secondary" id="cancel-worker">Cancel</button><button type="submit" class="primary">Save worker</button></div></form>`);
  $('#cancel-worker').onclick=()=>$('#modal').close();
  $('#worker-form').onsubmit=async(event)=>{event.preventDefault();const f=new FormData(event.currentTarget);const error=$('#worker-error');const schedule={...s,department:f.get('department').trim(),hoursPerWeek:Number(f.get('hours')),hourlyRate:Number(f.get('rate')),workDays:f.getAll('days'),firstName:f.get('firstName').trim(),surname:f.get('surname').trim(),identityNumber:f.get('identityNumber').trim(),occupation:f.get('occupation').trim(),startDate:f.get('startDate'),paymentMethod:f.get('paymentMethod').trim(),employerAddress:f.get('employerAddress').trim()};try{if(!schedule.workDays.length)throw new Error('Select at least one scheduled workday.');const body={name:f.get('name').trim(),email:f.get('email').trim()||null,schedule};if(!worker)body.employeeCode=f.get('code').trim();await api(worker?`/api/v1/admin/employees/${worker.id}`:'/api/v1/admin/employees',{method:worker?'PATCH':'POST',body});$('#modal').close();toast(worker?'Worker updated.':'Worker added.');renderEmployees();}catch(err){error.textContent=err.message;error.hidden=false;}};
  if(worker){
    $('#deactivate-worker').onclick=async()=>{if(!confirm(`Deactivate ${worker.name}? They will no longer be able to clock in.`))return;try{await api(`/api/v1/admin/employees/${worker.id}/deactivate`,{method:'POST',body:{}});$('#modal').close();toast('Worker deactivated.');renderEmployees();}catch(err){toast(err.message,true)}};
    $('#delete-worker').onclick=async()=>{if(!confirm(`Delete ${worker.name}? Attendance and audit history will be retained.`))return;try{await api(`/api/v1/admin/employees/${worker.id}/delete`,{method:'POST',body:{}});$('#modal').close();toast('Worker deleted.');renderEmployees();}catch(err){toast(err.message,true)}};
  }
}

async function renderAttendance(){
  const employees=state.cache.employees?.length?state.cache.employees:await getEmployees(); const initial=monthRange();
  $('#page').innerHTML=`<div class="toolbar"><div class="filters"><input id="att-from" type="date" value="${initial.from}"><input id="att-to" type="date" value="${initial.to}"><select id="att-worker"><option value="">All workers</option>${employees.map(e=>`<option value="${esc(e.id)}">${esc(e.name)}</option>`).join('')}</select><select id="att-status"><option value="">All statuses</option><option value="open">Open</option><option value="closed">Closed</option><option value="incomplete">Incomplete</option></select><button id="att-filter" class="secondary">Apply</button></div><div class="actions"><button id="mark-absent" class="secondary">Mark absent</button><button id="manual-time" class="primary">Add time entry</button></div></div><div id="attendance-table"></div>`;
  const load=async()=>{setLoading(true);try{const query=new URLSearchParams({from:$('#att-from').value,to:$('#att-to').value,limit:'500'});if($('#att-worker').value)query.set('employeeId',$('#att-worker').value);if($('#att-status').value)query.set('status',$('#att-status').value);const data=await api(`/api/v1/admin/attendance?${query}`);const rows=data.sessions||[];$('#attendance-table').innerHTML=rows.length?`<div class="table-wrap"><table><thead><tr><th>Date</th><th>Worker</th><th>Clock in</th><th>Clock out</th><th>Hours</th><th>Status</th><th></th></tr></thead><tbody>${rows.map(s=>`<tr><td>${esc(s.workDate)}</td><td>${esc(s.employeeName)} <span class="muted">#${esc(s.employeeCode)}</span></td><td>${esc(fmtTime(s.checkInAt))}</td><td>${esc(fmtTime(s.checkOutAt))}</td><td>${esc(hours(s.workedMinutes))}</td><td>${pill(s.status,s.status==='closed'?'green':s.status==='incomplete'?'red':'amber')}</td><td><button class="link-button edit-session" data-id="${esc(s.id)}">Edit times</button></td></tr>`).join('')}</tbody></table></div>`:'<div class="card empty">No attendance in this date range.</div>';$$('.edit-session').forEach(b=>b.onclick=()=>openSession(rows.find(r=>r.id===b.dataset.id),load));}catch(err){toast(err.message,true)}finally{setLoading(false)}};
  $('#att-filter').onclick=load;$('#manual-time').onclick=()=>openManualTime(employees,load);$('#mark-absent').onclick=()=>openAbsence(employees,load);await load();
}
function localInput(iso){if(!iso)return '';const d=new Date(iso);const local=new Date(d.getTime()-d.getTimezoneOffset()*60000);return local.toISOString().slice(0,16)}
function openManualTime(employees,onSaved){
  modal('Add time entry',`<form id="manual-form" class="form-grid"><label class="wide">Worker<select name="employeeId" required>${employees.filter(e=>e.status==='active').map(e=>`<option value="${esc(e.id)}">${esc(e.name)} (#${esc(e.employeeCode)})</option>`).join('')}</select></label><label>Clock in<input name="checkIn" type="datetime-local" required></label><label>Clock out (optional)<input name="checkOut" type="datetime-local"></label><label class="wide">Reason<input name="reason" value="Administrator time entry" required></label><p id="manual-error" class="form-error wide" hidden></p><div class="modal-actions wide"><button type="button" class="secondary" id="cancel-manual">Cancel</button><button class="primary">Save entry</button></div></form>`);$('#cancel-manual').onclick=()=>$('#modal').close();$('#manual-form').onsubmit=async(event)=>{event.preventDefault();const f=new FormData(event.currentTarget);try{const checkIn=new Date(f.get('checkIn'));const out=f.get('checkOut');if(out&&new Date(out)<=checkIn)throw new Error('Clock out must be after clock in.');await api('/api/v1/admin/corrections/manual-session',{method:'POST',body:{employeeId:f.get('employeeId'),checkInAt:checkIn.toISOString(),...(out?{checkOutAt:new Date(out).toISOString()}:{}),reason:f.get('reason').trim()}});$('#modal').close();toast('Time entry saved.');await onSaved();}catch(err){const e=$('#manual-error');e.textContent=err.message;e.hidden=false;}};
}
function openAbsence(employees,onSaved){
  modal('Mark worker absent',`<form id="absence-form" class="form-grid"><label class="wide">Worker<select name="employeeId" required>${employees.filter(e=>e.status==='active').map(e=>`<option value="${esc(e.id)}">${esc(e.name)} (#${esc(e.employeeCode)})</option>`).join('')}</select></label><label class="wide">Date<input name="workDate" type="date" required value="${isoDate()}"></label><label class="wide">Note<textarea name="note" rows="2"></textarea></label><p id="absence-error" class="form-error wide" hidden></p><div class="modal-actions wide"><button type="button" class="secondary" id="cancel-absence">Cancel</button><button class="danger">Mark absent</button></div></form>`);$('#cancel-absence').onclick=()=>$('#modal').close();$('#absence-form').onsubmit=async(event)=>{event.preventDefault();const f=new FormData(event.currentTarget);try{await api('/api/v1/admin/attendance/absence',{method:'POST',body:{employeeId:f.get('employeeId'),workDate:f.get('workDate'),note:f.get('note').trim()}});$('#modal').close();toast('Worker marked absent.');await onSaved();}catch(err){const e=$('#absence-error');e.textContent=err.message;e.hidden=false;}};
}
function openSession(session,onSaved){
  modal('Edit clock times',`<form id="session-form" class="form-grid"><div class="wide note">${esc(session.employeeName)} · ${esc(session.workDate)}</div><label>Clock in<input name="checkIn" type="datetime-local" required value="${esc(localInput(session.checkInAt))}"></label><label>Clock out<input name="checkOut" type="datetime-local" value="${esc(localInput(session.checkOutAt))}"></label><p id="session-error" class="form-error wide" hidden></p><div class="wide worker-danger"><button type="button" class="secondary" id="approve-session" ${session.status==='open'||session.reviewStatus==='approved'?'disabled':''}>${session.reviewStatus==='approved'?'Approved':'Approve time entry'}</button><button type="button" class="danger" id="delete-session">Delete time entry</button></div><div class="modal-actions wide"><button type="button" class="secondary" id="cancel-session">Cancel</button><button class="primary">Save time changes</button></div></form>`);$('#cancel-session').onclick=()=>$('#modal').close();$('#approve-session').onclick=async()=>{try{await api(`/api/v1/admin/attendance/${session.id}/approve`,{method:'POST',body:{}});$('#modal').close();toast('Time entry approved.');await onSaved();}catch(err){toast(err.message,true)}};$('#delete-session').onclick=async()=>{if(!confirm(`Delete this time entry for ${session.employeeName}? Raw scans and audit history will be retained.`))return;try{await api(`/api/v1/admin/attendance/${session.id}/delete`,{method:'POST',body:{reason:'Attendance entry removed from web dashboard'}});$('#modal').close();toast('Time entry deleted.');await onSaved();}catch(err){toast(err.message,true)}};$('#session-form').onsubmit=async(event)=>{event.preventDefault();const f=new FormData(event.currentTarget);try{const checkIn=new Date(f.get('checkIn')).toISOString();const out=f.get('checkOut');const checkOut=out?new Date(out).toISOString():null;if(checkOut&&new Date(checkOut)<=new Date(checkIn))throw new Error('Clock out must be after clock in.');const originalIn=new Date(session.checkInAt).toISOString();const originalOut=session.checkOutAt?new Date(session.checkOutAt).toISOString():null;if(checkIn===originalIn&&checkOut===originalOut){$('#modal').close();toast('No time changes to save.');return;}await api(`/api/v1/admin/attendance/${session.id}/times`,{method:'PATCH',body:{employeeId:session.employeeId,checkInAt:checkIn,checkOutAt:checkOut}});$('#modal').close();toast('Clock times updated.');await onSaved();}catch(err){const e=$('#session-error');e.textContent=err.message;e.hidden=false;}};
}

async function renderLeave(){
  const employees=state.cache.employees?.length?state.cache.employees:await getEmployees(); const data=await api('/api/v1/admin/leave'); const rows=data.leave||[];
  $('#page').innerHTML=`<div class="toolbar"><div class="filters"><select id="leave-filter"><option value="all">All leave</option><option value="approved">Approved</option><option value="pending">Pending</option><option value="rejected">Rejected</option><option value="cancelled">Cancelled</option></select></div><button id="add-leave" class="primary">Record leave</button></div><div id="leave-table"></div>`;
  const draw=()=>{const status=$('#leave-filter').value;const visible=status==='all'?rows:rows.filter(r=>r.status===status);$('#leave-table').innerHTML=visible.length?`<div class="table-wrap"><table><thead><tr><th>Worker</th><th>Type</th><th>Dates</th><th>Note</th><th>Status</th><th></th></tr></thead><tbody>${visible.map(r=>`<tr><td>${esc(r.employeeName)}</td><td>${esc(r.leaveType)}</td><td>${esc(r.startDate===r.endDate?r.startDate:`${r.startDate} – ${r.endDate}`)}</td><td>${esc(r.note||'—')}</td><td>${pill(r.status,r.status==='approved'?'green':r.status==='pending'?'amber':r.status==='rejected'?'red':'')}</td><td><button class="link-button edit-leave" data-id="${esc(r.id)}">Edit</button></td></tr>`).join('')}</tbody></table></div>`:'<div class="card empty">No matching leave records.</div>';$$('.edit-leave').forEach(b=>b.onclick=()=>openLeave(employees,rows.find(r=>r.id===b.dataset.id)));};$('#leave-filter').onchange=draw;$('#add-leave').onclick=()=>openLeave(employees,null);draw();
}
function openLeave(employees,entry){
  modal(entry?'Edit leave':'Record leave',`<form id="leave-form" class="form-grid"><label class="wide">Worker<select name="employeeId" ${entry?'disabled':''}>${employees.filter(e=>e.status==='active'||e.id===entry?.employeeId).map(e=>`<option value="${esc(e.id)}" ${e.id===entry?.employeeId?'selected':''}>${esc(e.name)}</option>`).join('')}</select></label><label>Leave type<select name="type">${['annual','sick','unpaid','other'].map(v=>`<option value="${v}" ${v===entry?.leaveType?'selected':''}>${v[0].toUpperCase()+v.slice(1)}</option>`).join('')}</select></label><label>Status<select name="status">${['approved','pending','rejected','cancelled'].map(v=>`<option value="${v}" ${v===(entry?.status||'approved')?'selected':''}>${v[0].toUpperCase()+v.slice(1)}</option>`).join('')}</select></label><label>Start date<input name="start" type="date" required value="${esc(entry?.startDate||isoDate())}"></label><label>End date<input name="end" type="date" required value="${esc(entry?.endDate||isoDate())}"></label><label class="wide">Note<textarea name="note" rows="2">${esc(entry?.note||'')}</textarea></label><p id="leave-error" class="form-error wide" hidden></p><div class="modal-actions wide"><button type="button" class="secondary" id="cancel-leave">Cancel</button><button class="primary">Save leave</button></div></form>`);$('#cancel-leave').onclick=()=>$('#modal').close();$('#leave-form').onsubmit=async(event)=>{event.preventDefault();const f=new FormData(event.currentTarget);try{if(f.get('end')<f.get('start'))throw new Error('End date must be on or after start date.');const body={startDate:f.get('start'),endDate:f.get('end'),leaveType:f.get('type'),status:f.get('status'),note:f.get('note').trim()};if(!entry)body.employeeId=f.get('employeeId');await api(entry?`/api/v1/admin/leave/${entry.id}`:'/api/v1/admin/leave',{method:entry?'PATCH':'POST',body});$('#modal').close();toast('Leave saved.');renderLeave();}catch(err){const e=$('#leave-error');e.textContent=err.message;e.hidden=false;}};
}

async function renderPayroll(){
  const month=isoDate().slice(0,7);$('#page').innerHTML=`<div class="card"><div class="card-head"><div><h3>Monthly payroll and payslips</h3><p class="muted">Default rate R30.23/hour · UIF automatically calculated at 1% of gross wages.</p></div><div class="actions"><input id="pay-month" type="month" value="${month}"><button id="pay-load" class="secondary">Preview</button><button id="pay-export" class="primary" disabled>Download Excel</button></div></div></div><div id="payroll-table"></div>`;
  let report; const load=async()=>{setLoading(true);try{const range=monthRange($('#pay-month').value);report=await api('/api/v1/admin/payroll/report',{method:'POST',body:{...range,format:'json',adjustments:[]}});const rows=report.workers||[];$('#payroll-table').innerHTML=rows.length?`<div class="table-wrap"><table><thead><tr><th>Worker</th><th>Hours</th><th>Rate</th><th>Gross</th><th>UIF (1%)</th><th>Other deductions</th><th>Net pay</th><th>Warnings</th></tr></thead><tbody>${rows.map(w=>`<tr><td>${esc(w.name)} <span class="muted">#${esc(w.code)}</span></td><td>${esc(hours(w.workedMinutes))}</td><td>${money(w.rate)}</td><td>${money(w.gross)}</td><td>${money(w.uif)}</td><td>${money(w.otherDeductions)}</td><td><strong>${money(w.net)}</strong></td><td>${w.unresolvedShifts?pill(`${w.unresolvedShifts} unfinished`,'red'):pill('Ready','green')}</td></tr>`).join('')}</tbody></table></div>`:'<div class="card empty">No workers for this payroll period.</div>';$('#pay-export').disabled=false;}catch(err){toast(err.message,true)}finally{setLoading(false)}};$('#pay-load').onclick=load;$('#pay-month').onchange=load;$('#pay-export').onclick=async()=>{try{const range=monthRange($('#pay-month').value);const blob=await api('/api/v1/admin/payroll/report',{method:'POST',body:{...range,format:'xlsx',adjustments:[]},download:true});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=`payroll-${range.from}-${range.to}.xlsx`;a.click();URL.revokeObjectURL(url);toast('Payroll workbook downloaded.');}catch(err){toast(err.message,true)}};await load();
}

async function renderAudit(){
  const data=await api('/api/v1/admin/audit?limit=200');const rows=data.events||[];$('#page').innerHTML=`<div class="toolbar"><div class="filters"><input id="audit-search" placeholder="Filter activity"></div></div><div id="audit-table"></div>`;const draw=()=>{const q=$('#audit-search').value.toLowerCase();const visible=rows.filter(r=>`${r.action} ${r.actorType} ${r.targetType||''} ${JSON.stringify(r.details||{})}`.toLowerCase().includes(q));$('#audit-table').innerHTML=visible.length?`<div class="table-wrap"><table><thead><tr><th>Time</th><th>Action</th><th>Actor</th><th>Target</th><th>Details</th></tr></thead><tbody>${visible.map(r=>`<tr><td>${esc(fmtTime(r.createdAt))}</td><td>${esc(r.action.replaceAll('_',' '))}</td><td>${esc(r.actorType)}</td><td>${esc(r.targetType||'—')}</td><td title="${esc(JSON.stringify(r.details||{}))}">${esc(JSON.stringify(r.details||{}).slice(0,100))}</td></tr>`).join('')}</tbody></table></div>`:'<div class="card empty">No matching audit activity.</div>';};$('#audit-search').oninput=draw;draw();
}

if(state.access&&state.refresh&&state.admin){api('/api/v1/admin/me').then(showApp).catch(()=>{clearSession();showLogin();});}else showLogin();
