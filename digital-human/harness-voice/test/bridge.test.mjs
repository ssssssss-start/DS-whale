import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Sentences } from '../sentences.js'
import { createBridge } from '../index.js'

test('sentences across chunks, code fences and trailing fragments', () => {
 const out = [], split = new Sentences(s => out.push(s))
 for (const chunk of ['你好', '呀。今天', '陪你！\n```js\n', 'const a = 1;\n```\n', '慢慢来']) split.push(chunk)
 split.push('', true)
 assert.deepEqual(out, ['你好呀。', '今天陪你！', '慢慢来'])
})
test('requires explicit user marker; reads visible text once, skips reasoning', () => {
 const out = [], bridge = createBridge(s => out.push(s), () => 1234)
 const session = { id: 'test' }
 const user = text => bridge(session, { type: 'user/message', data: { turn: 1, source: {kind:'user'}, content: [{type:'text', text}] } })
 const chunk = (type,text) => bridge(session, {type:'assistant/chunk',data:{chunk:{type,text}}})
 user('unrelated'); chunk('text-delta','Do not speak.'); assert.equal(out.length,0)
 user('[whale] Say hello'); chunk('reasoning-delta','private reasoning'); chunk('text-delta','你来啦。'); chunk('text-delta','我在呢')
 bridge(session,{type:'assistant/message',data:{message:{content:[{type:'text',text:'你来啦。我在呢'}]}}})
 bridge(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
 assert.deepEqual(out.map(s=>s.type),['start','sentence','end'])
 assert.deepEqual(out.filter(s=>s.type==='sentence').map(s=>s.text),['你来啦。 我在呢'])
})
test('replacement cancels previous turn; background injections do not opt in', () => {
 const out = [], bridge = createBridge(s => out.push(s))
 const session={id:'test'}
 const input=(source,text)=>bridge(session,{type:'user/message',data:{turn:1,source:{kind:source},content:[{type:'text',text}]}})
 input('schedule','[whale] should not speak'); assert.equal(out.length,0)
 input('user','[whale] hi'); input('user','different question')
 assert.deepEqual(out.map(s=>s.type),['start','cancel'])
})
test('public live assistant event feeds speech before durable settlement', () => {
 const out=[], bridge=createBridge(s=>out.push(s)), session={id:'live'}
 bridge(session,{type:'user/message',data:{turn:1,source:{kind:'user'},content:[{type:'text',text:'[whale] test'}]}})
 bridge.stream({agent:{session},frame:{type:'start'}})
 bridge.stream({agent:{session},frame:{type:'chunk',chunk:{type:'text-delta',text:'我一直在这里陪着你，现在可以直接和我说话。'}}})
 assert.deepEqual(out.map(s=>s.type),['start','sentence'])
 bridge.stream({agent:{session},frame:{type:'end',outcome:{kind:'committed',eventType:'assistant/message'}}})
 bridge(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
 assert.equal(out.at(-1).type,'end')
})
test('bound direct replies speak without a marker; history and other sources stay silent',()=>{
 const out=[],bridge=createBridge(m=>out.push(m),()=>1234,id=>id==='bound'),session={id:'bound'}
 const input=(s,kind,text)=>bridge(s,{type:'user/message',data:{turn:1,source:{kind},content:[{type:'text',text}]}})
 bridge(session,{type:'assistant/message',data:{message:{content:[{type:'text',text:'old history'}]}}})
 input({id:'other'},'user','hello')
 input(session,'schedule','background reminder')
 input(session,'bot','background Bot message')
 assert.equal(out.length,0)
 input(session,'user','你是谁呀')
 bridge.stream({agent:{session},frame:{type:'chunk',chunk:{type:'reasoning-delta',text:'hidden reasoning'}}})
 bridge.stream({agent:{session},frame:{type:'chunk',chunk:{type:'text-delta',text:'我在这里。'}}})
 bridge(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
 assert.deepEqual(out.map(m=>m.type),['start','sentence','end'])
 assert.equal(out[1].text,'我在这里。')
})
test('unbinding cancels a bound reply even after turn/end; late stream fragments are discarded',()=>{
 const out=[],bridge=createBridge(m=>out.push(m),()=>1234,()=>true),session={id:'bound'}
 const start=turn=>bridge(session,{type:'user/message',data:{turn,source:{kind:'user'},content:[{type:'text',text:'hello'}]}})
 start(1);bridge(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
 bridge.syncBinding(null)
 assert.deepEqual(out.map(m=>m.type),['start','end','cancel'])
 start(2);bridge.syncBinding('other')
 bridge.stream({agent:{session},frame:{type:'chunk',chunk:{type:'text-delta',text:'late reply。'}}})
 assert.equal(out.filter(m=>m.type==='sentence').length,0)
})
test('bound DND commands stay silent; explicit one-turn speech still works outside the binding',()=>{
 const out=[],bridge=createBridge(m=>out.push(m),()=>1234,id=>id==='bound')
 bridge({id:'bound'},{type:'user/message',data:{turn:1,source:{kind:'user'},content:[{type:'text',text:'先别打扰我'}]}})
 assert.equal(out.length,0)
 bridge({id:'other'},{type:'user/message',data:{turn:2,source:{kind:'user'},content:[{type:'text',text:'[whale] hello'}]}})
 bridge.syncBinding(null)
 assert.deepEqual(out.map(m=>m.type),['start'])
})
test('runtime context snapshots do not cancel the user reply before its first text chunk',()=>{
 const out=[],bridge=createBridge(m=>out.push(m),()=>1234,()=>true),session={id:'bound'}
 bridge(session,{type:'user/message',seq:20,data:{source:{kind:'user'},content:[{type:'text',text:'hello'}]}})
 bridge(session,{type:'user/message',seq:21,data:{source:{kind:'runtime-context'},content:[{type:'text',text:'private runtime snapshot'}]}})
 bridge.stream({agent:{session},frame:{type:'chunk',chunk:{type:'text-delta',text:'你好呀。'}}})
 bridge(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
 assert.deepEqual(out.map(m=>m.type),['start','sentence','end'])
 assert.equal(out[1].text,'你好呀。')
})


test('terminal text closes TTS before settlement, exactly once; old turn end cannot close a new reply',()=>{
 const out=[],session={id:'call'},bridge=createBridge(m=>out.push(m),()=>1000,()=>true)
 const user=n=>bridge(session,{type:'user/message',data:{turn:n,source:{kind:'user'},content:[{type:'text',text:'hello'}]}})
 const frame=f=>bridge.stream({agent:{session},frame:f})
 user(1);frame({type:'start',turn:1,attemptId:'a'})
 frame({type:'chunk',attemptId:'a',chunk:{type:'text-delta',text:'一条回复'}})
 frame({type:'chunk',attemptId:'a',chunk:{type:'finish',reason:{kind:'stop'}}})
 assert.deepEqual(out.map(m=>m.type),['start','sentence','end'])
 frame({type:'end',attemptId:'a',outcome:{kind:'committed',eventType:'assistant/message'}})
 assert.equal(out.filter(m=>m.type==='end').length,1)
 user(2);frame({type:'start',turn:2,attemptId:'b'})
 bridge(session,{type:'turn/end',data:{turn:1,reason:{kind:'completed'}}})
 frame({type:'end',attemptId:'a',outcome:{kind:'abandoned'}})
 frame({type:'chunk',attemptId:'b',chunk:{type:'text-delta',text:'新回复'}})
 frame({type:'chunk',attemptId:'b',chunk:{type:'finish',reason:{kind:'stop'}}})
 assert.equal(out.at(-2).text,'新回复');assert.equal(out.at(-1).turn,'call:2')
 bridge.close()
})

test('tool steps and unknown/error finish reasons do not prematurely close speech input',()=>{
 for(const reason of ['stop','tool-calls','error','aborted','future-reason']) {
  const out=[],session={id:'call'},bridge=createBridge(m=>out.push(m),()=>1000,()=>true)
  const frame=f=>bridge.stream({agent:{session},frame:f})
  bridge(session,{type:'user/message',data:{turn:1,source:{kind:'user'},content:[{type:'text',text:'hello'}]}})
  frame({type:'start',turn:1,attemptId:'tool'})
  frame({type:'chunk',chunk:{type:'text-delta',text:'让我查查。'}})
  if(reason==='stop') frame({type:'chunk',chunk:{type:'tool-call-delta'}})
  frame({type:'chunk',chunk:{type:'finish',reason:{kind:reason}}})
  assert.equal(out.some(m=>m.type==='end'),false,reason)
  frame({type:'start',turn:1,attemptId:'answer'})
  frame({type:'chunk',chunk:{type:'text-delta',text:'查好了。'}})
  frame({type:'chunk',chunk:{type:'finish',reason:{kind:'stop'}}})
  assert.equal(out.at(-1).type,'end');bridge.close()
 }
})
