import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { Context } from '@deepseek-ai/cordis'
import Storage from '@deepseek-ai/dsh-storage'
import { JsonStorageBackend } from '@deepseek-ai/dsh-storage-json'
import { DomainFacility } from '@deepseek-ai/dsh-storage-domain'
import { installHost } from '../host.js'
import { apply } from '../index.js'
import net from 'node:net'
import { EventEmitter } from 'node:events'

const directory = await mkdtemp(join(tmpdir(),'whale-host-integration-'))
const ctx = new Context()
await ctx.plugin(Storage)
const backend = new JsonStorageBackend(directory)
ctx.storage.backend.register('json',backend)
const facility = new DomainFacility(ctx,{backend:'json',routes:{}})
const tools = new Map(), sent=[], scheduled=[]
const services = {storageDomain:facility, tools:{register(tool){tools.set(tool.name,tool);return()=>tools.delete(tool.name)}},
 sessionController:{async list(){return {items:[{sessionId:'test-work',running:false,projections:{values:{title:'Mock work'}}},{sessionId:'test-call',running:false}]}},async create(args){assert.equal(args.agentPreset,'minimal');return {sessionId:'test-companion'}},async rename(args){assert.equal(args.title,'Whale Companion')}},
 get(name){return name==='schedule'?{async create(session,args){scheduled.push({session,...args});return {id:'test-schedule'}},async delete(){}}:undefined}}
