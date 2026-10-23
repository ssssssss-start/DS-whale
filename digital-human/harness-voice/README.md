# Whale voice bridge

## Full-detail 3D mode (desktop 0.7.0 / plugin 0.5.5)

Right-click the companion and select **3D Character (Original Detail)**. Toggle it again to return to 2D; the choice is remembered. All 1,383,928 original vertices, textures and mesh topology are preserved without decimation. Assets live in `digital-human/3d/whale-full-v0.3/`; reduced v0.2 is no longer the current result.

The 3D menu offers a full turn, walking in place and a tail swish. `whale_body` advertises `turn`, `walk` and `tail_swish` only when the connected desktop supports them, retaining ownership, visibility, expiry and receipt checks. 2D does not advertise these actions. 3D currently exposes idle, greeting, poke, headpat and the three new movements; the four older expressions have not passed 3D art review. Listening/thinking states drive head movements; output level drives a simple mouth morph. Blink and mouth controls remain drafts.

Reopen an older running app to load the rebuilt binary. New Agent commands also require installing `releases/dsh-whale-voice-0.5.5.tgz` through the Harness plugin page. Building and offline rendering do not upgrade the live plugin or place calls. The original-detail model has been rendered with native SceneKit offline; walking has no foot IK yet, and hair/skirt collision or physics is not implemented.


## Harness startup and visibility control (plugin 0.5.4, desktop 0.6.2/build 21)

Entering Harness starts Whale Companion once. The button directly above **DS Bot** follows the actual desktop state: **Hide Whale Companion** hides the visible character, **Show Whale Companion** reveals it, and **Start Whale Companion** reopens an exited app. Both entries remain left-aligned. Hiding stops speech and ends a voice call; showing or starting never opens the microphone or places a call. State polling never revives a deliberately exited companion.

Update both the companion and `dsh-whale-voice-0.5.4.tgz`; quit and reopen an older running companion once. A visibility change is confirmed only after the desktop reports it; failed communication prompts a retry. Older companions without hide support retain start/show behavior. The first upgrade from a plugin without a client component requires reopening Harness when current work permits, to refresh its missing-client cache.

The launcher searches `~/Applications/Whale Companion.app`, `/Applications/Whale Companion.app`, the adjacent `desktop-preview/Whale Companion.app`, then `~/main/DeepSeek-Bot/digital-human/desktop-preview/Whale Companion.app`. Cordis plugin configuration accepts an absolute `companionPath` and `autoStart: false`. macOS only; remote Web clients control the Harness host. Autostart is once per plugin host lifecycle and does not install a login item. Only public sidebar and authenticated route APIs are used, with no Harness patches.


## Desktop voice calls (plugin 0.5.0, desktop 0.6.0)

Double-click the character to start or end a voice call without opening a chat page. Harness must keep running in the background with this plugin, a chat model and the configured Voice Input recognizer ready. The desktop needs microphone permission, Doubao voice and Sound enabled. If a conversation is bound, the call uses it; otherwise the plugin creates and remembers a normal **Whale Voice Conversation** through the public Session controller. This is separate from the minimal reminder-delivery session. Busy or unavailable bound sessions fail explicitly.

The companion captures a maximum of 20 seconds per utterance as in-memory 16 kHz mono PCM16 WAV. After approximately 1.1 seconds of silence, it stops the microphone, transfers bounded chunks over the same-user socket and calls public `speechController.transcribe`. Only the recognized text enters the normal Session prompt. There is no browser route, raw-audio log, temporary audio file, alternate recognizer fallback or chat-model replacement. The first call may ask for macOS microphone permission. Recognition model preparation and chat-model configuration are prerequisites; calls do not silently download models.

A separate call badge follows the character at a readable size: blue **Connecting**, green **Listening**, orange **Recognizing / Thinking**, cyan **Speaking**, red **Paused / Unavailable**. It has an **End voice call** button and stays readable when the character is scaled down. Listening and thinking also drive subtle different poses. Recognition starts only in Listening; generation and tool work remain Thinking until actual audio starts. Only final input completion plus audio drain returns the call to Listening, after a short output-drain delay. The Agent's body context includes the corresponding call and microphone state.

