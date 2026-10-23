const problem = (message, status) => Object.assign(new Error(message), { status })

export function createBindingRoute({ read, bind, call, desktop }) {
  return {
    path: '/api/whale-voice', methods: ['POST'], requestBody: 'buffered',
    async fetch(request) {
      const answer = (body, status = 200) => new Response(JSON.stringify(body), {
        status, headers: { 'content-type':'application/json', 'cache-control':'no-store' },
      })
      try {
        let body
        try { body = await request.json() } catch { throw problem('Invalid binding request.',400) }
        if (['desktop_state','desktop_start','desktop_autostart','desktop_toggle'].includes(body?.action) && desktop) {
          return answer({ok:true,value:await desktop(body.action)})
        }
        if (['call_start','call_poll','call_prepare','call_pause','call_resume','call_end'].includes(body?.action) && call) {
          if (body.action === 'call_start' ? typeof body.sessionId !== 'string' || !/^[\w-]{1,200}$/.test(body.sessionId) : typeof body.id !== 'string' || !/^[\w-]{1,200}$/.test(body.id)) throw problem('Invalid call request.',400)
          return answer({ok:true,value:await call(body)})
        }
        if (body?.action === 'state') return answer({ ok:true, value:await read() })
        if (body?.action !== 'bind') throw problem('Unknown binding action.',400)
        if (typeof body.sessionId !== 'string' || !/^[\w-]{1,200}$/.test(body.sessionId)) throw problem('Choose a valid conversation.',400)
        if (body.title != null && (typeof body.title !== 'string' || body.title.length > 160 || /[\u0000-\u001f]/.test(body.title))) throw problem('Invalid conversation name.',400)
        return answer({ ok:true, value:await bind({ sessionId:body.sessionId, title:body.title?.trim() }) })
      } catch (error) {
        const status = error.status || 503
        return answer({ ok:false, error: status === 503 ? 'Whale binding is unavailable. Enable dsh-whale-voice and try again.' : error.message },status)
      }
    },
  }
}

export async function findSession(controller, sessionId) {
  // The public header-only list validates membership without activating an Agent or reading its transcript.
  const result = await controller.list({}, new AbortController().signal)
  const row = result.items.find(item => item.sessionId === sessionId && !item.parentSessionId && item.origin !== 'subagent')
  if (!row) throw problem('This conversation is no longer available. Refresh the sidebar and try again.',404)
  return { id:row.sessionId, running:row.running, title:row.projections?.values?.title || null }
}
