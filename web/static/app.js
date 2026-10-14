'use strict';
const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = name => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
const fmt = new Intl.NumberFormat('en-GB', {maximumFractionDigits:1});
const actions = {windows:'Start Windows', kali:'Start Kali', off:'Power off'};
for (const os of ['windows', 'kali']) {
  actions[`bootnext-${os}`] = `Set BootNext to ${os === 'kali' ? 'Kali Linux' : 'Windows 11'}`;
  actions[`reboot-${os}`] = `Reboot into ${os === 'kali' ? 'Kali Linux' : 'Windows 11'}`;
}
const actionIcon = action => action.startsWith('reboot-') ? 'refresh' : action.startsWith('bootnext-') ? 'arrow' : action === 'off' ? 'power' : action;
const states = {WINDOWS:'Windows 11', KALI:'Kali Linux', UNKNOWN:'Unknown', OFF:'Powered off · inferred', TRANSITIONING:'In progress…'};
let csrf = '', snapshot = null, timer = null, polling = false, pending = null, view = 'overview', diagnosticPending = false;

async function api(path, data) {
  const response = await fetch(path, {method:data === undefined ? 'GET':'POST', credentials:'same-origin',
    headers:data === undefined ? {} : {'Content-Type':'application/json','X-CSRF-Token':csrf},
    body:data === undefined ? undefined : JSON.stringify(data), signal:AbortSignal.timeout(10000)});
  const result = await response.json();
  if (!response.ok) {
    if (response.status === 401 && path !== '/api/login') showLogin();
    throw new Error(result.error || 'Request failed.');
  }
  return result;
}

function showLogin() { clearTimeout(timer); csrf = ''; $('shell').hidden = true; $('login').hidden = false; }
function toast(message) { $('toast').textContent = message; $('toast').hidden = false; setTimeout(() => $('toast').hidden = true, 5000); }
function percent(value) { return typeof value === 'number' && Number.isFinite(value) ? `${fmt.format(value)}%` : 'No data'; }
function bytes(value) { return typeof value === 'number' && Number.isFinite(value) ? `${fmt.format(value / 1024 ** 3)} GiB` : '—'; }
function age(value) { if (!value) return 'No data'; const s = Math.max(0, Math.floor(Date.now()/1000-value)); return s < 3 ? 'Just updated' : s < 60 ? `${s} seconds ago` : `${Math.floor(s/60)} minutes ago`; }
function uptime(value) { if (typeof value !== 'number') return 'Uptime —'; const hours = Math.floor(value/3600); return `Uptime ${hours >= 24 ? Math.floor(hours/24)+'d ' : ''}${hours%24}h`; }
function time(value) { return new Date(value*1000).toLocaleTimeString('en-GB', {hour:'2-digit',minute:'2-digit',second:'2-digit'}); }
function metric(name, value, total, color='teal', suffix='') {
  const valid = typeof value === 'number' && Number.isFinite(value) && (total === undefined || typeof total === 'number' && total > 0);
  const amount = valid ? total === undefined ? percent(value) : `${bytes(value)} <span>/ ${bytes(total)}</span>` : '<span>No data</span>';
  const width = valid ? Math.round(Math.max(0,Math.min(100,total === undefined ? value : value/total*100))) : 0;
  const glyph = {CPU:'cpu',RAM:'memory',Disk:'disk',GPU:'gpu',VRAM:'memory'}[name] || 'pulse';
  return `<div class="metric ${name === 'Disk' ? 'metric-wide' : ''}"><div class="metric-label"><span class="metric-glyph ${color}">${icon(glyph)}</span><span class="metric-name">${esc(name)}${suffix ? ` · ${esc(suffix)}` : ''}</span>${valid && total !== undefined ? `<span class="metric-ratio">${percent(value/total*100)}</span>` : ''}</div><div class="metric-value">${amount}</div><div class="track ${color}"><i class="fill-${width}"></i></div></div>`;
}
// Width classes are defined in style.css; no eval, external scripts or inline handlers.
function activeJob() { return snapshot?.jobs.find(j => j.status === 'running'); }
function explain(message) {
  if (message.includes('Sending Wake-on-LAN')) return 'Wake-on-LAN sent. Waiting for your desktop to start.';
  if (message.includes('one-time firmware boot')) return 'Requesting a one-time boot into Kali Linux.';
  if (message.includes('Kali one-time')) return 'Requesting a reboot into Windows.';
  if (message.includes('clean reboot')) return message.replace(/^\[pwnbox\]\s*/, '');
  if (message.includes('Requesting clean') || message.includes('Requesting Kali shutdown')) return 'Shutdown requested on the running OS.';
  if (message.includes('Waiting for')) return 'Waiting for the requested state to be verified…';
  if (message.includes('detected') || message.includes('ready:')) return 'Target operating system verified over SSH.';
  if (message.includes('OFF inferred')) return 'Shutdown acknowledged. LAN is reachable; the desktop no longer responds.';
  if (message.includes('already ready') || message.includes('already')) return 'The desktop is already in the requested state.';
  if (message.includes('Timed out')) return 'Timed out. The requested state has not been verified.';
  if (message.includes('without a reliable')) return 'Connection lost while sending the command. Checking the result without resending.';
  return message.replace(/^\[pwnbox\]\s*/, '');
}