let installed
try {
 installed=await installHost(services,m=>sent.push(m))
 await installed.engine.control({action:'follow_next'})
 await installed.engine.onEvent({id:'test-work'},{type:'user/message',data:{source:{kind:'user'},content:[{type:'text',text:'a mock task'}]}})
 assert.equal(installed.engine.state.settings.followedSession,'test-work')
 assert.equal(installed.engine.binding().title,'Mock work')
 await assert.rejects(installed.bindSession({sessionId:'missing'}),/no longer available/)
 assert.equal((await installed.bindSession({sessionId:'test-work',title:'My Bot'})).title,'My Bot')
 const result=await tools.get('whale_create_reminder').execute({title:'Mock reminder',text:'休息一下',at:new Date(Date.now()+60000).toISOString()},{agent:{session:{id:'test-work'}}})
 assert.equal(JSON.parse(result).id.length,36)
 assert.equal(scheduled.length,1)
 assert.equal(scheduled[0].session,'test-companion')
 const input={type:'user/message',data:{source:{kind:'schedule'},content:[{type:'text',text:`occurrence_at: ${new Date().toISOString()}\nreminder_prompt_json: ${JSON.stringify(scheduled[0].prompt)}`}]}}
 await installed.engine.onEvent({id:'test-companion'},input)
 assert.equal(installed.engine.state.records[0].kind,'reminder')
 await installed.close();installed=null
 const restored=await installHost(services,m=>sent.push(m));installed=restored
 assert.equal(restored.engine.state.records.length,1)
 assert.equal(restored.engine.state.companionSession,'test-companion')
 await restored.engine.onEvent({id:'test-companion'},input)
 assert.equal(restored.engine.state.records.length,1,'durable duplicate is not replayed')
 await installed.close();installed=null
 // No real socket or user desktop is contacted by this event-order regression.
 const createConnection=net.createConnection, writes=[], effects=[], attachments=[], listeners=new Map();let route
 class Socket extends EventEmitter {
  connecting=false;destroyed=false;writableLength=0
  setEncoding(){}
  write(line){writes.push(JSON.parse(line));return true}
  destroy(){this.destroyed=true;this.emit('close')}
 }
 const socket=new Socket()
 net.createConnection=()=>socket
 try {
  const scope={...services,
   connection:{fetch:{register(value){route=value;return()=>{route=null}}}},
   sessionController:{...services.sessionController,async list(...args){await new Promise(resolve=>setTimeout(resolve,20));return services.sessionController.list(...args)}},
   effect(fn){effects.push(fn())},
   on(name,fn){listeners.set(name,fn)},
   inject(names,attach){attachments.push(attach(scope))},
  }
  apply(scope);await Promise.all(attachments)
  socket.emit('data',JSON.stringify({type:'control',action:'unfollow'})+'\n')
  socket.emit('data',JSON.stringify({type:'control',action:'follow_next'})+'\n')
  const session={id:'test-work'}
  assert.equal(listeners.get('session/event')(session,{type:'user/message',data:{turn:5,source:{kind:'user'},content:[{type:'text',text:'hello without a marker'}]}}),undefined)
  listeners.get('agent/assistant-stream')({agent:{session},frame:{type:'chunk',chunk:{type:'text-delta',text:'普通回复直接读。'}}})
  listeners.get('session/event')(session,{type:'turn/end',data:{reason:{kind:'completed'}}})
  const deadline=Date.now()+2000
  while(!writes.some(m=>m.type==='end')&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,5))
  assert.deepEqual(writes.filter(m=>['start','sentence','end'].includes(m.type)).map(m=>m.type),['start','sentence','end'])
  assert.equal(writes.find(m=>m.type==='sentence').text,'普通回复直接读。')
  const fetchRoute=async body=>await (await route.fetch(new Request('http://localhost/api/whale-voice',{method:'POST',body:JSON.stringify(body)}))).json()
  socket.emit('data',JSON.stringify({type:'desktop_state',voiceProtocol:1,voiceReady:true})+'\n')
  const before=await fetchRoute({action:'state'})
  const opened=await fetchRoute({action:'call_start',sessionId:'test-call'})
  assert.equal(opened.ok,true)
  const callId=opened.value.id
  socket.emit('data',JSON.stringify({type:'call_state',id:callId,phase:'ready'})+'\n')
  assert.equal((await fetchRoute({action:'call_prepare',id:callId})).value.phase,'waiting')
  const callSession={id:'test-call'}
  listeners.get('session/event')(callSession,{type:'user/message',data:{turn:6,source:{kind:'user'},content:[{type:'text',text:'hello from call'}]}})
  listeners.get('session/event')(callSession,{type:'user/message',data:{source:{kind:'runtime-context'},content:[{type:'text',text:'mock dynamic context'}]}})
  listeners.get('agent/assistant-stream')({agent:{session:callSession},frame:{type:'chunk',chunk:{type:'text-delta',text:'这是一句通过通话链路的固定测试回复。'}}})
  listeners.get('agent/assistant-stream')({agent:{session:callSession},frame:{type:'chunk',chunk:{type:'finish',reason:{kind:'stop'}}}})
  const callDeadline=Date.now()+1000
  while(!writes.some(m=>m.type==='end'&&m.turn==='test-call:6')&&Date.now()<callDeadline)await new Promise(resolve=>setTimeout(resolve,5))
  assert.equal(writes.filter(m=>m.type==='start'&&m.turn==='test-call:6').length,1)
  assert.equal(writes.find(m=>m.type==='start'&&m.turn==='test-call:6').callId,callId)
  assert.equal(writes.some(m=>m.type==='cancel'&&m.turn==='test-call:6'),false,'runtime context never cancels live call audio')
  const generating=(await fetchRoute({action:'call_poll',id:callId})).value
  assert.equal(generating.phase,'generating')
  assert.equal(generating.text,'这是一句通过通话链路的固定测试回复。')
  socket.emit('data',JSON.stringify({type:'call_state',id:callId,turn:'test-call:6',phase:'finished'})+'\n')
  assert.equal((await fetchRoute({action:'call_poll',id:callId})).value.phase,'finished')
  await fetchRoute({action:'call_end',id:callId})
  assert.deepEqual(await fetchRoute({action:'state'}),before,'calls never change the persisted binding')
  assert.ok(writes.some(m=>m.type==='cancel'&&m.turn==='test-call:6'))
  assert.ok(writes.some(m=>m.type==='call_close'&&m.id===callId))
  console.log('Call integration passed: authenticated public connection route, temporary session speech, stream forwarding once, playback acknowledgement, hangup and unchanged binding (mock desktop).')
  console.log('Event ordering passed: first-message binding waits for public list/storage while immediate live chunks remain ordered; observer returns without blocking.')
 } finally {for(const close of effects.reverse())if(typeof close==='function')await close();net.createConnection=createConnection}
 console.log('Host integration passed: public storage domain + JSON backend, registered tool schema, minimal session creation adapter, schedule dispatch and durable dedupe.')
} finally {
 await installed?.close();await facility.closeAll();await backend.close();await rm(directory,{recursive:true,force:true})
}
