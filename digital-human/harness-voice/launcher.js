import { execFile } from 'node:child_process'
import { stat } from 'node:fs/promises'
import { homedir } from 'node:os'
import { isAbsolute, join, resolve } from 'node:path'
import { promisify } from 'node:util'

const execute = promisify(execFile)
const exists = async path => { try { return (await stat(path)).isDirectory() } catch { return false } }

export class CompanionLauncher {
  constructor({ send, appPath = '', autoStart = true, platform = process.platform, clock = Date.now,
    isApp = exists, run = execute, home = homedir(), packageDir = import.meta.dirname, visibilityTimeout = 2500 } = {}) {
    this.send = send; this.appPath = appPath; this.autoStart = autoStart; this.platform = platform; this.clock = clock
    this.isApp = isApp; this.run = run; this.home = home; this.packageDir = packageDir
    this.desktopAt = -Infinity; this.autoAttempted = false; this.pending = null; this.problem = null; this.closed = false; this.launchDeadline = 0
    this.visible = false; this.canHide = false; this.visibilityRequest = null; this.visibilityTimeout = visibilityTimeout
  }
  receive(message) {
    if (message.type !== 'desktop_state') return
    this.desktopAt = this.clock(); this.problem = null; this.launchDeadline = 0
    this.visible = message.visible === true; this.canHide = message.visibilityProtocol === 1
    if (this.visibilityRequest?.visible === this.visible) this.finishVisibility()
  }
  get running() { return this.clock() - this.desktopAt <= 6000 }
  async locate() {
    const candidates = this.appPath ? [this.appPath] : [
      join(this.home,'Applications','Whale Companion.app'), '/Applications/Whale Companion.app',
      resolve(this.packageDir,'../desktop-preview/Whale Companion.app'),
      join(this.home,'main','DeepSeek-Bot','digital-human','desktop-preview','Whale Companion.app'),
    ]
    for (const path of candidates) if (isAbsolute(path) && path.endsWith('.app') && await this.isApp(path)) return path
    return null
  }
  async state() {
    return { supported:this.platform === 'darwin', running:this.running, visible:this.running && this.visible, canHide:this.running && this.canHide,
      changing:!!this.visibilityRequest, starting:!!this.pending || (!this.running && this.clock() < this.launchDeadline),
      appFound:this.platform === 'darwin' && !!await this.locate(), autoStart:this.autoStart, problem:this.problem }
  }
  async toggle() {
    if (this.closed) throw new Error('Whale launcher stopped')
    if (this.visibilityRequest) { await this.visibilityRequest.promise; return this.state() }
    if (this.running && this.visible && this.canHide) return this.setVisibility(false)
    return this.launch(false)
  }
  async setVisibility(visible) {
    if (this.visibilityRequest) { await this.visibilityRequest.promise; return this.state() }
    if (this.visible === visible) return this.state()
    const request = {visible}
    request.promise = new Promise(resolve => { request.resolve = resolve })
    this.visibilityRequest = request
    request.timer = setTimeout(() => this.finishVisibility('visibility_failed'),this.visibilityTimeout)
    if (this.send?.({type:visible ? 'show_companion' : 'hide_companion'}) !== true) this.finishVisibility('unavailable')
    await request.promise
    return this.state()
  }
  finishVisibility(problem = null) {
    const request = this.visibilityRequest
    if (!request) return
    clearTimeout(request.timer); this.visibilityRequest = null; this.problem = problem; request.resolve()
  }
  async launch(automatic = false) {
    if (this.closed) throw new Error('Whale launcher stopped')
    if (automatic) {
      if (!this.autoStart || this.autoAttempted) return this.state()
      // Closing the companion is deliberate: polls and other windows never revive it.
      this.autoAttempted = true
    }
    if (this.running) {
      if (!automatic && this.canHide) return this.setVisibility(true)
      if (!automatic) this.send?.({type:'show_companion'})
      this.problem = null; return this.state()
    }
    if (this.pending) { await this.pending; return this.state() }
    if (this.clock() < this.launchDeadline) return this.state()
    this.pending = this.open()
    try { await this.pending } finally { this.pending = null }
    return this.state()
  }
  async open() {
    if (this.platform !== 'darwin') { this.problem = 'unsupported'; return }
    const path = await this.locate()
    if (this.closed) return
    if (!path) { this.problem = 'app_missing'; return }
    try {
      // Launch Services reuses an existing instance; never pass -n or start a call.
      await this.run('/usr/bin/open',['-g',path],{timeout:5000,maxBuffer:16384})
      this.launchDeadline = this.clock() + 8000
      this.problem = null
    } catch { this.problem = 'open_failed' }
  }
  close() { this.closed = true; this.finishVisibility('unavailable') }
}
