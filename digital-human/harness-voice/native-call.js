import { randomUUID } from 'node:crypto'

const validId = id => typeof id === 'string' && /^[\w-]{1,64}$/.test(id)
const MAX_AUDIO = 20 * 32000 + 44

// Audio stays in memory; only the recognized user message enters the normal Session.
export class NativeCall {
  constructor({ calls, send, target, speech, submit, clock = Date.now }) {
    this.calls = calls; this.send = send; this.target = target; this.speech = speech; this.submit = submit; this.clock = clock
    this.token = null; this.id = null; this.upload = null; this.processing = null; this.request = null; this.starting = false; this.closed = false
  }
  status(phase, reason = '') { if (this.token) this.send({type:'native_state',token:this.token,id:this.id,phase,reason}) }
  sync() {
    if (!this.token || this.starting) return
    if (this.calls.call?.id !== this.id) { this.status('closed'); this.clear(); return }
    const c = this.calls.call
    if (['paused','failed','cancelled'].includes(c.phase)) this.discard()
    this.status(this.processing ? 'transcribing' : c.phase, c.reason || '')
  }
  recognizer() {
    const service = this.speech()
    if (!service) throw new Error('Enable Harness Voice Input and prepare its recognition model first.')
    const catalog = service.catalog(), selected = catalog.providers.find(p => p.id === catalog.selection.providerId)
    if (!selected || !['ready','standby'].includes(selected.preparation.phase)) throw new Error('Prepare the selected recognition model in Harness Voice Input first.')
    return {service, selection:catalog.selection}
  }
  async receive(message) {
    if (message.type !== 'native_call' || !validId(message.token) || this.closed) return
    if (message.action === 'start') {
      if (this.token) {
        if (this.token === message.token) this.sync()
        else this.send({type:'native_state',token:message.token,phase:'failed',reason:'Another desktop call is already open.'})
        return
      }
      this.token = message.token; this.starting = true; const token = this.token
      try {
        this.recognizer(); this.calls.ready()
        if (this.calls.call) throw new Error('Another Whale voice call is already open.')
        const sessionId = await this.target()
        if (this.token !== token || this.closed) return
        const state = await this.calls.handle({action:'call_start',sessionId},async () => {})
        if (this.token !== token || this.closed) { if (this.calls.call?.id === state.id) this.calls.end(); return }
        this.id = state.id; this.starting = false; this.sync()
      } catch (error) {
        if (this.token === token) { this.status('failed',error.message === 'Another Whale voice call is already open.' ? error.message : 'Voice is unavailable. Check Harness Voice Input, the selected conversation, Doubao and Sound.'); this.clear() }
      }
      return
    }
    if (message.token !== this.token) return
    if (message.action === 'end') { const id = this.id; this.status('closed'); this.clear(); if (id && this.calls.call?.id === id) this.calls.end(); return }
    if (message.action === 'pause' && this.starting) { this.status('closed'); this.clear(); return }
    if (!this.id || this.calls.call?.id !== this.id) return
    if (message.action === 'audio_begin') {
      if (!['ready','finished'].includes(this.calls.call.phase) || this.processing || this.upload || !validId(message.recording)) return
      this.upload = {id:message.recording,next:0,bytes:0,chunks:[],at:this.clock(),selection:this.recognizer().selection}
      this.calls.call.inputPhase = 'off'
      return
    }
    if (message.action === 'audio_chunk') {
      const upload = this.upload
      if (!upload || upload.id !== message.recording || message.seq !== upload.next || typeof message.data !== 'string' || message.data.length > 44000) { this.fail(); return }
      const chunk = Buffer.from(message.data,'base64')
      if (!chunk.length || chunk.toString('base64') !== message.data || chunk.length > 32000 || upload.bytes + chunk.length > MAX_AUDIO) { this.fail(); return }
      upload.chunks.push(chunk); upload.bytes += chunk.length; upload.next += 1; return
    }
    if (message.action === 'audio_end') {
      const upload = this.upload; this.upload = null
      if (!upload || upload.id !== message.recording || upload.bytes < 46 || this.processing) { this.fail(); return }
      const token = this.token, id = this.id, controller = new AbortController()
      this.processing = controller; this.request = controller; this.sync()
      const timeout = setTimeout(() => { controller.abort(); if (this.token === token && this.calls.call?.id === id) this.fail() },60000)
      try {
        const {service} = this.recognizer()
        const result = await service.transcribe({audioBase64:Buffer.concat(upload.chunks).toString('base64'),...upload.selection},controller.signal)
        if (controller.signal.aborted || this.token !== token || this.id !== id || this.calls.call?.id !== id) return
        this.processing = null
        const text = typeof result.text === 'string' ? result.text.trim() : ''
        if (!text) { this.sync(); return }
        if (text.length > 12000) throw new Error('Transcript too long')
        await this.calls.handle({action:'call_prepare',id,input:'asr'},async () => {})
        if (controller.signal.aborted || this.token !== token || this.calls.call?.id !== id || this.calls.call.phase !== 'waiting') return
        await this.submit(this.calls.sessionId,text,controller.signal)
      } catch { if (this.token === token && this.calls.call?.id === id && !controller.signal.aborted) this.fail() }
      finally {
        clearTimeout(timeout)
        if (this.request === controller) this.request = null
        if (this.processing === controller) { this.processing = null; if (controller.signal.aborted && this.token === token) this.fail() }
      }
      return
    }
    if (message.action === 'input_state') {
      if (message.phase === 'listening' && ['ready','finished'].includes(this.calls.call.phase)) this.calls.call.inputPhase = 'listening'
      return
    }
    const action = {ping:'call_poll',pause:'call_pause',resume:'call_resume'}[message.action]
    if (action) {
      if (message.action !== 'ping') this.discard()
      try { await this.calls.handle({action,id:this.id},async () => {}); this.sync() }
      catch { this.fail() }
    }
  }
  fail() { this.discard(); if (this.calls.call?.id === this.id) { this.calls.cancel(this.calls.sessionId); this.calls.update('failed','Speech recognition or delivery failed. Check Harness Voice Input and resume the call.'); this.sync() } }
  tick() { if (this.upload && this.clock() - this.upload.at > 5000) this.fail() }
  discard() { this.upload = null; this.request?.abort(); this.request = null; this.processing = null }
  clear() { this.discard(); this.token = null; this.id = null; this.starting = false }
  close() { this.closed = true; const id = this.id; this.status('closed'); this.clear(); if (id && this.calls.call?.id === id) this.calls.end() }
}
