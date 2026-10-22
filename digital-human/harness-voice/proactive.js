import { randomUUID } from 'node:crypto'

export const defaults = () => ({ version: 1, settings: { followedSession: null, followNext: false }, records: [], reminders: {}, companionSession: null })
export function dndCommand(text) {
  const body = text.replace(/^\[whale\]\s*/, '').trim()
  if (/^(?:关闭免打扰|恢复主动提醒)[。！!\s]*$/.test(body)) return 0
  if (!/^(?:先别打扰(?:我)?|(?:开启)?免打扰|(?:半小时|一个小时|30\s*分钟|1\s*小时)内不要主动说话)(?:$|[，,。！!\s]|\d)/.test(body)) return null
  return /持续|一直|直到.*关闭/.test(body) ? -1 : /一个小时|一小时|1\s*小时|60\s*分钟/.test(body) ? 60 : 30
}

export const textOf = content => (Array.isArray(content) ? content : []).filter(p => p.type === 'text').map(p => p.text).join('\n')
const minute = 60_000

export function quietNow(state, now) {
  try {
    const parts = new Intl.DateTimeFormat('en-GB', { timeZone: state.timeZone || 'Asia/Shanghai', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(now))
    const time = Number(parts.find(p => p.type === 'hour').value) * 60 + Number(parts.find(p => p.type === 'minute').value)
    const a = state.quietStart ?? 1380, b = state.quietEnd ?? 540
    return a === b ? false : a < b ? time >= a && time < b : time >= a || time < b
  } catch { return true }
}
export function blocked(state, now) {
  if (!state || now - state.receivedAt > 15_000) return 'state_unknown'
  if (!state.proactive) return 'proactive_off'
  if (state.muted) return 'muted'
  if (!state.visible) return 'hidden'
  if (!state.active) return 'device_inactive'
  if (state.dndUntil === -1 || state.dndUntil > now) return 'dnd'
  if (quietNow(state, now)) return 'quiet_hours'
  return null
}

export class Proactive {
  constructor({ state = defaults(), save = async () => {}, send, clock = Date.now, createReminder, makeCompanion, resolveSession }) {
    this.state = { ...defaults(), ...state, settings: { ...defaults().settings, ...state.settings } }
    this.save = save; this.send = send; this.clock = clock; this.createReminder = createReminder; this.makeCompanion = makeCompanion
    this.resolveSession = resolveSession
    this.desktop = null; this.busy = new Set(); this.approvals = new Map(); this.jobs = new Map(); this.tools = new Map()
    this.closed = false; this.checkInArmed = false; this.companionCandidate = null; this.observationSince = clock(); this.lastInteraction = clock(); this.lastProactive = clock()
    this.lastCheckIn = state.settings?.lastCheckIn || 0; this.awaitingResponse = !!state.settings?.awaitingResponse; this.lastCompanionPoll = 0
    // Interrupted voice is never replayed after restart. Its text remains unread.
    for (const r of this.state.records) if (['queued','playing','synthesizing'].includes(r.status)) { r.status = 'text_only'; r.reason = 'restart' }
  }
  async persist() { await this.save(structuredClone(this.state)) }
  snapshot() {
    return { type: 'inbox', followedSession: this.state.settings.followedSession, followedTitle: this.state.settings.followedTitle || null, followNext: this.state.settings.followNext,
      messages: this.state.records.slice(-80).reverse().map(({ id, text, status, reason, source, kind, at, read }) => ({ id, text, status, reason, source, kind, at, read: !!read })) }
  }
  async publish() { await this.persist(); if (!this.closed) this.send(this.snapshot()) }
  async updateDesktop(value) {
    if (!Number.isFinite(value.revision) || (this.desktop && value.revision < this.desktop.revision)) return
    const before = this.desktop
    this.desktop = { ...value, receivedAt: this.clock() }
    if (value.lastInteraction > (this.state.settings.lastInteraction || 0)) { this.interact(value.lastInteraction); await this.persist() }
    if (before && blocked(before, before.receivedAt) && !blocked(this.desktop, this.clock())) this.observationSince = this.clock()
    if (!value.companion || blocked(this.desktop, this.clock())) this.checkInArmed = false
    if (!before || value.revision !== before.revision) this.send(this.snapshot())
  }
  interact(time = this.clock()) {
    this.lastInteraction = Math.max(this.lastInteraction, time); this.state.settings.lastInteraction = time; this.awaitingResponse = false; this.state.settings.awaitingResponse = false; this.checkInArmed = false; this.observationSince = this.clock()
  }
  async add({ key, kind, text, source, priority = 2, expiresAt = this.clock() + 10 * minute }) {
    if (this.closed || this.state.records.some(r => r.key === key)) return null
    const r = { id: randomUUID(), key, kind, text, source, priority, at: this.clock(), expiresAt, status: 'pending', read: false }
    this.state.records.push(r)
    // Bound functional message storage while retaining a durable, recent dedupe history.
    if (this.state.records.length > 500) this.state.records.splice(0, this.state.records.length - 500)
    const reason = expiresAt <= this.clock() ? 'expired' : blocked(this.desktop, this.clock())
    if (reason) { r.status = 'text_only'; r.reason = reason }
    else { r.status = 'queued' }
    await this.publish()
    if (r.status === 'queued') this.send({ type: 'proactive', event: r })
    return r
  }
  async revoke(key) {
    const r = this.state.records.find(r => r.key === key)
    if (!r || r.status === 'revoked') return
    r.status = 'revoked'; r.reason = 'no_longer_pending'
    this.send({ type: 'revoke', id: r.id }); await this.publish()
  }
  async ack(a) {
    const r = this.state.records.find(r => r.id === a.id)
    if (!r) return
    if (r.status === 'revoked') return
    if (['queued','synthesizing','playing','finished','cancelled','dropped','failed'].includes(a.status)) {
      if (a.status === 'playing' && r.playedAt == null) {
        r.playedAt = this.clock(); this.lastProactive = this.clock()
        if (r.kind === 'companion') { this.lastCheckIn = this.clock(); this.state.settings.lastCheckIn = this.lastCheckIn; this.awaitingResponse = true; this.state.settings.awaitingResponse = true }
      }
      r.status = a.status; r.reason = String(a.reason || '').slice(0, 100)
      await this.publish()
    }
  }
  binding() {
    const { followedSession, followedTitle, followNext } = this.state.settings
    return { sessionId: followedSession, title: followedTitle || null, followNext }
  }
  async follow(session, title) {
    if (this.state.settings.followedSession !== session.id) {
      for (const r of this.state.records.filter(r => r.kind !== 'reminder' && ['pending','queued','synthesizing','playing'].includes(r.status))) await this.revoke(r.key)
      this.approvals.clear(); this.jobs.clear(); this.busy.clear(); this.tools.clear()
      if (session.running) this.busy.add(session.id)
    }
    this.state.settings.followedSession = session.id
    this.state.settings.followedTitle = String(title || session.id).slice(0, 160)
    this.state.settings.followNext = false
    await this.publish()
    return this.binding()
  }
  async control(message) {
    switch (message.action) {
      case 'follow_next': this.state.settings.followNext = true; break
      case 'unfollow':
        this.state.settings.followNext = false; this.state.settings.followedSession = null; this.state.settings.followedTitle = null
        for (const r of this.state.records.filter(r => r.kind !== 'reminder' && ['pending','queued','synthesizing','playing'].includes(r.status))) await this.revoke(r.key)
        this.approvals.clear(); this.jobs.clear(); this.busy.clear(); this.tools.clear(); break
      case 'mark_read': { const r = this.state.records.find(r => r.id === message.id); if (r) r.read = true; break }
      case 'stop':
        for (const r of this.state.records) if (['queued','synthesizing','playing'].includes(r.status)) { r.status = 'cancelled'; r.reason = 'user_stop' }
        this.checkInArmed = false; this.observationSince = this.clock(); break
      default: return
    }
    await this.publish()
  }
  async userCommand(session, text) {
    const direct = session.id === this.state.settings.followedSession || text.startsWith('[whale]')
    if (direct) this.interact()
    if (session.id === this.state.companionSession || direct) {
      const minutes = dndCommand(text)
      if (minutes != null) { this.send({ type:'dnd_command', minutes }); return true }
    }
    return false
  }
  async onEvent(session, event) {
    if (this.closed) return
    const id = session?.id, data = event.data || {}, now = this.clock()
    if (!id) return
    if (event.type === 'user/message' && data.source?.kind === 'user') {
      const text = textOf(data.content)
      if (this.state.settings.followNext && id !== this.state.companionSession) {
        const listed = await this.resolveSession?.(id)
        await this.follow({ id, running:true }, listed?.title)
        this.busy.add(id); this.tools.set(id, new Set())
      }
      await this.userCommand(session, text)
    }
    if (event.type === 'user/message' && data.source?.kind === 'schedule' && id === this.state.companionSession) {
      const raw = textOf(data.content)
      const one = /^reminder_prompt_json: (.*)$/m.exec(raw), batch = /^reminders_json: (.*)$/m.exec(raw)
      let prompts = []
      try { if (one) prompts = [{ reminder_prompt:JSON.parse(one[1]), occurrence_at:/^occurrence_at: (.*)$/m.exec(raw)?.[1] }]; if (batch) prompts = JSON.parse(batch[1]) } catch { return }
      for (const entry of prompts) {
        const prompt = entry.reminder_prompt
        const match = typeof prompt === 'string' && /^\[whale-reminder:([\w-]+)\]/.exec(prompt)
        const reminder = match && this.state.reminders[match[1]]
        if (!reminder || reminder.prompt !== prompt) continue
        await this.add({ key: `reminder:${match[1]}:${entry.occurrence_at || reminder.at}`, kind: 'reminder', text: reminder.text, source: id, priority: 1, expiresAt: (Date.parse(entry.occurrence_at) || reminder.at || now) + 5 * minute })
      }
    }
    if (id !== this.state.settings.followedSession || id === this.state.companionSession) return
    if (event.type === 'session/title' && typeof data.title === 'string') {
      this.state.settings.followedTitle = data.title.slice(0,160); await this.publish()
    }
    if (event.type === 'turn/start') { this.busy.add(id); this.tools.set(id, new Set()) }
    if (event.type === 'tool/result') this.tools.get(id)?.add(event.seq)
    if (event.type === 'approval/asked') this.approvals.set(`${id}:${data.id}`, { id: data.id, session: id, due: now + 2000 })
    if (event.type === 'approval/decided') {
      this.approvals.delete(`${id}:${data.id}`); await this.revoke(`approval:${id}:${data.id}`)
    }
    if (event.type === 'turn/end') {
      this.busy.delete(id)
      if (data.reason?.kind === 'error') await this.add({ key: `error:${id}:${data.turn}`, kind: 'task_error', text: '刚才关注的那一轮运行出错了，可以到原会话查看原因。', source: id })
      if (['aborted','interrupted'].includes(data.reason?.kind)) {
        for (const a of [...this.approvals.values()]) if (a.session === id) { this.approvals.delete(`${id}:${a.id}`); await this.revoke(`approval:${id}:${a.id}`) }
      }
    }
  }
  async taskReport(sessionId, args) {
    if (sessionId !== this.state.settings.followedSession) throw new Error('Only the followed session can report a result')
    const refs = args.evidenceSeqs || []
    const observed = this.tools.get(sessionId) || new Set()
    if (!refs.length || !refs.every(n => observed.has(n))) throw new Error('Evidence must cite tool/result sequence numbers observed in the current followed turn')
    // Tool records prove provenance, not semantic correctness of the agent's claim.
    return this.add({ key: `report:${sessionId}:${args.taskId}`, kind: args.status === 'completed' ? 'task_complete' : 'task_error',
      text: `Agent 报告：${String(args.summary).slice(0, 120)}。详情和依据请到原会话查看。`, source: sessionId })
  }
  async reminder(args) {
    if (!this.createReminder) throw new Error('Harness schedule service is unavailable')
    const now = this.clock(), at = args.at ? Date.parse(args.at) : null
    let selector
    if (args.at) {
      if (!Number.isFinite(at) || at <= now || at > now + 366 * 24 * 60 * minute) throw new Error('Use a future ISO time with an explicit timezone (within one year)')
      if (!/[zZ]$|[+-]\d\d:\d\d$/.test(args.at)) throw new Error('Time must include an explicit timezone')
      selector = { at: new Date(at).toISOString() }
    } else if (args.dailyTime && /^([01]\d|2[0-3]):[0-5]\d$/.test(args.dailyTime)) {
      const time_zone = args.timeZone || 'Asia/Shanghai'
      new Intl.DateTimeFormat('en',{timeZone:time_zone}).format(new Date(now))
      selector = { daily: { time:args.dailyTime + ':00', time_zone } }
    } else throw new Error('Provide exactly one of at or dailyTime')
    if (args.at && args.dailyTime) throw new Error('Provide only one timing selector')
    const id = randomUUID(), text = String(args.text || '').trim().slice(0, 150)
    if (!text) throw new Error('Reminder text is required')
    const prompt = `[whale-reminder:${id}] ${text}\n这是一条用户约定的提醒。仅简短确认，不调用工具。`
    const result = await this.createReminder({ ...selector, title: String(args.title || 'Whale reminder').slice(0, 120), prompt })
    this.state.companionSession = result.sessionId
    this.state.reminders[id] = { at, text, prompt, scheduleId: result.id, selector }
    await this.publish(); return { id, ...selector }
  }
  async tick() {
    if (this.closed) return
    const now = this.clock()
    for (const a of this.approvals.values()) if (!a.notified && now >= a.due) {
      a.notified = true
      await this.add({ key: `approval:${a.session}:${a.id}`, kind: 'decision', text: '有一步需要你确认，请到原会话处理。', source: a.session, priority: 1, expiresAt: now + 10 * minute })
    }
    if (now - this.lastCompanionPoll < minute) return
    this.lastCompanionPoll = now
    if (!this.desktop?.companion || blocked(this.desktop, now) || this.busy.size || this.desktop.playing || this.awaitingResponse || this.checkInArmed) return
    if (now - Math.max(this.lastInteraction, this.observationSince) < 30 * minute || now - this.lastCheckIn < 60 * minute || now - this.lastProactive < 10 * minute) return
    const date = new Intl.DateTimeFormat('en-CA', { timeZone: this.desktop.timeZone || 'Asia/Shanghai' }).format(new Date(now))
    const count = this.state.records.filter(r => r.kind === 'companion' && r.playedAt && new Intl.DateTimeFormat('en-CA', { timeZone: this.desktop.timeZone || 'Asia/Shanghai' }).format(new Date(r.playedAt)) === date).length
    if (count >= 3) return
    this.checkInArmed = true
    const revision = this.desktop.revision, token = randomUUID()
    const text = this.makeCompanion ? await this.makeCompanion() : '我在这里陪着你呀，需要我的时候叫我就好。'
    if (!text || this.closed || this.desktop.revision !== revision || blocked(this.desktop, this.clock())) return
    await this.add({ key: `companion:${token}`, kind: 'companion', text: String(text).slice(0, 80), source: this.state.companionSession, priority: 3, expiresAt: this.clock() + minute })
  }
  async close() { this.closed = true; await this.persist() }
}
