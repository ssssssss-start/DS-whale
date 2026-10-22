import { test } from 'node:test'
import assert from 'node:assert/strict'
import { VoiceCalls } from '../calls.js'
import { NativeCall } from '../native-call.js'
import { createBridge } from '../index.js'

function fixture() {
  let now = 1000
  const sent = [], submissions = []
  const calls = new VoiceCalls({send:m => {sent.push(m);return true},cancel:() => {},clock:() => now})
  calls.receive({type:'desktop_state',voiceProtocol:1,voiceReady:true})
  const service = {catalog:() => ({selection:{providerId:'mock-local',language:'auto'},providers:[{id:'mock-local',preparation:{phase:'ready'}}]}),
    async transcribe(request,signal) { assert.equal(request.providerId,'mock-local'); assert.equal(Buffer.from(request.audioBase64,'base64').toString('ascii',0,4),'RIFF'); signal.throwIfAborted(); return {text:'你好，向我挥挥手。'} }}
  const native = new NativeCall({calls,send:m => sent.push(m),target:async () => 'selected-session',speech:() => service,
    submit:async (sessionId,text,signal) => { signal.throwIfAborted(); assert.equal(calls.call.input,'asr'); assert.equal(calls.call.prepared,true); submissions.push({sessionId,text}) },clock:() => now})
  calls.onChange = () => native.sync()
  const command = (action,extra = {}) => native.receive({type:'native_call',token:'desktop-token',action,...extra})
  async function start() { await command('start'); calls.receive({type:'call_state',id:native.id,phase:'ready'}) }
  async function audio() {
    await command('audio_begin',{recording:'recording-1'})
    const wav = Buffer.alloc(3244); wav.write('RIFF'); wav.write('WAVE',8)
    await command('audio_chunk',{recording:'recording-1',seq:0,data:wav.toString('base64')})
    return command('audio_end',{recording:'recording-1'})
  }
  return {calls,native,service,sent,submissions,command,start,audio,advance:ms => {now += ms}}
}

test('desktop-only call transcribes through public speech service and submits once to its Harness session',async () => {
  const f = fixture(); await f.start()
  assert.equal(f.calls.sessionId,'selected-session')
  await f.command('input_state',{phase:'listening'})
  assert.equal(f.calls.call.inputPhase,'listening')
  await f.audio()
  assert.deepEqual(f.submissions,[{sessionId:'selected-session',text:'你好，向我挥挥手。'}])
  assert.ok(f.sent.some(m => m.type === 'native_state' && m.phase === 'transcribing'))
  assert.equal(f.calls.call.phase,'waiting')
  const bridge = createBridge(m => {f.calls.track(m);f.sent.push(m)},Date.now,id => f.calls.reads(id),id => f.calls.callId(id))
  const session = {id:f.calls.sessionId}
  bridge(session,{type:'user/message',data:{turn:1,source:{kind:'user'},content:[{type:'text',text:f.submissions[0].text}]}})
  const turn = f.calls.call.turn
  bridge.stream({agent:{session},frame:{type:'chunk',chunk:{type:'text-delta',text:'听到了，我向你挥挥手。'}}})
  assert.equal(f.calls.call.phase,'generating')
  f.calls.receive({type:'call_state',id:f.native.id,turn,phase:'speaking'})
  bridge(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
  assert.equal(f.calls.call.phase,'speaking','agent completion cannot open microphone before audio drains')
  f.calls.receive({type:'call_state',id:f.native.id,turn,phase:'finished'})
  assert.equal(f.sent.at(-1).phase,'finished')
  await f.command('ping')
  assert.equal(f.sent.at(-1).phase,'finished','heartbeat acknowledges the current state without resetting it')
  await f.command('end'); assert.equal(f.calls.call,null); assert.equal(f.native.token,null)
  bridge.close()
})

test('hangup and pause discard a late recognizer result even if its provider ignores cancellation',async () => {
  for (const action of ['pause','end']) {
    const f = fixture(); await f.start()
    let resolve, signal
    f.service.transcribe = async (_request,s) => {signal = s;return new Promise(done => {resolve = done})}
    const pending = f.audio()
    while (!resolve) await new Promise(done => setImmediate(done))
    await f.command(action)
    assert.equal(signal.aborted,true)
    resolve({text:'迟到的语音不应发送。'}); await pending
    assert.equal(f.submissions.length,0)
    assert.equal(f.native.upload,null)
    if (action === 'pause') assert.equal(f.calls.call.phase,'paused')
  }
})

test('no speech, unsupported recognizer, browser contention and cancelled startup never create a ghost call',async () => {
  const f = fixture()
  f.service.catalog = () => ({selection:{providerId:'mock-local'},providers:[]})
  await f.command('start'); assert.equal(f.calls.call,null); assert.equal(f.sent.at(-1).phase,'failed')
  const browser = fixture(); await browser.calls.handle({action:'call_start',sessionId:'browser'},async () => {})
  const browserId = browser.calls.call.id
  await browser.command('start'); assert.equal(browser.calls.call.id,browserId)
  const late = fixture(); let resolve
  late.native.target = () => new Promise(done => {resolve = done})
  const starting = late.command('start'); await late.command('end'); resolve('selected-session'); await starting
  assert.equal(late.calls.call,null)
  const paused = fixture(); let select
  paused.native.target = () => new Promise(done => {select = done})
  const pendingStart = paused.command('start'); await paused.command('pause'); select('selected-session'); await pendingStart
  assert.equal(paused.calls.call,null,'pausing setup cannot open the microphone later')
  const empty = fixture(); empty.service.transcribe = async () => ({text:'   '}); await empty.start(); await empty.audio()
  assert.equal(empty.calls.call.phase,'ready'); assert.equal(empty.submissions.length,0)
  await empty.command('start'); assert.equal(empty.calls.call.phase,'ready','duplicate start is idempotent')
  empty.native.close(); browser.calls.end()
})

test('invalid chunks, oversized or stalled recordings pause safely; foreign tokens cannot stop a call',async () => {
  const f = fixture(); await f.start()
  await f.native.receive({type:'native_call',token:'other',action:'end'})
  assert.ok(f.calls.call)
  await f.command('audio_begin',{recording:'r'})
  await f.command('audio_chunk',{recording:'r',seq:1,data:'AA=='})
  assert.equal(f.calls.call.phase,'failed'); assert.equal(f.native.upload,null)
  await f.command('resume'); f.calls.receive({type:'call_state',id:f.native.id,phase:'ready'})
  await f.command('audio_begin',{recording:'r2'})
  f.advance(5001); f.native.tick()
  assert.equal(f.calls.call.phase,'failed'); assert.equal(f.submissions.length,0)
  await f.command('resume'); f.calls.receive({type:'call_state',id:f.native.id,phase:'ready'})
  await f.command('audio_begin',{recording:'oversized'})
  for (let seq=0;seq<21;seq++) await f.command('audio_chunk',{recording:'oversized',seq,data:Buffer.alloc(32000).toString('base64')})
  assert.equal(f.calls.call.phase,'failed'); assert.equal(f.native.upload,null)
  f.native.close()
})
