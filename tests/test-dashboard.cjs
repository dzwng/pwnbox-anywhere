const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const elements = new Map();
const actions = [];
const requests = [];
function element(id) {
  if (!elements.has(id)) elements.set(id, {
    contains(){return false;}, querySelectorAll(){return [];},
    id, value: id === 'bootnext-os' ? 'windows' : '', handlers: {}, dataset: {}, checked:false,
    classList:{add(){},remove(){},toggle(){}}, lastChild:{textContent:''},
    addEventListener(kind, handler) { (this.handlers[kind] ??= []).push(handler); },
    querySelector(selector) { return element(id + selector); },
    showModal(){this.open=true;}, close(){this.open=false;},
  });
  return elements.get(id);
}
for (const kind of ['windows','linux','off','bootnext','reboot','vm-start','vm-stop']) {
  const button = element('action-' + kind); button.dataset.action = kind; actions.push(button);
}
const context = vm.createContext({
  document:{hidden:false, getElementById:element, querySelectorAll:s => s === '[data-action]' ? actions : [], addEventListener(){}},
  Intl, AbortSignal, crypto:{randomUUID:()=>'test-request-123456789'},
  setTimeout(){return 1;}, clearTimeout(){},
  fetch:async (path, options) => {
    requests.push({path, payload:options?.body ? JSON.parse(options.body) : null});
    return path === '/api/session' ? {ok:false,status:401,json:async()=>({error:'Not signed in'})} : {ok:true,status:202,json:async()=>({})};
  }
});
vm.runInContext(fs.readFileSync('web/static/app.js','utf8'),context);
async function emit(id,kind) { for(const handler of element(id).handlers[kind] ?? []) await handler(); }
const powerRequests = () => requests.filter(r=>r.path === '/api/actions');
(async()=>{
  await new Promise(resolve => setImmediate(resolve));
  for (const os of ['kali','windows','kali']) {
    element('bootnext-os').value = os;
    await emit('bootnext-os','change'); await emit('bootnext-os','input');
  }
  assert.equal(powerRequests().length,0);
  console.log('PASS: changing BootNext selection sends no power/firmware request');
  for (const [kind,os,expected] of [['bootnext','kali','bootnext-kali'],['bootnext','windows','bootnext-windows'],['reboot','kali','reboot-kali'],['windows','kali','windows'],['vm-start','kali','vm-start'],['vm-stop','windows','vm-stop']]) {
    element('bootnext-os').value=os;
    const count=powerRequests().length;
    await emit('action-'+kind,'click');
    assert.equal(powerRequests().length,count);
    element('confirm-check').checked=true; await emit('confirm-check','change');
    await emit('confirm-action','click');
    assert.equal(powerRequests().length,count+1);
    assert.equal(powerRequests().at(-1).payload.action,expected);
    console.log('PASS: confirmed '+kind+' with selection '+os+' sends '+expected);
  }
  function renderState(host, guest, age=0, linux='kali') {
    vm.runInContext(`snapshot = {status:{state:${JSON.stringify(host)},linux_os:${JSON.stringify(linux)},checked_at:Date.now()/1000},thinkpad:{},desktop:{},jobs:[],diagnostic:{},vmware:{state:${JSON.stringify(guest)},checked_at:Date.now()/1000-${age}}}; render();`,context);
  }
  renderState('WINDOWS','RUNNING');
  assert.equal(element('desktop-os').textContent,'Windows 11');
  assert.equal(element('vmware-status').textContent,'Running · guest SSH verified');
  for (const kind of ['linux','off','reboot','vm-start']) assert.equal(element('action-'+kind).disabled,true);
  assert.equal(element('action-vm-stop').disabled,false);
  renderState('WINDOWS','STOPPED');
  assert.equal(element('action-vm-start').disabled,false);
  assert.equal(element('action-vm-stop').disabled,true);
  assert.equal(element('action-linux').disabled,false);
  renderState('KALI','HOST_UNAVAILABLE');
  assert.equal(element('action-vm-start').disabled,false);
  assert.equal(element('action-vm-stop').disabled,true);
  for (const state of ['DISABLED','CONFIG_ERROR']) {
    renderState('WINDOWS',state);
    for (const kind of ['vm-start','vm-stop']) assert.equal(element('action-'+kind).disabled,true);
  }
  renderState('WINDOWS','RUNNING',90);
  assert.equal(element('vmware-status').textContent,'Unverified');
  assert.equal(element('action-vm-stop').disabled,true);
  console.log('PASS: host/guest rendering, disabled controls, stale VM state and confirmed VM actions');
  renderState('WINDOWS','RUNNING',0,'ubuntu');
  assert.equal(element('linux-action-label').textContent,'Start Ubuntu dual boot');
  assert.equal(element('bootnext-linux').value,'ubuntu');
  assert.equal(element('action-linux').disabled,true);
  renderState('WINDOWS','STOPPED',0,'ubuntu');
  assert.equal(element('action-linux').disabled,false);
  await emit('action-linux','click');
  element('confirm-check').checked=true;
  await emit('confirm-action','click');
  assert.equal(powerRequests().at(-1).payload.action,'ubuntu');
  renderState('UBUNTU','HOST_UNAVAILABLE',0,'ubuntu');
  assert.equal(element('desktop-os').textContent,'Ubuntu dual boot');
  assert.equal(element('action-linux').disabled,true);
  assert.equal(element('action-vm-start').disabled,false);
  console.log('PASS: Ubuntu profile selects the Ubuntu boot action and keeps guest controls separate');
})().catch(error=>{console.error(error);process.exitCode=1;});
