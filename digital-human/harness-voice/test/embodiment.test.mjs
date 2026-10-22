import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Embodiment, bodyActions } from '../embodiment.js'

function fixture(timeout = 100) {
  let now = 1000, owner = 'chosen', call = null
  const sent = []
  const body = new Embodiment({ send: message => { sent.push(message); return true }, owner: () => owner,
    call: () => call, clock: () => now, timeout })
  const desktop = extra => body.receive({ type:'desktop_state', bodyProtocol:1, bodyActions, visible:true, active:true, ...extra })
  desktop()
  return { body, sent, desktop, advance: ms => { now += ms }, owner: value => { owner = value }, call: value => { call = value } }
}

test('body context belongs only to the selected session and distinguishes ASR from typed/unknown input', () => {
  const f = fixture()
  assert.equal(f.body.prompt('other'), '')
  assert.equal(f.body.prompt(undefined), '')
  assert.throws(() => f.body.state('other'), /does not own/)
  assert.equal(f.body.state('chosen').hearing, 'text_or_unknown')
  f.call({ sessionId:'chosen', input:'asr' })
  assert.equal(f.body.state('chosen').hearing, 'asr_transcript')
  const prompt = f.body.prompt('chosen')
  assert.match(prompt, /your digital body/)
  assert.match(prompt, /You can hear the user through speech recognition/)
  assert.match(prompt, /not raw sound/)
  assert.match(prompt, /not that the animation finished/)
  f.owner('call-session')
  assert.equal(f.body.prompt('chosen'), '')
  assert.match(f.body.prompt('call-session'), /digital body/)
  f.advance(6001)
  assert.equal(f.body.state('call-session').connected, false)
  assert.deepEqual(f.body.state('call-session').actions, [])
})

test('body actions require capability, active desktop and matching execution receipt', async () => {
  const f = fixture()
  const pending = f.body.execute('greeting', 'chosen')
  const request = f.sent.at(-1)
  assert.equal(request.type, 'body_action')
  f.body.receive({ type:'body_result', id:'old-request', action:'greeting', status:'accepted' })
  f.body.receive({ type:'body_result', id:request.id, action:'sad', status:'accepted' })
  assert.equal(f.body.pending.size, 1)
  f.body.receive({ type:'body_result', id:request.id, action:'greeting', status:'accepted' })
  assert.deepEqual(await pending, { action:'greeting', status:'accepted' })
  const busy = f.body.execute('headpat', 'chosen'), next = f.sent.at(-1)
  f.body.receive({ ...next, type:'body_result', status:'busy' })
  assert.equal((await busy).status, 'busy')
  f.desktop({ visible:false })
  await assert.rejects(f.body.execute('sad','chosen'), /hidden/)
  f.desktop({ bodyActions:['greeting','fly'] })
  assert.deepEqual(f.body.state('chosen').actions,['greeting'])
  await assert.rejects(f.body.execute('fly','chosen'), /not supported/)
  await assert.rejects(f.body.execute('greeting','other'), /does not own/)
  assert.equal(f.sent.length,2)
})

test('late, missing, aborted, disconnected and reassigned commands never report success', async () => {
  const f = fixture(10)
  await assert.rejects(f.body.execute('greeting','chosen'), /No body receipt/)
  assert.equal(f.body.pending.size,0)
  const abort = new AbortController()
  const stopped = f.body.execute('greeting','chosen',abort.signal)
  abort.abort()
  await assert.rejects(stopped,/cancelled/)
  f.body.receive({ ...f.sent.at(-1), type:'body_result', status:'accepted' })
  const switched = f.body.execute('shy','chosen')
  f.owner('other')
  f.body.receive({ ...f.sent.at(-1), type:'body_result', status:'accepted' })
  await assert.rejects(switched,/ownership changed/)
  f.owner('chosen'); f.body.send = () => false
  await assert.rejects(f.body.execute('idle','chosen'),/disconnected/)
  assert.equal(f.body.pending.size,0)
  f.body.send = () => true
  const disposed = f.body.execute('idle','chosen')
  f.body.close()
  await assert.rejects(disposed,/control stopped/)
})
