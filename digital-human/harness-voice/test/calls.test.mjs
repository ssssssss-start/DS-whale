import { test } from 'node:test'
import assert from 'node:assert/strict'
import { VoiceCalls } from '../calls.js'
import { createBridge } from '../index.js'
import { createBindingRoute } from '../binding.js'

function fixture() {
  let now = 1000
  const sent = [], cancelled = []
  const calls = new VoiceCalls({send:m => {sent.push(m);return true},cancel:id=>cancelled.push(id),clock:()=>now})
  const desktop = () => calls.receive({type:'desktop_state',voiceProtocol:1,voiceReady:true})
  desktop()
  return {calls,sent,cancelled,desktop,advance:ms=>{now+=ms},start:()=>calls.handle({action:'call_start',sessionId:'chosen'},async()=>{})}
}

test('calls require ready companion, validate sessions and never mutate the binding',async()=>{
  const f=fixture();f.calls.desktop.voiceReady=false
  await assert.rejects(f.start(),/Configure Doubao/)
  f.desktop()
  await assert.rejects(f.calls.handle({action:'call_start',sessionId:'missing'},async()=>{throw new Error('missing')}),/missing/)
  const state=await f.start()
  assert.equal(state.phase,'connecting');assert.equal(f.calls.sessionId,'chosen')
  assert.deepEqual(f.cancelled,[null])
  assert.deepEqual(f.sent,[{type:'call_open',id:state.id}])
  await assert.rejects(f.start(),/already open/)
  await assert.rejects(f.calls.handle({action:'call_end',id:'another-tab'}),e=>e.status===410)
  f.calls.receive({type:'call_state',id:state.id,phase:'ready'})
  assert.equal(f.calls.snapshot().phase,'ready')
  await f.calls.handle({action:'call_end',id:state.id})
  assert.equal(f.calls.call,null)
})

test('call streams reply once; only matching audio-drain ack completes it, pause drops late frames',async()=>{
  const f=fixture(),initial=await f.start(),session={id:'chosen'}
  f.calls.receive({type:'call_state',id:initial.id,phase:'ready'})
  const out=[],bridge=createBridge(m=>{out.push(m);f.calls.track(m)},()=>1000,id=>f.calls.reads(id),id=>f.calls.callId(id))
  f.calls.cancel=id=>bridge.cancelSession(id)
  await f.calls.handle({action:'call_prepare',id:initial.id,input:'asr'})
  assert.equal(f.calls.call.input,'asr','only explicitly identified speech is hearing evidence')
  assert.equal(f.sent.at(-1).type,'call_prepare','preconnect on user question, before model text')
  bridge(session,{type:'user/message',data:{turn:1,source:{kind:'user'},content:[{type:'text',text:'hello'}]}})
  bridge.stream({agent:{session},frame:{type:'chunk',chunk:{type:'text-delta',text:'这是一条足够长的流式回复，应该在模型完成之前播放。'}}})
  assert.equal(out[0].callId,initial.id)
  assert.equal(out.filter(m=>m.type==='start').length,1)
  const turn=out[0].turn
  assert.equal(f.calls.snapshot().phase,'generating')
  f.calls.receive({type:'call_state',id:initial.id,turn:'old-turn',phase:'finished'})
  assert.equal(f.calls.snapshot().phase,'generating')
  f.calls.receive({type:'call_state',id:initial.id,turn,phase:'speaking'})
  bridge(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
  assert.equal(f.calls.snapshot().phase,'speaking','model completion does not count as audio completion')
  f.calls.receive({type:'call_state',id:initial.id,turn,phase:'finished'})
  assert.equal(f.calls.snapshot().phase,'finished')
  await f.calls.handle({action:'call_pause',id:initial.id})
  assert.equal(f.calls.call.input,null,'paused input must not keep claiming active speech')
  assert.equal(out.at(-1).type,'cancel','cancel remains possible after model turn ends')
  f.calls.receive({type:'call_state',id:initial.id,turn,phase:'finished'})
  assert.equal(f.calls.snapshot().phase,'paused')
  assert.equal(f.calls.allows('other'),false)
  assert.equal(f.calls.reads('chosen'),false)
  await f.calls.handle({action:'call_resume',id:initial.id})
  assert.equal(f.calls.snapshot().phase,'connecting','resume waits for a fresh desktop handshake')
  f.calls.receive({type:'call_state',id:initial.id,phase:'ready'})
  await f.calls.handle({action:'call_prepare',id:initial.id})
  assert.equal(f.calls.call.input,null,'legacy/unknown input is not silently labeled speech')
  bridge(session,{type:'user/message',data:{turn:2,source:{kind:'user'},content:[{type:'text',text:'先别打扰我'}]}})
  assert.equal(out.at(-1).type,'start','a direct call reply remains usable when setting DND')
  bridge.close();f.calls.end()
})

test('stale desktop or tab releases speech; late status cannot affect a new call',async()=>{
  const f=fixture(),first=await f.start()
  f.advance(16000);f.desktop();f.calls.tick()
  assert.equal(f.calls.call,null)
  assert.equal(f.sent.at(-1).type,'call_close')
  const second=await f.start()
  f.calls.receive({type:'call_state',id:first.id,phase:'ready'})
  assert.equal(f.calls.snapshot().phase,'connecting')
  f.advance(5500);f.desktop();f.calls.tick()
  assert.equal(f.calls.snapshot().phase,'failed','missing native handshake never opens the microphone')
  f.advance(6500);f.calls.tick()
  assert.equal(f.calls.call,null)
  assert.notEqual(first.id,second.id)
})

test('manual or background messages cannot trigger speech while the call microphone is open',async()=>{
  const f=fixture(),state=await f.start()
  f.calls.receive({type:'call_state',id:state.id,phase:'ready'})
  assert.equal(f.calls.allows('chosen',{type:'user/message',data:{source:{kind:'runtime-context'}}}),false)
  assert.equal(f.calls.snapshot().phase,'ready','runtime context is neither speech nor a human interruption')
  assert.equal(f.calls.allows('chosen',{type:'user/message',data:{source:{kind:'user'}}}),false)
  assert.equal(f.calls.snapshot().phase,'cancelled')
  assert.deepEqual(f.cancelled,[null,'chosen'])
})

test('call route validates action/session/token before dispatch and hides private failures',async()=>{
  let dispatch=0
  const route=createBindingRoute({read:()=>{},bind:()=>{},call:async body=>{dispatch++;return {id:body.id,phase:'paused'}}})
  const req=body=>new Request('http://localhost/api/whale-voice',{method:'POST',body:JSON.stringify(body)})
  assert.equal((await route.fetch(req({action:'call_start',sessionId:'../private'}))).status,400)
  assert.equal((await route.fetch(req({action:'call_end',id:123}))).status,400)
  assert.equal(dispatch,0)
  const response=await route.fetch(req({action:'call_pause',id:'mock-call'}))
  assert.equal(response.status,200);assert.equal(dispatch,1)
})
