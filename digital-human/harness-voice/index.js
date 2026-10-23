import { dndCommand } from './proactive.js'
import { Phrases } from './phrases.js'
import { connectDesktop } from './transport.js'
import { createBindingRoute, findSession } from './binding.js'
import { VoiceCalls } from './calls.js'
import { Embodiment } from './embodiment.js'
import { NativeCall } from './native-call.js'
import { randomUUID } from 'node:crypto'
import { CompanionLauncher } from './launcher.js'
export { socketPath } from './transport.js'

export const name = 'whale-voice'

export function createBridge(send, clock = Date.now, canRead = () => false, callId = () => null) {
  const turns = new Map()
  const automatic = new Map()
  const finish = turn => {
    if (turn.inputEnded) return
    turn.splitter.push('', true); turn.inputEnded = true
    send({ type:'end', turn:turn.key })
  }
  const handle = (session, event) => {
    const id = session?.id
    if (!id) return
    // Binding opts in to new direct replies, not history, schedules or Bot-to-Bot messages.
    if (event.type === 'user/message') {
      if (event.data?.source?.kind !== 'user') return
      const text = (event.data.content ?? []).filter(p => p.type === 'text').map(p => p.text).join('\n')
      const previous = turns.get(id)
      if (previous) { previous.splitter.cancel(); send({ type: 'cancel', turn: previous.key }); turns.delete(id) }
      const marked = text.trimStart().startsWith('[whale]')
      if ((!marked && !canRead(id)) || (dndCommand(text) != null && !callId(id))) return
      const turn = { key: `${id}:${event.data.turn ?? event.seq}`, startedAt: clock(), index: 0, firstTextAt: null, number:event.data.turn, inputEnded:false, hasTools:false }
      if (marked && !callId(id)) automatic.delete(id)
      else automatic.set(id,turn.key)
      turn.splitter = new Phrases(text => send({ type: 'sentence', turn: turn.key, index: turn.index++, text, firstTextAt: turn.firstTextAt, sentenceAt: clock() }))
      turns.set(id, turn)
      const call = callId(id)
      send({ type: 'start', turn: turn.key, startedAt: turn.startedAt, ...(call ? {callId:call} : {}) })
    }
    const turn = turns.get(id)
    if (!turn || (event.data?.turn != null && turn.number != null && event.data.turn !== turn.number)) return
    if (event.type === 'assistant/chunk' && event.data?.chunk?.type === 'text-delta' && !turn.inputEnded) {
      turn.firstTextAt ??= clock()
      turn.splitter.push(event.data.chunk.text ?? '')
    }
    if (event.type === 'turn/end') {
      const kind = event.data?.reason?.kind
      if (kind === 'error' || kind === 'aborted' || kind === 'cancelled' || kind === 'interrupted') { turn.splitter.cancel(); send({ type: 'cancel', turn: turn.key }) }
      else finish(turn)
      turns.delete(id)
    }
  }
  handle.syncBinding = selectedId => {
    // Keep the key after turn/end so switching also cancels buffered audio still playing.
    for (const [id,key] of automatic) if (id !== selectedId) {
      send({type:'cancel',turn:key}); automatic.delete(id)
      if (turns.get(id)?.key === key) { turns.get(id).splitter.cancel(); turns.delete(id) }
    }
  }
  handle.cancelSession = id => {
    const keys = new Set()
    for (const [session,key] of automatic) if (id == null || session === id) { keys.add(key); automatic.delete(session) }
    for (const [session,turn] of turns) if (id == null || session === id) {
      turn.splitter.cancel(); keys.add(turn.key); turns.delete(session)
    }
    for (const turn of keys) send({type:'cancel',turn})
  }
  handle.stream = ({ agent, frame }) => {
    const turn = turns.get(agent.session.id)
    if (!turn || (frame.turn != null && turn.number != null && frame.turn !== turn.number)) return
    if (frame.type === 'start') { turn.hasTools = false; turn.attempt = frame.attemptId }
    else if (frame.attemptId && turn.attempt && frame.attemptId !== turn.attempt) return
    if (frame.type === 'chunk') {
      handle(agent.session, { type: 'assistant/chunk', data: { chunk: frame.chunk } })
      if (frame.chunk.type === 'tool-call-delta' || frame.chunk.blockType === 'tool-call' || frame.chunk.block?.type === 'tool-call') turn.hasTools = true
      // A final text response can close TTS before durable projections and turn cleanup.
      // Tool steps remain open: another answer may follow their result.
      if (frame.chunk.type === 'finish' && frame.chunk.reason?.kind === 'stop' && !turn.hasTools) finish(turn)
    }
    if (frame.type === 'end' && frame.outcome.kind === 'committed' && frame.outcome.eventType === 'assistant/message' && !turn.inputEnded) turn.splitter.push('', true)
    if (frame.type === 'end' && (frame.outcome.kind === 'abandoned' || frame.outcome.eventType === 'assistant/attempt')) {
      const turn = turns.get(agent.session.id)
      if (turn) { turn.splitter.cancel(); send({ type: 'cancel', turn: turn.key }); turns.delete(agent.session.id) }
    }
  }
  handle.close = () => { for (const turn of turns.values()) turn.splitter.cancel(); turns.clear() }
  return handle
}

