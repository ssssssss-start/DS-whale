import { randomUUID } from 'node:crypto'

export const bodyActions = ['idle', 'greeting', 'poke', 'headpat', 'shy', 'surprised', 'sad', 'sleepy', 'turn', 'walk', 'tail_swish']

export class Embodiment {
  constructor({ send, owner, call, clock = Date.now, timeout = 2000 }) {
    this.send = send; this.owner = owner; this.call = call; this.clock = clock; this.timeout = timeout
    this.desktop = {}; this.receivedAt = -Infinity; this.pending = new Map()
  }
  receive(message) {
    if (message.type === 'desktop_state') {
      this.desktop = { bodyProtocol: message.bodyProtocol, visible: message.visible === true, active: message.active === true,
        actions: Array.isArray(message.bodyActions) ? bodyActions.filter(a => message.bodyActions.includes(a)) : [] }
      this.receivedAt = this.clock()
    }
    if (message.type === 'body_result') {
      const request = this.pending.get(message.id)
      if (!request || message.action !== request.action) return
      const status = ['accepted', 'busy', 'unavailable', 'unsupported', 'expired'].includes(message.status) ? message.status : 'unavailable'
      request.finish({ action: request.action, status })
    }
  }
  state(sessionId) {
    if (!sessionId || sessionId !== this.owner()) throw new Error('This session does not own the Whale body. Bind it or start a Whale call first.')
    const connected = this.clock() - this.receivedAt <= 6000 && this.desktop.bodyProtocol === 1
    const call = this.call()
    return { body: 'Whale Companion', connected, available: connected && this.desktop.visible && this.desktop.active,
      actions: connected ? this.desktop.actions : [], hearing: call?.sessionId === sessionId && call.input === 'asr' ? 'asr_transcript' : 'text_or_unknown',
      communication: call?.sessionId === sessionId ? {phase:call.phase,microphone:call.inputPhase === 'listening' && ['ready','finished'].includes(call.phase) ? 'listening' : 'off'} : null }
  }
  prompt(sessionId) {
    if (!sessionId || sessionId !== this.owner()) return ''
    const state = this.state(sessionId)
    return [
      '## Your hearing and digital body',
      'Whale Companion (鲸鱼娘) is your digital body for this conversation. Keep your existing name, role and responsibilities; express yourself through this body in the first person.',
      'You can hear the user through speech recognition: the voice input channel turns their speech into text you understand. Naturally say “I heard you” when speech input is confirmed; do not deny hearing merely because the model receives a transcript.',
      'ASR provides words, not raw sound. Do not invent tone, pitch, background sounds or continuous listening. Text or unknown input is not evidence that the user spoke. Ask about a possible recognition error when needed.',
      'Use whale_body to perform your available movements and expressions, rather than only narrating them. It is appropriate to choose a fitting expression while talking. Every action must be supported by the current body; future joints or motions become controllable only after implementation and capability registration.',
      'An accepted receipt means the body accepted the movement, not that the animation finished. Busy, offline, hidden or expired results are not successful movement. Do not pretend a failed action occurred. Body actions are silent and do not interrupt your spoken reply.',
      `Current body and input state: ${JSON.stringify(state)}`,
    ].join('\n')
  }
  async execute(action, sessionId, signal) {
    const state = this.state(sessionId)
    if (action === 'status') return state
    if (!state.available) throw new Error('The Whale body is offline, hidden or inactive.')
    if (!bodyActions.includes(action) || !state.actions.includes(action)) throw new Error('This movement is not supported by the connected Whale body.')
    if (signal?.aborted) throw new Error('Body action cancelled.')
    if (this.pending.size) throw new Error('Another body command is awaiting its receipt.')
    const id = randomUUID()
    return new Promise((resolve, reject) => {
      let timer
      const abort = () => finish(null, new Error('Body action cancelled; movement is unconfirmed.'))
      const finish = (result, error) => {
        clearTimeout(timer); signal?.removeEventListener('abort', abort); this.pending.delete(id)
        if (error) reject(error)
        else if (sessionId !== this.owner()) reject(new Error('Body ownership changed; movement is unconfirmed.'))
        else resolve(result)
      }
      this.pending.set(id, { action, finish })
      timer = setTimeout(() => finish(null, new Error('No body receipt arrived; movement is unconfirmed.')), this.timeout)
      signal?.addEventListener('abort', abort, { once: true })
      try {
        if (!this.send({ type: 'body_action', id, action, expiresAt: this.clock() + this.timeout })) finish(null, new Error('The Whale body is disconnected.'))
      } catch { finish(null, new Error('The Whale body is disconnected.')) }
    })
  }
  close() {
    for (const request of this.pending.values()) request.finish(null, new Error('Body control stopped; movement is unconfirmed.'))
  }
}
