import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createBindingRoute, findSession } from '../binding.js'
import { Proactive } from '../proactive.js'

const request = body => new Request('http://localhost/api/whale-voice',{method:'POST',body:JSON.stringify(body)})

test('binding route validates inputs and exposes only binding metadata',async()=>{
  const calls=[]
  const route=createBindingRoute({read:async()=>({sessionId:'part-b',title:'Writer'}),bind:async args=>{calls.push(args);return args}})
  assert.equal((await route.fetch(request({action:'state'}))).status,200)
  for (const body of [{action:'delete'},{action:'bind',sessionId:'../private'},{action:'bind',sessionId:'a',title:'line\nbreak'}]) {
    assert.equal((await route.fetch(request(body))).status,400)
  }
  assert.deepEqual(calls,[])
  const result=await (await route.fetch(request({action:'bind',sessionId:'part-b',title:'  Writer  ',other:'ignored'}))).json()
  assert.deepEqual(result,{ok:true,value:{sessionId:'part-b',title:'Writer'}})
  assert.deepEqual(calls,[{sessionId:'part-b',title:'Writer'}])
  const unavailable=createBindingRoute({read:async()=>{throw new Error('private internal details')},bind:async()=>{}})
  const response=await unavailable.fetch(request({action:'state'}))
  assert.equal(response.status,503);assert.doesNotMatch(await response.text(),/private internal/)
})

test('public session list rejects unknown sessions and subagents without activating agents',async()=>{
  const controller={async list(args,signal){assert.deepEqual(args,{});assert.ok(signal instanceof AbortSignal);return {items:[
    {sessionId:'part-b',running:true,projections:{values:{title:'Writer'}}},
    {sessionId:'child',parentSessionId:'part-b'},
  ]}}}
  assert.deepEqual(await findSession(controller,'part-b'),{id:'part-b',running:true,title:'Writer'})
  await assert.rejects(findSession(controller,'missing'),/no longer available/)
  await assert.rejects(findSession(controller,'child'),/no longer available/)
})

test('switching sessions revokes old task audio, preserves reminders and persists the selected title',async()=>{
  const sent=[];let saved
  const engine=new Proactive({send:m=>sent.push(m),save:async value=>{saved=value}})
  await engine.follow({id:'old'},'Old Bot')
  engine.state.records.push({id:'old-report',key:'report:old',kind:'task_complete',status:'playing'},
    {id:'reminder',key:'reminder:one',kind:'reminder',status:'queued'})
  engine.busy.add('old');engine.tools.set('old',new Set([1]));engine.approvals.set('old:a',{})
  const result=await engine.follow({id:'part-b',running:true},'Writer')
  assert.deepEqual(result,{sessionId:'part-b',title:'Writer',followNext:false})
  assert.equal(saved.settings.followedTitle,'Writer')
  assert.equal(engine.state.records[0].status,'revoked');assert.equal(engine.state.records[1].status,'queued')
  assert.deepEqual([...engine.busy],['part-b']);assert.equal(engine.approvals.size,0);assert.equal(engine.tools.size,0)
  assert.ok(sent.some(m=>m.type==='revoke'&&m.id==='old-report'))
  assert.equal(sent.filter(m=>m.type==='proactive'||m.type==='start').length,0,'binding never starts speech')
  engine.tools.set('part-b',new Set([2]))
  await engine.follow({id:'part-b'},'Writer renamed')
  assert.ok(engine.tools.get('part-b').has(2),'rebinding same session keeps observed task evidence')
  await engine.onEvent({id:'part-b'},{type:'session/title',data:{title:'Latest name'}})
  assert.equal(engine.snapshot().followedTitle,'Latest name')
  await engine.control({action:'unfollow'})
  assert.deepEqual(engine.binding(),{sessionId:null,title:null,followNext:false})
  assert.equal(engine.busy.size,0)
})
