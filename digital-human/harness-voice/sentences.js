// Streamed fences can span chunks. Code and reasoning must never become speech.
export class Sentences {
  buffer = ''
  code = false
  constructor(emit) { this.emit = emit }
  push(text, final = false) {
    this.buffer += text
    while (this.buffer.length) {
      const fence = this.buffer.indexOf('```')
      if (this.code) {
        if (fence < 0) { if (final) this.buffer = ''; return }
        this.buffer = this.buffer.slice(fence + 3); this.code = false; continue
      }
      const boundary = /[。！？!?\n]|\.(?=\s|$)/.exec(this.buffer)
      if (fence >= 0 && (!boundary || fence < boundary.index)) {
        this.say(this.buffer.slice(0, fence)); this.buffer = this.buffer.slice(fence + 3); this.code = true; continue
      }
      if (boundary) {
        const end = boundary.index + 1
        this.say(this.buffer.slice(0, end)); this.buffer = this.buffer.slice(end); continue
      }
      if (final) { this.say(this.buffer); this.buffer = ''; return }
      if (this.buffer.length > 100) {
        const cut = this.buffer.slice(0, 100).search(/[,，;；:：]/)
        if (cut >= 15) { this.say(this.buffer.slice(0, cut + 1)); this.buffer = this.buffer.slice(cut + 1); continue }
        if (!this.buffer.includes('`')) { this.say(this.buffer.slice(0, 100)); this.buffer = this.buffer.slice(100); continue }
      }
      return
    }
  }
  say(text) {
    const plain = text.replace(/!?\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/^\s*(?:#{1,6}|[-*]|\d+\.)\s+/gm, '').replace(/[*_`]/g, '').trim()
    if (plain && /[\p{L}\p{N}]/u.test(plain)) this.emit(plain)
  }
}
