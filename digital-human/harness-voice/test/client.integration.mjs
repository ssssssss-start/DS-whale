import assert from 'node:assert/strict'
import {createRequire} from 'node:module'
import {mkdtemp,writeFile,rm} from 'node:fs/promises'
import {join,resolve} from 'node:path'
import {tmpdir} from 'node:os'

const require = createRequire(import.meta.url), {build} = require('esbuild')
const harness = process.env.DSH_HARNESS ?? resolve(import.meta.dirname,'../../../deepseek-harness')
const fromHarness = createRequire(join(harness,'apps/web/package.json'))
const {JSDOM} = fromHarness('jsdom'), React = fromHarness('react'), {createRoot} = fromHarness('react-dom/client')
const folder = await mkdtemp(join(tmpdir(),'whale-launcher-ui-'))
const dom = new JSDOM('<div id="root"></div>',{url:'http://localhost',pretendToBeVisual:true})
const previous = new Map(), effects = [], requests = []
let slot, Component, dictionaries, root, running = true, visible = true, missing = false
function global(name,value) {previous.set(name,Object.getOwnPropertyDescriptor(globalThis,name));Object.defineProperty(globalThis,name,{value,writable:true,configurable:true})}
try {
  global('window',dom.window); global('document',dom.window.document); global('navigator',dom.window.navigator); global('IS_REACT_ACT_ENVIRONMENT',true)
  global('fetch',async (path,options) => {
    assert.equal(path,'api/whale-voice'); assert.equal(options.credentials,'same-origin')
    const body = JSON.parse(options.body); requests.push(body)
    if (body.action === 'desktop_toggle') {
      if (running) visible = !visible
      else {running = !missing;visible = running}
    }
    return Response.json({ok:true,value:{supported:true,running,visible,canHide:true,starting:false,problem:missing?'app_missing':null}})
  })
  const result = await build({entryPoints:[resolve(import.meta.dirname,'../src/client/index.js')],bundle:true,platform:'node',format:'cjs',write:false,
    plugins:[{name:'react',setup(builder){builder.onResolve({filter:/^react$/},() => ({path:fromHarness.resolve('react'),external:true}))}}]})
  const compiled = join(folder,'client.cjs'); await writeFile(compiled,result.outputFiles[0].text)
  const client = require(compiled)
  const ctx = {
    effect(fn){effects.push(fn())},
    locale:{register(ns,dicts){assert.equal(ns,'whale-launcher');dictionaries=dicts;return()=>{}}},
    slots:{inject(name,install){assert.equal(name,'sidebar.footer.action');effects.push(install())},register(value,component){slot=value;Component=component;return()=>{}}},
  }
  await React.act(async () => {client.apply(ctx)})
  assert.equal(slot.order,-400); assert.equal(slot.id,'whale-launcher')
  assert.deepEqual(requests,[{action:'desktop_autostart'}])
  root = createRoot(dom.window.document.getElementById('root'))
  const props = wide => ({wide,...slot.inject(),t:key=>dictionaries.zh[key]})
  await React.act(async () => root.render(React.createElement(Component,props(true))))
  assert.match(dom.window.document.body.textContent,/隐藏鲸鱼娘/)
  assert.equal(dom.window.document.querySelector('button').getAttribute('aria-pressed'),'true')
  await React.act(async () => dom.window.document.querySelector('button').click())
  assert.equal(requests.at(-1).action,'desktop_toggle')
  assert.match(dom.window.document.body.textContent,/显示鲸鱼娘/)
  assert.equal(dom.window.document.querySelector('button').getAttribute('aria-pressed'),'false')
  await React.act(async () => dom.window.document.querySelector('button').click())
  assert.match(dom.window.document.body.textContent,/隐藏鲸鱼娘/)
  running = false
  await React.act(async () => slot.inject().controller.refresh())
  assert.match(dom.window.document.body.textContent,/启动鲸鱼娘/)
  await React.act(async () => dom.window.document.querySelector('button').click())
  assert.equal(requests.at(-1).action,'desktop_toggle')
  assert.match(dom.window.document.body.textContent,/隐藏鲸鱼娘/)
  missing = true; running = false
  await React.act(async () => slot.inject().controller.refresh())
  assert.match(dom.window.document.querySelector('[role="alert"]').textContent,/未找到鲸鱼娘/)
  await React.act(async () => root.render(React.createElement(Component,props(false))))
  assert.equal(dom.window.document.querySelector('button').getAttribute('aria-label'),'启动鲸鱼娘')
  assert.equal(requests.filter(r=>r.action==='desktop_autostart').length,1)
  assert.equal(requests.some(r=>r.action.startsWith('call_')),false)
  console.log('Launcher UI integration passed: footer above DS Bot, hide/show/start toggle and pressed state, one-time autostart, localized errors, manual re-open and no voice call (mock API).')
} finally {
  if(root) await React.act(async()=>root.unmount())
  for (const effect of effects.reverse()) if(typeof effect==='function')effect()
  for (const [name,descriptor] of previous) {if(descriptor)Object.defineProperty(globalThis,name,descriptor);else delete globalThis[name]}
  dom.window.close(); await rm(folder,{recursive:true,force:true})
}
