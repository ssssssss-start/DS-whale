import net from 'node:net'
import { join } from 'node:path'
export const socketPath = () => join('/tmp', `whale-voice-${process.getuid()}`, 'speech.sock')

export function connectDesktop(receive, path = socketPath()) {
  let connection, stopped = false, reconnect, buffer = ''
  function connect() {
    if (stopped) return
    const socket = net.createConnection(path)
    connection = socket; buffer = ''; socket.setEncoding('utf8')
    socket.on('connect', () => socket.write('{"type":"hello"}\n'))
    socket.on('data', data => {
      buffer += data.toString('utf8')
      if (Buffer.byteLength(buffer) > 262144) { socket.destroy(); return }
      let index
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0,index); buffer = buffer.slice(index + 1)
        try { receive(JSON.parse(line)) } catch { /* malformed IPC is not a command */ }
      }
    })
    socket.on('error', () => socket.destroy())
    socket.on('close', () => {
      if (connection === socket) connection = null
      if (!stopped) { reconnect = setTimeout(connect, 2000); reconnect.unref?.() }
    })
  }
  connect()
  return {
    send(command) {
      if (!connection || connection.connecting || connection.destroyed || connection.writableLength > 65536) return false
      connection.write(JSON.stringify(command) + '\n'); return true
    },
    close() { stopped = true; clearTimeout(reconnect); connection?.destroy() },
  }
}