Use the menu's **Pause Voice Call** / **Resume Voice Call** for desktop calls. Double-click again or press the badge's red phone button to hang up. Hide, mute, sleep and session inactivity release the desktop microphone; device changes pause the call. Cancelled permissions, ASR results and old-call messages cannot restart capture or submit a late transcript. Hangup stops speech without cancelling the Agent's task. A disconnected backend times out locally; a missing desktop heartbeat releases its host lease. Existing DS Bot browser calls still work and share the single-call limit.

See [desktop call notes and validation](../桌面直连语音通话说明.md). This working copy is not automatically copied to `repository/DS-whale` or installed into a running Harness.

## Hearing and digital body (plugin 0.4.4, desktop 0.5.4)

The bound conversation receives a public system-prompt section identifying Whale Companion as its digital body, while preserving the Bot's name, role and instructions. A Whale call temporarily owns the body and returns ownership to the bound conversation on hangup. Other conversations receive no body identity and cannot control it.

DS Bot voice calls label recognized input as ASR when preparing a reply. The Agent can naturally say it hears the user through speech recognition. Typed or unknown input is not labeled speech; raw audio, tone and background sound are not provided to the model. Update and rebuild DS Bot's client too; older clients leave input provenance unknown.

`whale_body` with `action: "status"` reports current connectivity, availability, input provenance and actions advertised by the desktop. Supported actions are `greeting` (wave), `poke`, `headpat`, `shy`, `surprised`, `sad`, `sleepy` and `idle` (return to rest). Actions are silent and do not stop live TTS. A busy interaction is not replaced; the tool reports `busy`. Hidden, inactive, outdated or disconnected companions cannot execute new movements. Body control does not require a TTS key or Sound to be enabled.

Commands expire after two seconds and require a matching desktop receipt. `accepted` confirms acceptance, not animation completion; timeout, cancellation and ownership changes remain unconfirmed. Future motions require updating both the desktop implementation/capability list and the plugin action registry/schema. No Harness source or user data is changed. This working tree is ahead of the separate `repository/DS-whale` publication copy; it is not automatically synchronized or installed.

Install this directory through Harness **Plugins → Add plugin → Local directory**, then enable `dsh-whale-voice`. No Harness files are patched. From v0.2.3, new direct replies in the bound conversation are spoken without a prefix. In an unbound conversation, a direct user prompt beginning with `[whale]` opts that turn into speech. History, background schedules, Bot-to-Bot messages, reasoning and code blocks are not automatically read.

With desktop v0.4.3, fill `doubao_api_key` in `desktop-preview/voice-config.local.json` once; the app reads it on launch. The local file is Git-ignored and owner-readable/writable only. **Reload Voice Config…** applies edits without restarting. **Connect Doubao Voice…** remains available for a temporary in-memory connection. No local voice service is needed. Choose **Test Voice (Uses API)** for a short billed sample; success displays `Doubao connected · streaming ready`. See [setup](../豆包TTS接入说明.md). No credentials enter this Harness plugin.

Example prompt:

```text
[whale] Reply as my whale companion in three short Chinese sentences. Tell me how you can keep me company while I work. Do not use tools.
```

The plugin observes public `session/event` events and splits visible `agent/assistant-stream` text at sentence boundaries. It forwards complete sentences through a same-user Unix socket in `/tmp/whale-voice-<uid>/speech.sock` (directory 0700, socket 0600). A missing companion never blocks the agent loop. The companion serializes synthesis, buffers at most two ready clips, and starts the next synthesis while the current clip plays. Audio metering drives small speaking/tail motion; phoneme lip synchronization is not implemented. Stop Speaking, mute, hide, character interactions, a new voice turn and cancellation stop local playback and discard obsolete results. Cancelling HTTP does not guarantee the upstream job stops immediately.

