# Whale desktop preview

Desktop **0.6.0/build 19** supports direct voice calls: double-click the character to call, double-click again or use the red phone button to hang up. The readable call badge follows the character and distinguishes connecting, listening, recognition, thinking, speaking and paused states. No chat page is needed; Harness and plugin **0.5.0** must run in the background with a prepared Voice Input recognizer and chat model. Configure Doubao, enable Sound and grant microphone permission. An existing binding is used, or a normal Harness voice session is created and reused. See [direct desktop calls](../harness-voice/README.md#desktop-voice-calls-plugin-050-desktop-060).

Desktop 0.5.4/build 18 adds Agent body control through the same-user voice socket. With voice plugin 0.4.4, only the bound session or current Whale call controls the character. All existing gestures/expressions and return-to-idle are exposed by `whale_body`; movement requests are silent, expire after two seconds and return acceptance/busy/unavailable receipts. They do not stop TTS or replace an active user interaction. Hidden or inactive desktops reject new movements. Hearing/body context and setup are documented in [the voice plugin](../harness-voice/README.md#hearing-and-digital-body-plugin-044-desktop-054). Rebuild and reopen the app to activate the native changes; building alone does not restart a running companion.

A standalone macOS companion using the supplied chibi whale character.
It connects to Harness through the standalone Whale voice plugin.

Build with `bash build.sh` (requires Apple's Command Line Tools).
Source art is in `assets/`, and application metadata is in `Info.plist`.

Open `Whale Companion.app`. Drag the character to move it.
Use the × button to quit, or the Whale menu-bar item to hide, show, or quit.
Scroll over the character to resize it, or right-click and select a size.
The default window is 190 × 234 points; scaling ranges from 50% to 200%.
The selected size is remembered. Starting the app replaces any previous instance.
The app does not start automatically on login and does not access Harness data.

## Interactions

- Idle: random blinks, subtle breathing, local hair and tail movement. No automatic speech.
- Click: a brief flinch, head tilt and small bounce with the approved Mira "poke-hum" clip.
- Hold the head for 0.7 seconds: closed smiling eyes, a gentle tilt, faster tail movement and the Mira head-pat clip.
- Actions → Say Hello: raise a hand and wave, play the welcome clip once, then return to idle.
- Actions → Sound: mute immediately, including audio already playing.
- Actions → Idle Motion: pause/resume idle deformations. Interaction responses remain available.

The actions menu is available through the ⋯ button, right-click, or the Whale menu-bar item.
Dragging more than 5 points cancels the head-pat gesture. Reactions have a 1.1-second
cooldown. A new reaction stops the previous voice; its duration includes the full
voice clip. Hiding the companion stops audio and pauses rendering. Size, position,
sound and idle-motion preferences are remembered.

Desktop v0.4.4 keeps the existing open-eye smile and closed-eye smile. Head pats ease in over 0.5 s, hold the full smile for at least 2.6 s, and ease out over 0.7 s (3.8 s minimum overall). Greetings now last at least 6 s with visible key-pose holds. A new interaction waits for the current recovery; only the latest pending interaction is kept, and its local sound starts when its action actually begins. A reply starts speech without resetting the face: an early head pat keeps its full smile until 2.1 s from onset, then recovers over 0.7 s. An interrupted wave returns over available full-body transition frames over 1.6 s, after a minimum 2.6 s of the action. Repeated reply starts do not extend recovery, and speech clears pending local interactions. Random blinks remain brief (0.28 s, including a 0.06 s closed-eye hold) and are suppressed during interactions. This changes timing, not the two source expressions or their eyelid shapes.

In v0.4.4, eye transitions reused the existing 0→1→2 interpolated textures within two eye masks, excluding the mouth. That replaced the old face-opacity dissolve, but the masks still clipped the brows. The next version below replaces those masks.

Version 0.4.5 supersedes the eye masks with one feathered full-face region whose boundary lies in the hair, outside the eyebrow/eyelid outlines. The same source frame supplies the eyes and mouth, avoiding clipped brows and rectangular remnants. The arm lift now takes 1.6 s, followed by another 0.8 s to reach the high smiling pose; lowering takes 1.25 s. The whole greeting lasts at least 8.1 s. Three complete-character intermediate poses were made with the built-in imagegen tool, then offline Apple Vision flow with palm position guidance produced 97 RGBA lift frames. Runtime uses only the prebuilt images. Source sheet, exact prompts and provenance are in [asset notes](assets/README.md); legacy originals remain unchanged. Frame interpolation may still soften finger detail.

Version 0.4.6 fixes lateral sliding in those new poses. The builder now derives placement from the original artwork and registers the head, apron and feet before and after interpolation. Runtime loads the resulting 97 frames from [asset notes](assets/README.md). The previous fixed foot center mismatched the reference stance. Independent image checks reduced the foot center's horizontal range from 21.98 to 0.82 source pixels; the largest adjacent-frame foot change is 0.013 source pixels. The build refuses an incomplete registered frame set. Run `tools/check-registration.swift` with the desktop folder and `--check-lift-v3` after compiling it to verify the artifact sequence; the report is saved under `previews/registration-v0.4.6.json`.

## Implementation and checks

`FullBodyFrames.swift` extracts all five complete characters from the supplied
`assets/wave-reference-full.png`, removes the black backdrop, and applies one
shared crop. The original PNG is preserved. No generated arm layer is used.
`WavePose.swift` plays the original full-body poses in a rest → lift → closed-eye
wave → open-eye → lower sequence. The five original drawings remain key poses. Offline RIFE interpolation supplies
33 complete RGBA frames per transition. Textures are preloaded and the desktop
targets 60 fps, without runtime inference. Key poses now include holds; the initial lift takes 0.5 s at the minimum greeting duration. Interpolation can still soften fingers. No separate arm layer is used.

`--export-expressions /absolute/output/folder` renders silent previews of a normal head pat, a head pat interrupted by a simulated reply, and a wave interrupted by a simulated reply. It checks the full smile hold and continuity on interruption without loading the voice config or calling an API.

`CharacterScene.swift` retains idle motion and interaction handling;
`AudioFeedback.swift` plays the existing bundled Mira clips. The companion accepts opted-in Harness replies through `../harness-voice/`.
`VoicePipeline.swift` serializes sentence synthesis and overlaps it with playback.
Speaking motion uses audio amplitude. Desktop microphone input now uses the public Harness recognition service; phoneme lip sync remains unimplemented.

The build runs reaction and pose-sequence checks. `--wave-demo` previews the
welcome action; `--demo` runs greeting, head-pat and poke. A normal launch stays quiet.
`--export-wave /absolute/output/folder` exports a silent GIF, the five transparent
source poses and rendered checkpoints using the same renderer as the desktop app.

Older generated assets and previews are retained for reference and are not used
for the current greeting. The window has no background card or rectangular shadow.

Dynamic speech: choose **Connect Doubao Voice…** and enter your Volcengine Speech API Key in the secure local input. It stays in memory; no local TTS service is needed. Choose **Test Voice (Uses API)** to hear one short sample, billed by your API account. New direct replies in a bound conversation are read automatically; `[whale]` opts in one turn elsewhere. See [voice bridge](../harness-voice/README.md) for installation, interruption and latency measurements.

Proactive controls now include **Do Not Disturb**, **Proactive Voice**, **Companion Check-ins**, **Follow Next Conversation**, **Quiet Hours…** and **Recent Messages**. Voice/check-ins are opt-in. DND suppresses proactive events, while direct replies remain available unless global Sound is off. See [implementation and validation](../harness-voice/README.md).

## Doubao streaming voice (desktop v0.4.3)

The default provider is the official Doubao Speech TTS 2.0 API. Sweet Xiaoyuan 2.0 is selected initially; **Doubao Voice** also offers Playful Xuemei 2.0, Gentle Xiaoya 2.0, Vivi 2.0, Xiaohe 2.0, Yunzhou 2.0 and Xiaotian 2.0. Only the voice choice is remembered. API credentials never enter preferences, reports, IPC or the Harness plugin. **Disconnect Voice** cancels audio and removes the in-memory key.

Version 0.4.3 reads `voice-config.local.json` beside `Whale Companion.app` on launch. Fill its `doubao_api_key` string once; the empty template is already created for this checkout. For other checkouts, copy `voice-config.example.json` to that local filename. The local file is Git-ignored and read with owner-only permissions. Keep it beside the app, outside the bundle, so rebuilding does not overwrite it. **Reload Voice Config…** applies later edits without restarting or making a cloud request. Missing/empty config leaves manual connection available; invalid config reports a sanitized error and preserves any current key. **Connect Doubao Voice…** still connects for this run without saving its input. **Disconnect Voice** clears memory only; the file is read again on the next launch or explicit reload. Empty/remove the file to disable future automatic loading.

Version 0.4.2 adds the four requested voices from the [official TTS 2.0 catalog](https://docs.volcengine.com/docs/DoubaoVoice/Tonelist-1?lang=zh). Vivi and Xiaohe are female voices; Yunzhou and Xiaotian are male voices. Catalog support is confirmed; account access and sound quality still need a live preview for each voice.

After entering a key, `Doubao key set · select Test Voice` means that it has not been verified yet. `Doubao connected · streaming ready` appears after a successful synthesis. API errors stop the current queue without automatic retries. The client refuses redirects, uses an ephemeral session without disk cache/cookies, and calls the fixed official HTTPS endpoint directly. No DeepSeek website token, local bridge or local password is used by the normal desktop path.

The adapter uses the official bidirectional WebSocket API. Each reply creates one connection and one session: StartConnection → StartSession → repeated TaskRequest text fragments while audio arrives → FinishSession after Harness ends → FinishConnection. The plugin sends cleaned complete phrases, including short-phrase merging; it does not forward raw model tokens. Different reply turns currently use separate connections. PCM starts after about 150 ms of queued audio and drives speaking motion. Stop/mute/hide/DND cancellation discards queued chunks and late results. DND continues to exempt direct replies.

The bundled greeting/poke/head-pat MP3 files remain offline assets from the previous iteration. They do not call the legacy Mira service. Regenerating those assets with the selected Doubao voice is a separate step after the user approves the sound.

`--self-test` covers the official request contract, documented wire fixtures, strict lengths/compression/session IDs, multiple text fragments in one session with audio before input ends, bounded audio, cancellation, DND interruption, rejected-key removal, disconnect and redirect refusal using mock WebSocket/audio. `--pcm-audio-check` separately plays the bundled welcome through the real audio engine. Real Doubao latency and account permission still require an authorized API key.

See [Doubao setup](../../README.md#build-and-setup). The existing v0.3.0 Harness plugin remains compatible and needs no reinstall. Legacy Mira transport is retained only for regression/compatibility code; the default desktop has no automatic fallback to it.

Version 0.4.1 adds Command-V/Command-A and an explicit Paste button to the secure key input. Manual preview failures show a diagnostic alert with separate HTTP 401/403 messages. One live fixed-phrase run completed: first packet ~0.88 s, player start ~1.14 s; this excludes Harness generation and is not acoustic onset. The user confirmed normal operation.

## Whale voice calls (plugin v0.4.3, desktop v0.4.9)

DS Bot's **Voice chat** button now uses Whale Companion's selected Doubao voice when `dsh-whale-voice` is enabled. Open the rebuilt companion on the Harness host, load the existing voice config and enable **Sound**, then start a call in DS Bot. The call shows **Voice: Whale Companion**. Speech recognition still uses Harness **Voice Input** (with its model prepared) or the browser's recognizer; the current Bot's chat model generates replies. No new TTS credential is entered in DS Bot. Voice data and audio play on the Harness host, including when DS Bot is opened remotely.

A call temporarily selects its own conversation without changing the persisted Whale binding. Visible reply phrases stream through the existing socket and Doubao pipeline; audio levels drive the existing speaking motion. The browser does not also read the reply. Final reply input and actual audio drain permit listening again, without waiting for chat projections or socket teardown. Captions follow the speech phrases; call status polls every 250 ms. Tool steps and sentence gaps do not count as completion. **Pause** stops current/buffered speech; **Resume listening** starts a fresh utterance without replaying it. **End voice chat** cancels speech and releases the temporary selection; it does not abort the underlying Bot task. Other conversation replies and proactive notifications are suppressed during the call and not replayed afterward. Direct call replies remain available during DND.

Only one Whale call can run per Harness host. Closing the page or losing the connection releases its 15-second lease (checked periodically). A voice failure pauses the call with an error instead of switching to browser speech. Browser speech remains the original fallback only when the Whale plugin route is absent. The API Key stays in the native companion; the authenticated connection route carries only call control/status, and the same-user socket carries visible reply text and playback status.

After updating the plugin files, reload the Whale plugin through Harness's plugin manager (or restart Harness when no other tasks need to keep running), and refresh the DS Bot client. This change uses public plugin interfaces only. Automated checks use mock model/recognizer/desktop/audio output; they do not establish real microphone quality, acoustic echo suppression or paid API latency.


### Connection reuse (plugin v0.4.3, desktop v0.4.9)

Submitting a call utterance preconnects Doubao while the Bot generates its reply. Consecutive replies reuse that WebSocket, with a fresh synthesis session ID per reply. Final input and actual audio drain still control listening; connection lifetime does not. After playback, the local idle limit is 120 seconds, checked every two seconds; call polling does not extend it. Hangup, pause, disconnect, credential/voice changes and active synthesis errors release the connection. If the server closes an idle connection sooner, the next question reconnects; partially spoken replies are not automatically retried. Ordinary non-call playback retains its existing lifecycle.

This follows the [official bidirectional protocol](https://docs.volcengine.com/docs/DoubaoVoice/WebSocketBidirectionalStreaming-V3?lang=zh). Mock checks cover early preconnect, two replies on one connection, unique session IDs, late-packet isolation, idle loss/reconnect and expiry. Actual latency savings remain unmeasured.


## Emotion expressions (desktop v0.5.0)

Open **⋯ → Expressions** and choose **Shy**, **Surprised**, **Sad**, or **Sleepy**. These are manual previews; the Bot does not yet infer or select moods. Previewing a mood does not cancel live call speech or request TTS. The new expressions reuse the full original body; only a feathered facial region changes. Each mood has 33 registered transition frames. Subtle head movement is procedural.

Entry takes 0.75 seconds and recovery takes 1 second. Total durations are Shy/Sad 5.2 seconds, Surprised 4.4 seconds and Sleepy 6 seconds. A reply can request recovery, but expressions stay visible for at least 3 seconds from entry. Repeated input uses the existing cooldown and latest pending action. No extra voice samples have been added.

Assets and original generation prompts are in `assets/emotions-v1/`; `tools/build-emotions.swift` creates aligned, masked inbetweens with offline Vision flow and eyelid constraints. Every generated frame is checked against the original outside the face mask, including alpha. `--export-emotions <folder>` exports the four GIFs, a speech-interruption sample, PNG checkpoints and `expressions.png`; resource completeness and hold/recovery assertions run during export.

### Tail motion correction

The full-body artwork currently contains a baked-in tail. Idle and head-pat animations no longer warp the lower-right tail region. Its mesh stays still while blinking, breathing and upper hair motion continue. Elastic tail motion requires a separate tail layer with a covered attachment or registered whole-character animation frames.

### Layered tail (v0.5.1)

The tail is separated from the original character into a rear layer. Its root stays fixed under the skirt; a small root rotation and a delayed distal rotation move only tail vertices. The cycle is 4.8 seconds, with root/tip amplitudes of approximately 1.8/1.4 degrees and a 0.42-second tip phase lag. The original visible art is retained; built-in imagegen supplies a small hidden-root patch. No clothing, legs or hair are driven by the tail rig. Idle Motion eases the movement on/off. Greeting frames retain their existing full-character tail, with a short settle before switching and a gradual restart afterward.

`--export-tail /absolute/output/folder` exports silent layer checks and an animated preview. The checks verify root anchoring, continuous tip movement, and pixel reconstruction of the neutral original. Source and prompt: `assets/tail-v1/`. This supersedes the static-tail correction.

### Hidden hair and readable expressions (v0.5.2)

A stationary reconstructed hair patch now sits behind the moving tail and original foreground, filling the previously occluded area. Its top/left edges are feathered under the original hair and skirt. Head pats smoothly increase both tail-joint amplitudes to 2.5 times idle, then restore idle movement.

The former 0.28-second blink used a full smiling-face texture. It is now a deliberate, infrequent idle smile: 0.55-second entry, 2-second full smile, 0.85-second recovery, with subsequent starts 14–22 seconds apart. Head pats enter over 0.6 seconds and normally hold the full smile for 3.2 seconds before a 1-second recovery. Speech interruptions retain the smile until at least 3.5 seconds after onset. Keeping the mouse held extends the head-pat hold; releasing it allows a gradual return, and dragging or speech releases the hold. Emotion menu timings are unchanged.

The expression preview export additionally verifies idle-smile holds and a sustained head pat. `assets/tail-v1/HAIR-PROMPT.md` records the built-in imagegen prompt; only the hidden-hair patch is used from that generated image.