function renderHistory(jobs, details=false) {
  if (!jobs.length) return '<div class="empty">No activity yet. Your operations will appear here.</div>';
  const statuses = {success:'Verified successfully',failed:'Failed / not verified',running:'In progress',interrupted:'Service restarted; check the current state'};
  return jobs.map(job => `<div class="history-row"><span class="history-symbol ${esc(job.status)}">${icon(job.status === 'success' ? 'check' : job.status === 'running' ? 'clock' : 'close')}</span><div><div class="history-title">${esc(actions[job.action] || job.action)}</div><div class="history-subtitle">${esc(statuses[job.status])}${job.code !== null && job.code !== 0 ? ` · code ${esc(job.code)}`:''}</div></div><time datetime="${new Date(job.started*1000).toISOString()}">${esc(new Date(job.started*1000).toLocaleString('en-GB',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}))}</time>${details ? `<details class="history-details"><summary>Operation details</summary><pre>${job.events.map(e => `${esc(time(e.time))}  ${esc(e.message)}`).join('\n')}</pre></details>`:''}</div>`).join('');
}

function render() {
  const {status,thinkpad:tp,desktop:pc,jobs,diagnostic,demo} = snapshot;
  const job = activeJob();
  $('demo-banner').hidden = !demo;
  $('desktop-os').textContent = states[status.state] || states.UNKNOWN;
  const known = status.state === 'WINDOWS' || status.state === 'KALI';
  $('desktop-badge').innerHTML = `${known ? '<span class="dot"></span>' : ''}${known ? 'Running' : status.state === 'TRANSITIONING' ? 'Switching' : status.state === 'OFF' ? 'Not responding' : 'Unknown'}`;
  $('desktop-badge').className = `badge ${known ? 'green' : status.state === 'TRANSITIONING' ? 'amber' : 'muted'}`;
  $('desktop-state-note').textContent = known ? 'Operating system verified over SSH' : status.state === 'OFF' ? 'Off inferred after shutdown · power state is not measured' : status.state === 'TRANSITIONING' ? 'Follow the operation below' : 'Power state has not been confirmed';
  $('status-age').textContent = age(status.checked_at);
  $('current-os-icon').className = `current-os-icon ${known ? status.state.toLowerCase() : ''}`;
  $('current-os-icon').innerHTML = known ? icon(status.state === 'WINDOWS' ? 'windows' : 'kali') : icon('desktop');
  $('thinkpad-uptime').textContent = uptime(tp.uptime);
  $('thinkpad-age').textContent = age(tp.sampled_at);
  $('desktop-age').textContent = age(pc.sampled_at);
  $('thinkpad-metrics').innerHTML = metric('CPU', tp.cpu_percent) + metric('RAM',tp.ram_used,tp.ram_total,'blue') + metric('Disk',tp.disk_used,tp.disk_total,'amber');
  const battery = {'Charging':'Charging','Discharging':'On battery','Not charging':'Not charging','Full':'Fully charged'};
  const power = tp.ac_online === true ? 'AC connected' : tp.ac_online === false ? 'AC disconnected' : '';
  const charge = battery[tp.battery_status] || 'Charging status unavailable';
  const thresholds = tp.charge_start_threshold != null && tp.charge_stop_threshold != null ? `Charge limits ${percent(tp.charge_start_threshold)}–${percent(tp.charge_stop_threshold)}` : '';
  $('thinkpad-extras').innerHTML = `<span>${icon('temperature')}Temperature <b>${tp.temperature != null ? fmt.format(tp.temperature)+'°C':'—'}</b></span><span>${icon('battery')}Battery <b>${tp.battery_percent != null ? percent(tp.battery_percent):'—'}</b></span><span>${icon('shield')}Battery health <b>${tp.battery_health != null ? percent(tp.battery_health):'—'}</b></span><span class="power-source">${icon('plug')}${esc([power,charge].filter(Boolean).join(' · '))}</span>${thresholds ? `<span>${esc(thresholds)}</span>` : ''}`;
  const fresh = pc.sampled_at && Date.now()/1000 - pc.sampled_at < 20 && !pc.error;
  const values = fresh ? pc : {};
  $('desktop-metrics').innerHTML = metric('CPU',values.cpu_percent) + metric('RAM',values.ram_used,values.ram_total,'blue') + metric('Disk',pc.disk_used,pc.disk_total,'amber',pc.disk_mount || '') + metric('GPU',values.gpu_percent,undefined,'violet') + metric('VRAM',values.vram_used,values.vram_total,'violet');
  $('gpu-note').textContent = 'AMD Radeon RX 9060 XT · 16 GB VRAM' + (pc.gpu_note ? ` · ${pc.gpu_note}` : '');
  $('desktop-metrics-error').hidden = !pc.error && (!known || fresh);
  $('desktop-metrics-error').textContent = pc.error || 'Metrics are unavailable or stale. Waiting for a fresh sample.';
  document.querySelectorAll('[data-action]').forEach(button => {
    button.disabled = !!job || (['off', 'bootnext', 'reboot'].includes(button.dataset.action) && !known) || (button.dataset.action.toUpperCase() === status.state);
    button.title = button.dataset.action.toUpperCase() === status.state ? 'Already running this OS' : '';
  });
  $('bootnext-os').disabled = !!job;
  $('operation').hidden = !job;
  if (job) $('operation').innerHTML = `<div class="operation-title"><div class="operation-heading"><span class="operation-icon">${icon(actionIcon(job.action))}</span><div><span class="eyebrow">OPERATION IN PROGRESS</span><h3>${esc(actions[job.action])}</h3></div></div><span class="spinner" aria-label="Processing"></span></div><p>Your controller is processing and verifying this request.</p><div class="operation-events">${job.events.slice(-5).map(e => `<div><span class="event-marker"></span><span>${esc(explain(e.message))}</span><time>${esc(time(e.time))}</time></div>`).join('') || '<div>Request accepted. Preparing to check the desktop…</div>'}</div><div class="operation-footnote">${icon('shield')}You can close or reload this page. The operation continues on your ThinkPad.</div>`;
  $('recent-history').innerHTML = renderHistory(jobs.slice(0,4));
  // Preserve expanded history details across periodic snapshots.
  if (!$('full-history').contains(document.activeElement) && ![...$('full-history').querySelectorAll('details')].some(d => d.open)) $('full-history').innerHTML = renderHistory(jobs,true);
  $('diagnostic-time').textContent = diagnostic.time ? 'Checked at '+new Date(diagnostic.time*1000).toLocaleString('en-GB') : 'Not checked yet';
  $('diagnostic-output').textContent = diagnostic.output;
  diagnosticPending = snapshot.diagnostic_running;
  $('diagnose').disabled = !!job || !!diagnosticPending;
  $('diagnose').innerHTML = diagnosticPending ? '<span class="spinner"></span>Checking…' : icon('refresh')+'Run check';
}

