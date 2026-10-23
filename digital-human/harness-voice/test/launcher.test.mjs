import {test} from 'node:test'
import assert from 'node:assert/strict'
import {CompanionLauncher} from '../launcher.js'
import {createBindingRoute} from '../binding.js'
import {LauncherController} from '../src/client/controller.js'

function fixture(extra = {}) {
  let now = 1000
  const opened = [], sent = []
  const launcher = new CompanionLauncher({platform:'darwin',appPath:'/Applications/My Whale.app',clock:() => now,
    isApp:async () => true,run:async (...args) => opened.push(args),send:m => {sent.push(m);return true},...extra})
  return {launcher,opened,sent,advance:ms => {now += ms}}
}

test('entering Harness starts once; closing the companion never makes polling or other windows restart it',async () => {
  const f = fixture()
  await Promise.all([f.launcher.launch(true),f.launcher.launch(true)])
  assert.equal(f.opened.length,1)
  assert.deepEqual(f.opened[0].slice(0,2),['/usr/bin/open',['-g','/Applications/My Whale.app']])
  assert.equal((await f.launcher.state()).starting,true)
  f.advance(9000)
  await f.launcher.state(); await f.launcher.launch(true)
  assert.equal(f.opened.length,1)
  await f.launcher.launch(false)
  assert.equal(f.opened.length,2,'manual re-open remains possible after deliberate close')
  assert.deepEqual(f.sent,[],'launching never starts speech or microphone capture')
})

test('already running companion is preserved and manual click reveals it without a new process',async () => {
  const f = fixture(); f.launcher.receive({type:'desktop_state',visible:false})
  await f.launcher.launch(true)
  assert.deepEqual(f.opened,[]); assert.deepEqual(f.sent,[])
  await f.launcher.launch(false)
  assert.deepEqual(f.sent,[{type:'show_companion'}]); assert.deepEqual(f.opened,[])
})

test('missing app, launch error, disabled autostart and unsupported hosts fail without shell commands or retries',async () => {
  const missing = fixture({isApp:async () => false}); assert.equal((await missing.launcher.launch(true)).problem,'app_missing'); assert.equal(missing.opened.length,0)
  const failed = fixture({run:async () => {throw new Error('private diagnostic')}})
  assert.equal((await failed.launcher.launch()).problem,'open_failed')
  assert.doesNotMatch(JSON.stringify(await failed.launcher.state()),/private diagnostic/)
  const off = fixture({autoStart:false}); await off.launcher.launch(true); assert.equal(off.opened.length,0); await off.launcher.launch(false); assert.equal(off.opened.length,1)
  const other = fixture({platform:'linux'}); assert.equal((await other.launcher.launch()).supported,false); assert.equal(other.opened.length,0)
  const relative = fixture({appPath:'relative/Whale.app'}); assert.equal((await relative.launcher.launch()).appFound,false)
  relative.launcher.close(); await assert.rejects(relative.launcher.launch(),/stopped/)
})

test('launcher route admits only fixed actions and never forwards browser-supplied executable paths',async () => {
  const actions = []
  const route = createBindingRoute({desktop:async action => {actions.push(action);return {running:true}}})
  const request = body => new Request('http://localhost/api/whale-voice',{method:'POST',body:JSON.stringify(body)})
  assert.equal((await route.fetch(request({action:'desktop_start',path:'/unexpected.app'}))).status,200)
  assert.deepEqual(actions,['desktop_start'])
  assert.equal((await route.fetch(request({action:'execute',path:'/unexpected.app'}))).status,400)
})

test('client bootstrap requests autostart once; polls never relaunch and a later click starts manually',async () => {
  const requests = [], controller = new LauncherController(async action => {requests.push(action);return {supported:true,running:false,starting:false,problem:null}})
  await controller.start(); await controller.refresh(); await controller.refresh(); await controller.launch()
  assert.deepEqual(requests,['desktop_autostart','desktop_state','desktop_state','desktop_toggle'])
  controller.close(); await controller.refresh(); await controller.launch(); assert.equal(requests.length,4)
})

test('toggle hides and reveals a running companion only after its reported state changes',async () => {
  const f = fixture()
  f.launcher.receive({type:'desktop_state',visible:true,visibilityProtocol:1})
  assert.equal((await f.launcher.state()).canHide,true)
  const hidden = f.launcher.toggle(), duplicate = f.launcher.toggle()
  assert.deepEqual(f.sent,[{type:'hide_companion'}])
  assert.equal((await f.launcher.state()).visible,true,'a sent command is not proof of a hidden window')
  assert.equal((await f.launcher.state()).changing,true)
  f.launcher.receive({type:'desktop_state',visible:false,visibilityProtocol:1})
  assert.equal((await hidden).visible,false); assert.equal((await duplicate).visible,false)
  await f.launcher.launch(true)
  assert.equal(f.sent.length,1,'entry autostart preserves a manually hidden companion')
  const shown = f.launcher.toggle()
  assert.equal(f.sent.at(-1).type,'show_companion')
  f.launcher.receive({type:'desktop_state',visible:true,visibilityProtocol:1})
  assert.equal((await shown).visible,true)
  assert.deepEqual(f.opened,[],'hide/show never restart the app or open a microphone')
})

test('visibility failure, legacy desktops and stale connections do not pretend that a hide succeeded',async () => {
  const f = fixture({visibilityTimeout:10})
  f.launcher.receive({type:'desktop_state',visible:true,visibilityProtocol:1})
  assert.equal((await f.launcher.toggle()).problem,'visibility_failed')
  assert.equal((await f.launcher.state()).visible,true)
  const lost = fixture({send:() => false})
  lost.launcher.receive({type:'desktop_state',visible:true,visibilityProtocol:1})
  assert.equal((await lost.launcher.toggle()).problem,'unavailable')
  const legacy = fixture(); legacy.launcher.receive({type:'desktop_state',visible:true})
  await legacy.launcher.toggle(); assert.deepEqual(legacy.sent,[{type:'show_companion'}])
  assert.equal((await legacy.launcher.state()).canHide,false)
  const stopped = fixture(); stopped.launcher.receive({type:'desktop_state',visible:true,visibilityProtocol:1})
  const hiding = stopped.launcher.toggle(); stopped.launcher.close()
  assert.equal((await hiding).problem,'unavailable')
  f.advance(7000); assert.equal((await f.launcher.state()).visible,false)
  await f.launcher.toggle(); assert.equal(f.opened.length,1,'an exited companion is launched instead of receiving a hide')
})

test('late polls cannot replace a launch result and disposal prevents late updates',async () => {
  let finish
  const controller = new LauncherController(action => action === 'desktop_state' ? new Promise(resolve => {finish = resolve}) : Promise.resolve({running:true,starting:false}))
  const poll = controller.refresh(); await controller.launch(); finish({running:false}); await poll
  assert.equal(controller.getSnapshot().running,true)
  const late = controller.refresh(); controller.close(); finish({running:false}); await late
  assert.equal(controller.getSnapshot().running,true)
})
