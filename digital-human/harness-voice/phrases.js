import { Sentences } from './sentences.js'

export class Phrases {
  pending = []
  timer = null
  constructor(emit, { minimum = 18, waitMS = 180, schedule = setTimeout, unschedule = clearTimeout } = {}) {
    this.emit = emit; this.minimum = minimum; this.waitMS = waitMS
    this.schedule = schedule; this.unschedule = unschedule
    this.splitter = new Sentences(text => this.add(text))
  }
  add(text) {
    this.pending.push(text)
    if (this.pending.join(' ').length >= this.minimum) this.flush()
    else if (this.timer == null) {
      this.timer = this.schedule(() => { this.timer = null; this.flush() },this.waitMS)
      this.timer?.unref?.()
    }
  }
  push(text, final = false) {
    this.splitter.push(text,final)
    if (final) this.flush()
  }
  flush() {
    if (this.timer != null) this.unschedule(this.timer)
    this.timer = null
    const phrase = this.pending.join(' '); this.pending = []
    if (phrase) this.emit(phrase)
  }
  cancel() {
    if (this.timer != null) this.unschedule(this.timer)
    this.timer = null; this.pending = []; this.splitter = new Sentences(text => this.add(text))
  }
}