Version 0.3.0 merges short completed sentences up to 18 characters, waiting at most 180 ms after the first short sentence. Long sentences and the final remainder are sent immediately. This reduces separate requests for very short utterances.

Desktop v0.4.0 sends the reply phrases into one official Doubao TTS 2.0 bidirectional WebSocket session. Text input and PCM output overlap; the reply ends its voice session only after Harness ends the turn. Initial audio buffering is about 150 ms. The plugin forwards cleaned complete phrases rather than raw model tokens. No temporary web conversation, text-copy model call or webpage credentials are involved. The prior Mira transport remains as compatibility/regression code, with no automatic fallback in the normal desktop path.

Timing-only logs (no conversation text or credentials) are written to `/tmp/whale-voice-<uid>/latency-*.jsonl`. Times start when Harness publishes the direct user message, excluding UI and earlier dispatch overhead. `play_start` measures the player start call, not microphone-measured acoustic onset. `tts_start.overlaps_playback` confirms scheduling overlap; `cache_hit` distinguishes cached audio. `report.py` summarizes these logs, including streaming first-packet time, whole-request time, bridge stages and buffer underruns. Records include provider/source labels; fixed preview samples exclude real Harness model latency. WebSocket total synthesis time also includes waiting for subsequent text input. Old Mira timing files in `mira-tts/bridge/timings/` belong to the historical bridge and do not describe Doubao requests. Its `estimated_gap_ms` subtracts the previous clip duration from successive start times; the raw `gap_ms` is only post-callback handoff overhead. Neither measures silence embedded in the audio.

```sh
node --test digital-human/harness-voice/test/*.test.mjs
python3 digital-human/harness-voice/report.py --out digital-human/harness-voice/review
```

## Proactive v0.2

Update the plugin through Harness's plugin manager. Old linked v0.1 installs need reinstalling to refresh dependencies/module caches. In the rebuilt companion choose **Follow Next Conversation**, then send a direct user message in the desired Harness session. **Stop Following** removes the subscription. Enable **Proactive Voice** separately.

**Do Not Disturb** supports 30 minutes, one hour or until turned off, survives restart, cancels proactive speech and rejects late audio without replay. Direct `[whale]` replies remain available; global **Sound** mutes all speech. Quiet hours default to 23:00–09:00 local time. Hidden/inactive desktops suppress proactive voice. **Recent Messages** shows unread functional text, origin and delivery status.

**Companion Check-ins** is opt-in: 30 minutes without interacting with Whale, a 60-minute minimum interval, three per local day, and no further check-ins after an unanswered one until a new interaction. First-version wording is a fixed gentle template; no screen/keyboard monitoring or additional model call is used.

Public approval events trigger one notice after two seconds and revoke it when decided. A completed model turn never proves task success. The followed agent can use `whale_task_evidence` then `whale_report_task` with observed tool-result sequence references; the result is explicitly an agent claim. Terminal errors are reported as turn errors.

For explicit reminders, ask the followed agent to call `whale_create_reminder`: supply `at` (ISO time with timezone) or `dailyTime` (HH:mm), optionally `timeZone` (default Asia/Shanghai). The public Session controller creates a dedicated minimal Whale session and Harness schedule delivers reminders. `whale_manage_reminders` lists/deletes only owned reminders. Installation creates no schedules. Question-card notices and exact source-session navigation are not yet implemented.

Preferences, dedupe and functional unread text use public `storageDomain` in the `whale_voice` domain. No private Harness files or credentials are read. Native preferences use the companion's UserDefaults. Missing public services disable proactive features; manual speech remains independent. Nothing patches Harness.

Host integration check (mock session/schedule adapters, real public storage API):

```sh
node --import ./deepseek-harness/node_modules/tsx/dist/loader.mjs --import ./digital-human/harness-voice/test/harness-resolve.mjs digital-human/harness-voice/test/host.integration.mjs
```

The test resolver is not shipped or used at runtime.

## Direct conversation binding (v0.2.2)

