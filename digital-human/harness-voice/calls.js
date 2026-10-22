import { randomUUID } from 'node:crypto'

const problem = (message, status = 424) => Object.assign(new Error(message), { status })
const LEASE = 15000

// A call borrows speech without changing the persisted conversation binding.
export class VoiceCalls {
  constructor({ send, cancel, clock = Date.now, onChange = () => {} }) {
    this.send = send; this.cancel = cancel; this.clock = clock
    this.desktopAt = -Infinity; this.desktop = {}; this.call = null; this.revision = 0
    this.onChange = onChange
  }
  get sessionId() { return this.call?.sessionId }
  snapshot() {
    const c = this.call
    return c ? { id:c.id, phase:c.phase, turn:c.turn, revision:this.revision, reason:c.reason || '', text:c.text || '' } : null
  }
  update(phase, reason = '') { this.call.phase = phase; this.call.reason = reason; this.revision += 1; this.onChange() }
  ready() {
    if (this.clock() - this.desktopAt > 6000 || this.desktop.voiceProtocol !== 1) throw problem('Open the updated Whale Companion on the Harness host.')
    if (!this.desktop.voiceReady) throw problem('Configure Doubao voice and enable Sound in Whale Companion.')
  }
  receive(message) {
    if (message.type === 'desktop_state') { this.desktop = { voiceProtocol:message.voiceProtocol, voiceReady:message.voiceReady === true }; this.desktopAt = this.clock(); return }
    const c = this.call
    if (!c || message.type !== 'call_state' || message.id !== c.id) return
    if (message.phase === 'closed') { this.end(); return }
    if (message.phase === 'ready' && c.phase === 'connecting') this.update('ready')
    if (c.phase === 'connecting' && message.phase === 'failed') this.update('failed','Whale voice is unavailable. Open the companion and check Doubao voice and Sound.')
    if (c.turn && message.turn === c.turn && ['speaking','finished','cancelled','failed'].includes(message.phase) && c.phase !== 'paused') {
      this.update(message.phase, message.phase === 'failed' ? 'Whale voice failed. Check Doubao voice access and balance in the companion.' : '')
    }
  }
  reads(id) { return !!this.call && this.call.sessionId === id && (this.call.prepared || !!this.call.turn) && !['paused','failed','cancelled'].includes(this.call.phase) }
  allows(id, event) {
    if (!this.call) return true
    if (id !== this.call.sessionId) return false
    if (event?.type === 'user/message' && event.data?.source?.kind !== 'user') return false
    // An out-of-band message must not make the whale speak into an open mic.
    if (event?.type === 'user/message' && !this.call.prepared) {
      this.cancel(id); this.call.turn = null; this.call.input = null; this.update('cancelled'); return false
    }
    return this.reads(id)
  }
  callId(id) { return this.reads(id) ? this.call.id : null }
  track(command) {
    if (this.call && command.type === 'start' && command.callId === this.call.id) {
      this.call.turn = command.turn; this.call.text = ''; this.call.prepared = false; this.update('generating')
    }
    if (this.call?.turn && command.type === 'sentence' && command.turn === this.call.turn) {
      this.call.text = ((this.call.text || '') + command.text).slice(-8000); this.revision += 1
    }
  }
  async handle(body, validate) {
    this.tick()
    if (body.action === 'call_start') {
      if (this.call) throw problem('Another Whale voice call is already open.',409)
      this.ready()
      await validate(body.sessionId)
      // Session validation yields; another tab may have acquired the call meanwhile.
      if (this.call) throw problem('Another Whale voice call is already open.',409)
      this.ready(); this.cancel(null)
      this.call = { id:randomUUID(), sessionId:body.sessionId, turn:null, prepared:false, touched:this.clock(), created:this.clock() }
      this.update('connecting')
      if (!this.send({type:'call_open',id:this.call.id})) { this.call = null; throw problem('Whale Companion is disconnected.') }
      return this.snapshot()
    }
    const c = this.call
    if (!c || body.id !== c.id) throw problem('This Whale voice call has ended. Close the call and try again.',410)
    if (body.action === 'call_end') { this.end(); return { ended:true } }
    c.touched = this.clock()
    if (!this.send({type:'call_ping',id:c.id})) { this.end(); throw problem('Whale Companion is disconnected.') }
    if (body.action === 'call_pause') {
      this.cancel(c.sessionId); c.turn = null; c.prepared = false; c.input = null; this.update('paused')
      this.send({type:'call_pause',id:c.id})
    } else if (body.action === 'call_resume') {
      this.ready(); c.turn = null; c.prepared = false; c.input = null; c.created = this.clock(); this.update('connecting'); this.send({type:'call_resume',id:c.id})
    } else if (body.action === 'call_prepare') {
      this.ready()
      if (c.phase !== 'ready' && c.phase !== 'finished') throw problem('Resume the call before speaking again.',409)
      this.cancel(c.sessionId); c.turn = null; c.text = ''; c.prepared = true; c.input = body.input === 'asr' ? 'asr' : null; this.update('waiting')
      this.send({type:'call_prepare',id:c.id})
    } else if (body.action !== 'call_poll') throw problem('Unknown call action.',400)
    return this.snapshot()
  }
  tick() {
    if (this.call?.phase === 'connecting' && this.clock() - this.call.created > 5000) this.update('failed','Whale voice is unavailable. Open the companion and check Doubao voice and Sound.')
    if (this.call && (this.clock() - this.call.touched > LEASE || this.clock() - this.desktopAt > 6000)) this.end()
  }
  end() {
    if (!this.call) return
    const c = this.call; this.call = null; this.cancel(c.sessionId); this.send({type:'call_close',id:c.id}); this.onChange()
  }
}
