import { Proactive } from './proactive.js'
import { findSession } from './binding.js'
import { bodyActions } from './embodiment.js'

export async function installHost(ctx, send, body) {
  const [{ defineDomain, domainTable }, { z }, { defineTool }] = await Promise.all([
    import('@deepseek-ai/dsh-storage-domain'), import('zod'), import('@deepseek-ai/dsh-tools'),
  ])
  const spec = defineDomain({ name: 'whale_voice', version: 1, tables: { settings: domainTable(z.object({ value: z.record(z.string(), z.unknown()) })) } })
  const domain = await ctx.storageDomain.open(spec), table = domain.table('settings')
  const state = table.get('current')?.value
  let companion = state?.companionSession
  const ensureCompanion = async () => {
    if (companion) return companion
    const created = await ctx.sessionController.create({ agentPreset: 'minimal' })
    companion = created.sessionId
    await ctx.sessionController.rename({ sessionId: companion, title: 'Whale Companion' })
    engine.state.companionSession = companion
    await engine.persist()
    return companion
  }
  const engine = new Proactive({ state, send, save: value => table.put('current', { value }),
    resolveSession: id => findSession(ctx.sessionController,id),
    createReminder: async args => {
      const service = ctx.get?.('schedule')
      if (!service) throw new Error('Automation tasks are unavailable; enable the Harness schedule service')
      const sessionId = await ensureCompanion()
      const result = await service.create(sessionId, args)
      return { sessionId, id: result.id }
    },
  })
  const output = { schema: { type: 'string' }, render: (_args, value) => [{ type: 'text', text: String(value) }] }
  const register = tool => ctx.tools.register(defineTool({ ...tool, output }))
  const requireSelected = exec => {
    if (!engine.state.settings.followedSession || exec.agent?.session?.id !== engine.state.settings.followedSession) throw new Error('Select this session using Follow Next Conversation in the Whale menu first')
  }
  const disposers = []
  if (body) disposers.push(register({ name:'whale_body', description:'Sense and move your Whale Companion digital body. Use status to inspect connection, hearing input and supported actions. greeting waves hello; poke and headpat perform their reactions; shy, surprised, sad and sleepy show expressions; idle returns to rest. A connected 3D body may also offer turn (one full turn), walk (in place) and tail_swish. Check status before choosing an action. Only the bound session or current Whale call owns this body. Actions are silent; wait for the desktop receipt before describing a movement as accepted. An accepted command does not prove animation completion.',
    parameters:{ action:{type:'string',required:true,enum:['status',...bodyActions]} },
    async execute(args,exec) { return JSON.stringify(await body.execute(args.action,exec.agent?.session?.id,exec.signal)) },
  }))
  disposers.push(register({ name: 'whale_task_evidence', description: 'List tool result sequence ids observed in the current followed task. These references support a whale_report_task claim; they do not prove success.', parameters: {},
    execute(_args, exec) { requireSelected(exec); return JSON.stringify([...engine.tools.get(exec.agent.session.id) || []]) } }))
  disposers.push(register({ name: 'whale_report_task', description: 'Report the followed task result with observed tool/result sequence ids. This is an attributed agent report, not independently verified success. Only report after the requested work is done or terminally failed.',
    parameters: { taskId: { type:'string', required:true }, status: { type:'string', required:true, enum:['completed','failed'] }, summary: { type:'string', required:true }, evidenceSeqs: { type:'array', required:true, items:{type:'number'} } },
    async execute(args, exec) { requireSelected(exec); const r = await engine.taskReport(exec.agent.session.id,args); return JSON.stringify({ recorded:!!r, eventId:r?.id }) } }))
  disposers.push(register({ name: 'whale_create_reminder', description: 'Create one explicitly requested Whale reminder, using the Harness schedule service. Requires the followed user session. Do not create reminders without an explicit user request. The at time must be an ISO date with timezone.',
    parameters: { title:{type:'string',required:true}, text:{type:'string',required:true}, at:{type:'string'}, dailyTime:{type:'string',description:'Daily HH:mm, mutually exclusive with at'}, timeZone:{type:'string',description:'IANA timezone, default Asia/Shanghai'} },
    async execute(args,exec) { requireSelected(exec); return JSON.stringify(await engine.reminder(args)) } }))
  disposers.push(register({ name:'whale_manage_reminders', description:'List or delete Whale-owned reminders on explicit user request. Never manages other reminders.',
    parameters:{action:{type:'string',required:true,enum:['list','delete']},id:{type:'string'}},
    async execute(args,exec) {
      requireSelected(exec)
      if (args.action === 'list') return JSON.stringify(Object.entries(engine.state.reminders).map(([id,r])=>({id,text:r.text,...r.selector})))
      const r = engine.state.reminders[args.id]
      if (!r) throw new Error('Unknown Whale reminder')
      const service = ctx.get?.('schedule'); if (!service) throw new Error('Schedule service unavailable')
      await service.delete({sessionId:engine.state.companionSession,id:r.scheduleId})
      delete engine.state.reminders[args.id]; await engine.persist()
      return 'Deleted'
    } }))
  await engine.persist()
  return { engine, controller:ctx.sessionController,
    async nativeTarget() {
      const selected = engine.state.settings.followedSession || engine.state.nativeSession
      if (selected) {
        const session = await findSession(ctx.sessionController,selected)
        if (session.running) throw new Error('The selected conversation is busy.')
        return session.id
      }
      const created = await ctx.sessionController.create({})
      await ctx.sessionController.rename({sessionId:created.sessionId,title:'Whale Voice Conversation'})
      engine.state.nativeSession = created.sessionId; await engine.persist()
      return created.sessionId
    },
    async bindSession({ sessionId, title }) {
      if (sessionId === engine.state.companionSession) throw Object.assign(new Error('Choose your conversation, not the reminder delivery session.'),{status:400})
      const session = await findSession(ctx.sessionController,sessionId)
      return engine.follow(session,title || session.title)
    },
    async close() { await engine.close(); for (const dispose of disposers) if (typeof dispose === 'function') dispose(); await domain.close() },
  }
}