With the updated DS Bot client, right-click a Bot and choose **Bind Whale Companion**. The authenticated Harness connection route `/api/whale-voice` validates the current conversation against the public Session controller list and saves the binding in the plugin's storage domain. It does not send a prompt or start an Agent. The updated desktop menu displays the selected name. Switching selection revokes pending old task notifications, preserves reminders, and does not enable voice. Groups are not supported. **Follow Next Conversation** remains available as a fallback. The route exposes only binding metadata, not transcripts or credentials. A new Bot conversation part needs a new binding.

## Bound replies (v0.2.3)

Binding also opts in to reading future direct replies. Doubao must be configured and Sound enabled. Proactive Voice and DND govern unsolicited notifications, not replies to your own new messages. Unbinding or switching cancels the previous conversation's buffered automatic reply, including audio still playing after the model turn ends. Historical replies are not replayed. Background schedule and Bot-to-Bot replies remain outside this automatic path. The desktop displays `Doubao key set · select Test Voice` before verification, and `Doubao connected · streaming ready` after successful synthesis. The prefix is not required in the bound conversation.

## Whale voice calls (plugin v0.4.3, desktop v0.4.9)

DS Bot's **Voice chat** button now uses Whale Companion's selected Doubao voice when `dsh-whale-voice` is enabled. Open the rebuilt companion on the Harness host, load the existing voice config and enable **Sound**, then start a call in DS Bot. The call shows **Voice: Whale Companion**. Speech recognition still uses Harness **Voice Input** (with its model prepared) or the browser's recognizer; the current Bot's chat model generates replies. No new TTS credential is entered in DS Bot. Voice data and audio play on the Harness host, including when DS Bot is opened remotely.

A call temporarily selects its own conversation without changing the persisted Whale binding. Visible reply phrases stream through the existing socket and Doubao pipeline; audio levels drive the existing speaking motion. The browser does not also read the reply. Final reply input and actual audio drain permit listening again, without waiting for chat projections or socket teardown. Captions follow the speech phrases; call status polls every 250 ms. Tool steps and sentence gaps do not count as completion. **Pause** stops current/buffered speech; **Resume listening** starts a fresh utterance without replaying it. **End voice chat** cancels speech and releases the temporary selection; it does not abort the underlying Bot task. Other conversation replies and proactive notifications are suppressed during the call and not replayed afterward. Direct call replies remain available during DND.

Only one Whale call can run per Harness host. Closing the page or losing the connection releases its 15-second lease (checked periodically). A voice failure pauses the call with an error instead of switching to browser speech. Browser speech remains the original fallback only when the Whale plugin route is absent. The API Key stays in the native companion; the authenticated connection route carries only call control/status, and the same-user socket carries visible reply text and playback status.

After updating the plugin files, reload the Whale plugin through Harness's plugin manager (or restart Harness when no other tasks need to keep running), and refresh the DS Bot client. This change uses public plugin interfaces only. Automated checks use mock model/recognizer/desktop/audio output; they do not establish real microphone quality, acoustic echo suppression or paid API latency.


### Connection reuse (plugin v0.4.3, desktop v0.4.9)

Submitting a call utterance preconnects Doubao while the Bot generates its reply. Consecutive replies reuse that WebSocket, with a fresh synthesis session ID per reply. Final input and actual audio drain still control listening; connection lifetime does not. After playback, the local idle limit is 120 seconds, checked every two seconds; call polling does not extend it. Hangup, pause, disconnect, credential/voice changes and active synthesis errors release the connection. If the server closes an idle connection sooner, the next question reconnects; partially spoken replies are not automatically retried. Ordinary non-call playback retains its existing lifecycle.

This follows the [official bidirectional protocol](https://docs.volcengine.com/docs/DoubaoVoice/WebSocketBidirectionalStreaming-V3?lang=zh). Mock checks cover early preconnect, two replies on one connection, unique session IDs, late-packet isolation, idle loss/reconnect and expiry. Actual latency savings remain unmeasured.
