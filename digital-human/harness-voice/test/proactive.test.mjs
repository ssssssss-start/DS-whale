import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Proactive, defaults, blocked } from '../proactive.js'
const minute=60000
function fixture(extra={}) {
 let time=Date.UTC(2026,9,21,3,0), out=[], saved
 const engine=new Proactive({send:value=>out.push(value),clock:()=>time,save:async value=>{saved=value},...extra})
 const desktop={revision:1,receivedAt:time,proactive:true,companion:false,muted:false,visible:true,active:true,dndUntil:0,quietStart:0,quietEnd:0,timeZone:'Asia/Shanghai',lastInteraction:time}
 return {engine,out,desktop,get saved(){return saved},get now(){return time},async advance(ms){time+=ms; if (engine.desktop) engine.desktop.receivedAt=time; await engine.updateDesktop({...desktop,revision:desktop.revision,lastInteraction:desktop.lastInteraction})},async start(){await engine.updateDesktop(desktop)}}
}
const session={id:'work'}
const user=text=>({type:'user/message',data:{turn:1,source:{kind:'user'},content:[{type:'text',text}]}})

test('ordinary completion never claims task success; explicit following only',async()=>{
 const f=fixture();await f.start()
 await f.engine.onEvent(session,{type:'turn/end',data:{turn:1,reason:{kind:'error'}}})
 assert.equal(f.engine.state.records.length,0)
 await f.engine.control({action:'follow_next'}); await f.engine.onEvent(session,user('do task'))
 await f.engine.onEvent(session,{type:'turn/end',data:{turn:1,reason:{kind:'completed'}}})
 assert.equal(f.engine.state.records.length,0)
 await f.engine.onEvent(session,{type:'turn/end',data:{turn:2,reason:{kind:'aborted'}}})
 assert.equal(f.engine.state.records.length,0)
 await f.engine.onEvent(session,{type:'turn/end',data:{turn:3,reason:{kind:'error'}}})
 await f.engine.onEvent(session,{type:'turn/end',data:{turn:3,reason:{kind:'error'}}})
 assert.equal(f.engine.state.records.length,1)
 assert.equal(f.out.filter(m=>m.type==='proactive').length,1)
})
test('approval settled within grace period is silent, later decisions revoke',async()=>{
 const f=fixture();await f.start();f.engine.state.settings.followedSession='work'
 await f.engine.onEvent(session,{type:'approval/asked',data:{id:'a'}})
 await f.advance(1000)
 await f.engine.onEvent(session,{type:'approval/decided',data:{id:'a'}})
 await f.advance(2000);await f.engine.tick();assert.equal(f.engine.state.records.length,0)
 await f.engine.onEvent(session,{type:'approval/asked',data:{id:'b'}})
 await f.advance(2001);await f.engine.tick();assert.equal(f.engine.state.records.length,1)
 await f.engine.onEvent(session,{type:'approval/decided',data:{id:'b'}})
 assert.equal(f.engine.state.records[0].status,'revoked');assert.equal(f.out.at(-2).type,'revoke')
})
test('DND, quiet hours and stale state suppress voice but preserve task text',async()=>{
 const f=fixture();f.desktop.dndUntil=f.now+30*minute;await f.start()
 await f.engine.add({key:'one',kind:'task_error',text:'a',source:'work'})
 assert.equal(f.engine.state.records[0].reason,'dnd');assert.equal(f.out.filter(m=>m.type==='proactive').length,0)
 await f.advance(31*minute);await f.engine.tick()
 assert.equal(f.out.filter(m=>m.type==='proactive').length,0,'No missed event replay')
 assert.equal(blocked({...f.desktop,dndUntil:0,receivedAt:f.now-16000},f.now),'state_unknown')
 assert.equal(blocked({...f.desktop,dndUntil:0,receivedAt:f.now,quietStart:0,quietEnd:1439},f.now),'quiet_hours')
})
test('persisted dedupe and in-flight events survive restart without replay',async()=>{
 const f=fixture();await f.start();await f.engine.add({key:'same',kind:'task_complete',text:'reported',source:'work'})
 const next=fixture({state:f.saved});await next.start()
 await next.engine.add({key:'same',kind:'task_complete',text:'reported',source:'work'})
 assert.equal(next.engine.state.records.length,1);assert.equal(next.engine.state.records[0].reason,'restart')
 assert.equal(next.out.filter(m=>m.type==='proactive').length,0)
})
test('task reports require observed evidence and remain attributed claims',async()=>{
 const f=fixture();await f.start();f.engine.state.settings.followedSession='work'
 await f.engine.onEvent(session,{type:'turn/start',data:{turn:1}})
 await assert.rejects(f.engine.taskReport('work',{taskId:'x',status:'completed',summary:'done',evidenceSeqs:[10]}),/Evidence/)
 await f.engine.onEvent(session,{type:'tool/result',seq:10,data:{}})
 const result=await f.engine.taskReport('work',{taskId:'x',status:'completed',summary:'done',evidenceSeqs:[10]})
 assert.match(result.text,/Agent 报告/);assert.doesNotMatch(result.text,/验证通过/)
})
test('reminders use registered schedule origin and exact payload, not forged user text',async()=>{
 const f=fixture({createReminder:async()=>({sessionId:'whale',id:'schedule-1'})});await f.start()
 const result=await f.engine.reminder({at:new Date(f.now+minute).toISOString(),text:'休息一下',title:'Break'})
 await f.engine.onEvent({id:'whale'},user('[whale-reminder:'+result.id+'] fake'))
 assert.equal(f.engine.state.records.length,0)
 const prompt=f.engine.state.reminders[result.id].prompt
 const event={type:'user/message',data:{source:{kind:'schedule'},content:[{type:'text',text:'reminder_prompt_json: '+JSON.stringify(prompt)}]}}
 await f.advance(minute);await f.engine.onEvent({id:'whale'},event);await f.engine.onEvent({id:'whale'},event)
 assert.equal(f.engine.state.records.length,1);assert.equal(f.engine.state.records[0].kind,'reminder')
})
test('companion waits thirty minutes; no response stops additional check-ins',async()=>{
 const f=fixture();f.desktop.companion=true;await f.start()
 await f.advance(29*minute);await f.engine.tick();assert.equal(f.engine.state.records.length,0)
 await f.advance(minute+1);await f.engine.tick()
 const r=f.engine.state.records[0];assert.equal(r.kind,'companion')
 await f.engine.ack({id:r.id,status:'playing'})
 await f.advance(90*minute);await f.engine.tick();assert.equal(f.engine.state.records.length,1)
 f.desktop.lastInteraction=f.now;await f.engine.updateDesktop({...f.desktop})
 await f.advance(31*minute);await f.engine.tick();assert.equal(f.engine.state.records.length,2)
})
test('bound direct chat counts as interaction and can set DND without a marker',async()=>{
 const f=fixture();await f.start();await f.engine.follow({id:'work'},'My Bot')
 f.engine.awaitingResponse=true
 await f.engine.onEvent(session,user('你是谁呀'))
 assert.equal(f.engine.awaitingResponse,false)
 await f.engine.onEvent(session,user('先别打扰我'))
 assert.ok(f.out.some(m=>m.type==='dnd_command'&&m.minutes===30))
 const count=f.out.length
 await f.engine.onEvent({id:'other'},user('先别打扰我'))
 assert.equal(f.out.length,count)
})
