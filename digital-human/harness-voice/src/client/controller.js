export class LauncherController {
  constructor(request = async action => {
    const controller = new AbortController(), timeout = setTimeout(() => controller.abort(),10000)
    try {
      const response = await fetch('api/whale-voice',{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify({action}),signal:controller.signal})
      const result = await response.json()
      if (!response.ok || !result?.ok) throw new Error('unavailable')
      return result.value
    } finally { clearTimeout(timeout) }
  }) {
    this.request = request; this.listeners = new Set(); this.value = {loading:true,supported:true,running:false,starting:false,problem:null}
    this.closed = false; this.busy = false; this.polling = false; this.timer = null; this.generation = 0
    this.subscribe = listener => { this.listeners.add(listener); return () => this.listeners.delete(listener) }
    this.getSnapshot = () => this.value
  }
  update(state) {
    if (this.closed) return
    this.value = {...this.value,...state}
    for (const listener of this.listeners) listener()
  }
  async start() {
    try { this.update({...await this.request('desktop_autostart'),loading:false}) }
    catch { this.update({loading:false,problem:'unavailable'}) }
    if (!this.closed) this.timer = setInterval(() => { void this.refresh() },2000)
  }
  async refresh() {
    if (this.closed || this.polling || this.busy) return
    this.polling = true
    const generation = this.generation
    try { const value = await this.request('desktop_state'); if (generation === this.generation) this.update({...value,loading:false}) }
    catch { if (generation === this.generation) this.update({running:false,starting:false,problem:'unavailable'}) }
    finally { this.polling = false }
  }
  async launch() {
    if (this.closed || this.busy) return
    this.busy = true; this.generation += 1; this.update({loading:true,problem:null})
    try { this.update({...await this.request('desktop_toggle'),loading:false}) }
    catch { this.update({loading:false,problem:'unavailable'}) }
    finally { this.busy = false }
  }
  close() { this.closed = true; clearInterval(this.timer); this.listeners.clear() }
}