export function apply(ctx, config = {}) {
  let host, disposed = false, chain = Promise.resolve(), hostStatus = 'Waiting for public storage/tools/session services'
  const serialize = work => {
    const result = chain.then(() => { if (disposed) throw new Error('Plugin stopped'); return work() })
    chain = result.catch(() => {})
    return result
  }
  const enqueue = work => serialize(work).catch(() => transport.send({ type:'host_status', text:'Proactive operation failed; check the selected session.' }))
  const transport = connectDesktop(message => {
    calls.receive(message)
    body.receive(message)
    launcher.receive(message)
    if (message.type === 'native_call') void native.receive(message).catch(() => native.fail())
    if (message.type === 'desktop_state') enqueue(async () => { transport.send({type:'host_status',text:hostStatus}); await host?.engine.updateDesktop(message) })
    if (message.type === 'control') enqueue(async () => { await host?.engine.control(message); bridge.syncBinding(calls.sessionId ?? host?.engine.state.settings.followedSession) })
    if (message.type === 'ack') enqueue(() => host?.engine.ack(message))
  })
  const launcher = new CompanionLauncher({send:command => transport.send(command),
    appPath:typeof config.companionPath === 'string' ? config.companionPath : '', autoStart:config.autoStart !== false})
  const calls = new VoiceCalls({send:command => transport.send(command),cancel:id => bridge.cancelSession(id)})
  const native = new NativeCall({ calls, send:command => transport.send(command),
    target:() => { if (!host) throw new Error('Plugin not ready'); return host.nativeTarget() },
    speech:() => ctx.get?.('speechController'),
    submit:(sessionId,text,signal) => host.controller.prompt({requestId:randomUUID(),sessionId,mode:'queue',content:[{type:'text',text}]},signal),
  })
  calls.onChange = () => native.sync()
  const body = new Embodiment({ send: command => transport.send(command),
    owner: () => calls.sessionId ?? host?.engine.state.settings.followedSession, call: () => calls.call })
  const send = command => { calls.track(command); return transport.send(command) }
  const bridge = createBridge(send,Date.now,id => {
    const state = host?.engine.state
    return calls.call ? calls.reads(id) : !!state && id !== state.companionSession && state.settings.followedSession === id
  }, id => calls.callId(id))
  ctx.on('session/event', (session, event) => {
    // Queue both sources together: first-message binding can await storage while live chunks arrive.
    // The observer itself never waits on storage or speech in Harness's agent loop.
    enqueue(async () => {
      await host?.engine.onEvent(session, event)
      bridge.syncBinding(calls.sessionId ?? host?.engine.state.settings.followedSession)
      if (calls.allows(session?.id,event)) bridge(session, event)
    })
  })
  ctx.on('agent/assistant-stream', value => { enqueue(() => { if (calls.allows(value.agent.session.id)) bridge.stream(value) }) })
  const attach = async sub => {
    try {
      const { installHost } = await import('./host.js')
      const installed = await installHost(sub, send, body)
      if (disposed) { await installed.close(); return }
      host = installed
      sub.effect(() => () => { if (host === installed) host = undefined; return installed.close() }, 'whale proactive state')
      hostStatus = 'Proactive plugin ready'
      send({ type:'host_status', text:hostStatus })
    } catch (error) {
      hostStatus = 'Proactive unavailable: ' + (error.code || error.name || 'public API setup failed')
      send({ type:'host_status', text:hostStatus })
    }
  }
  ctx.inject(['storageDomain', 'tools', 'sessionController'], attach)
  ctx.inject(['systemPrompt'], sub => {
    sub.effect(() => sub.systemPrompt.section({ name:'whale-embodiment', order:650, interpolate:false,
      text: context => body.prompt(context?.agent?.session?.id),
    }), 'whale hearing and body context')
  })
  ctx.inject(['connection'], sub => {
    const ready = () => { if (!host) throw new Error('Plugin not ready'); return host }
    sub.effect(() => sub.connection.fetch.register(createBindingRoute({
      read: () => serialize(() => ready().engine.binding()),
      bind: args => serialize(async () => { const result = await ready().bindSession(args); bridge.syncBinding(calls.sessionId ?? result.sessionId); return result }),
      call: body => calls.handle(body, id => findSession(ready().controller,id)),
      desktop: action => action === 'desktop_state' ? launcher.state() : action === 'desktop_toggle' ? launcher.toggle() : launcher.launch(action === 'desktop_autostart'),
    })), 'whale conversation binding route')
  })
  const timer = setInterval(() => { calls.tick(); native.tick(); enqueue(() => host?.engine.tick()) }, 1000)
  timer.unref?.()
  ctx.effect(() => () => { disposed = true; clearInterval(timer); launcher.close(); native.close(); calls.end(); body.close(); bridge.close(); transport.close() }, 'whale voice lifecycle')
}