async function poll() {
  clearTimeout(timer);
  if (!csrf || document.hidden || polling) return;
  polling = true;
  try {
    snapshot = await api('/api/snapshot'); render();
    $('connection-error').hidden = true; document.body.classList.remove('connection-bad');
    $('connection-label').textContent = 'Live updates';
  } catch (error) {
    $('connection-error').textContent = 'Connection lost. Displayed data may be stale. Reconnecting…';
    $('connection-error').hidden = false; document.body.classList.add('connection-bad');
    $('connection-label').textContent = 'Reconnecting';
    document.querySelectorAll('[data-action]').forEach(button => button.disabled = true);
  } finally {
    polling = false;
    if (csrf && !document.hidden) timer = setTimeout(poll, activeJob() || diagnosticPending ? 2000 : 5000);
  }
}

function navigate(name) {
  const views = {overview:['Overview','Your machines. One place. Anywhere.'],diagnostics:['Diagnostics','A clear view of your controller and desktop connectivity.'],history:['Activity','Every operation, with its verified result and full details.']};
  if (!views[name]) return;
  view = name;
  for (const key of Object.keys(views)) $(key).hidden = key !== name;
  $('page-title').textContent = $('crumb').textContent = views[name][0]; $('page-description').textContent = views[name][1];
  document.querySelectorAll('[data-view]').forEach(b => { b.classList.toggle('active',b.dataset.view === name); if (b.dataset.view === name) b.setAttribute('aria-current','page'); else b.removeAttribute('aria-current'); });
}
document.querySelectorAll('[data-view]').forEach(b => b.addEventListener('click', () => navigate(b.dataset.view)));
document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => {
  const kind = button.dataset.action;
  const action = ['bootnext', 'reboot'].includes(kind) ? `${kind}-${$('bootnext-os').value}` : kind;
  const target = action.split('-').pop();
  const targetName = target === 'kali' ? 'Kali Linux' : 'Windows 11';
  pending = {action, request_id:crypto.randomUUID(), confirmed:true};
  $('confirm-title').textContent = actions[action];
  $('confirm-description').textContent = kind === 'bootnext' ? `Set the next boot to ${targetName}. The desktop keeps running; this choice is used once.` : kind === 'reboot' ? `Set BootNext to ${targetName}, then restart the running desktop directly into that OS.` : action === 'off' ? 'Shut down your desktop through the running OS. Your ThinkPad stays online.' : `Start your desktop in ${targetName}. An offline desktop will be woken; switching from another OS requires a reboot.`;
  $('confirm-icon').innerHTML = icon(actionIcon(action));
  $('confirm-icon').className = `confirm-icon ${target}`;
  const current = snapshot?.status.state || 'UNKNOWN';
  const currentIcon = current === 'WINDOWS' ? 'windows' : current === 'KALI' ? 'kali' : 'desktop';
  $('confirm-transition').innerHTML = `<div><span class="transition-icon ${currentIcon}">${icon(currentIcon)}</span><small>Current state</small><b>${esc(states[current] || states.UNKNOWN)}</b></div>${icon('arrow')}<div><span class="transition-icon ${target}">${icon(target === 'off' ? 'power' : target)}</span><small>${kind === 'bootnext' ? 'Next boot only' : 'Requested state'}</small><b>${action === 'off' ? 'Powered off' : targetName}</b></div>`;
  $('confirm-dialog').querySelector('.notice').hidden = kind === 'bootnext';
  $('confirm-dialog').querySelector('.confirm-check').lastChild.textContent = kind === 'bootnext' ? 'I want to set the OS for the next boot.' : 'I have saved my work and want to continue.';
  $('confirm-check').checked = false; $('confirm-action').disabled = true; $('confirm-error').textContent = '';
  $('confirm-dialog').showModal();
}));
$('confirm-check').addEventListener('change', () => $('confirm-action').disabled = !$('confirm-check').checked);
$('cancel-action').addEventListener('click', () => $('confirm-dialog').close());
$('confirm-action').addEventListener('click', async () => {
  $('confirm-action').disabled = true; $('cancel-action').disabled = true;
  try { await api('/api/actions',pending); $('confirm-dialog').close(); toast('Request accepted. Follow its progress on the dashboard.'); await poll(); }
  catch (error) { $('confirm-error').textContent = error.message + ' If the connection was lost, check the operation before trying again.'; }
  finally { $('confirm-action').disabled = !$('confirm-check').checked; $('cancel-action').disabled = false; }
});
$('diagnose').addEventListener('click', async () => {
  $('diagnose').disabled = true;
  try { await api('/api/diagnose',{}); diagnosticPending = true; await poll(); }
  catch(error) { toast(error.message); $('diagnose').disabled = false; }
});
$('login-form').addEventListener('submit', async event => {
  event.preventDefault(); const button = event.target.querySelector('button'); button.disabled = true; $('login-error').textContent = '';
  try { const result = await api('/api/login',{password:$('password').value}); csrf=result.csrf; $('password').value=''; $('login').hidden=true; $('shell').hidden=false; await poll(); }
  catch(error) { $('login-error').textContent = error.message; }
  finally { button.disabled=false; }
});
$('logout').addEventListener('click', async () => { try { await api('/api/logout',{}); showLogin(); } catch(error) { toast(error.message); } });
document.addEventListener('visibilitychange', () => { if (document.hidden) clearTimeout(timer); else poll(); });
(async () => { try { const result = await api('/api/session'); csrf=result.csrf; $('shell').hidden=false; await poll(); } catch { showLogin(); } })();
