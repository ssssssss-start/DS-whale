# Changelog

## Desktop 0.7.2 / voice plugin 0.5.5 — 2026-10-23

- Preserve the original full-detail 3D model: all 1,383,928 vertices and textures, 14 meshes, 16 bones and seven clips, with a 2D/3D switch.
- Connect turning, waving, walking in place and tail motion, plus listening/thinking/speaking states. Advertise only supported Agent actions while retaining busy, expiry and deduplication checks.
- Preserve painted shading, remove extra metallic highlights and correct desktop color compositing with fixed exposure. The ◐ control adjusts white brightness live, protects warm skin tones, persists changes and saves/restores a reference. The user approved **94%**, now the default.
- Deliver full GLB/Blender files as versioned release assets with binding/export scripts, validation records, SHA-256 metadata and a verified model downloader.
- Include today's Harness auto-start, sidebar hide/show/reopen and restored DS Bot left alignment; see the 0.6.x entries below.

Validation: 45 plugin unit tests, generated-client consistency, mock sidebar/host integrations and the publication-copy native build/self-checks passed. The live brightness control was checked and the user approved and saved 94%. No credentials/session data or Harness-core patches are included.

Limits: rigging and facial morphs remain drafts, without individual fingers, foot IK or hair/skirt physics. The four older expressions are not advertised in 3D. No real microphone or paid ASR/TTS quality test was performed in this round; no automatic updater is implemented.

## Desktop 0.6.2 / Voice plugin 0.5.4 — 2026-10-23

- Toggle the sidebar button between Hide, Show and Start from the actual desktop state. Hiding keeps the application running; exited companions can still reopen.
- Advertise desktop hide support and wait for reported visibility before confirming a change. Timeouts and disconnections fail explicitly; older desktops keep start/show behavior.
- Reuse native Hide Whale behavior: stop speech and end calls. Showing never opens the microphone or starts a call. Preserve left alignment and once-per-host autostart.
- Pass 44 plugin tests, generated-client consistency, mocked UI/host integration and native build self-checks. Installed and enabled in live Harness; the same sidebar control confirms hide/show state and label changes without starting a voice call.

## Voice plugin 0.5.3 — 2026-10-23

- Restore the original left alignment of DS Bot after adding the Whale launcher. Footer entries keep their natural width rather than stretching into centered rows; Whale remains above DS Bot.
- Change only the plugin's injected layout style, preserving launch and reveal behavior.

## Desktop 0.6.1 / Voice plugin 0.5.2 — 2026-10-23

- Start Whale Companion once when entering Harness; state polling never revives a deliberately closed app.
- Add a localized Start/Show button above DS Bot with running, starting and failure states, including collapsed-sidebar accessibility.
- Use the public sidebar slot and authenticated route, fixed application discovery and optional companionPath/autoStart configuration. No Harness patches.
- Reveal or reopen the character without duplicate instances, microphone capture, calls or welcome speech.
- Pass 42 plugin tests, generated-client consistency, mocked UI/host integration and native build self-checks. Live Harness installation of 0.5.2 confirms vertical placement, entry autostart, hidden-character reveal and manual re-opening after quit. No live voice call was started.

## Desktop 0.6.0 / Voice plugin 0.5.0 — 2026-10-22

- Start and end a native voice call by double-clicking the character, without opening a chat page; use a bound Harness session or create and reuse a normal voice session.
- Capture bounded PCM16 speech in memory and use the configured public Harness recognition and Session prompt APIs. Pause, hangup, mute, hide, sleep, device changes and stale callbacks release or protect microphone ownership.
- Add a readable attached phone badge with connecting, listening, recognition, thinking, speaking and paused states, a hangup button and state-linked character poses.
- Give the owning Agent ASR-aware hearing context, digital-body identity and receipt-based `whale_body` gesture/expression controls. Preserve the Bot's name, role and persistent binding.
- Update the optional DS Bot integration patch with explicit ASR input provenance and include its generated client bundle.
- Include desktop 0.5.3 hair-edge cleanup and its image checks, previously absent from this publication copy.
- Record versions, setup instructions, screenshots and [Chinese release notes](CHANGELOG.zh.md).
- Validation: 36 voice-plugin tests, 318 DS Bot tests, public API integration, desktop build/self-checks and patch applicability. Real microphone/model/paid-TTS integration is unverified; the broad DS Bot mock smoke still fails at the Chief question-card step. No Harness core patch or automatic updater is included.

## Desktop 0.5.2 — 2026-10-22

- Restore hidden hair behind the moving tail with a fixed, feathered background patch.
- Increase head-pat tail amplitudes smoothly to 2.5 times idle.
- Replace the full-face 0.28-second blink with a readable idle smile (2-second hold).
- Extend head-pat smiles and sustain them while the head is held, with gradual recovery.
- Add sustained-press and idle-smile rendering checks; no Harness or DS Bot changes.

## Desktop 0.5.2 — 2026-10-22

- Separate the original tail from the body and keep its root anchored under the skirt.
- Add a gentle 4.8-second cycle with delayed tip rotation and smooth start/stop.
- Preserve the foreground hair, skirt and legs; include a generated hidden-root patch and prompt.
- Verify exact neutral-pixel reconstruction, tail continuity and existing interaction/voice checks.
- Harness and DS Bot code are unchanged in this update.

## Initial repository publication — 2026-10-22

- Publish Whale Harness plugin 0.4.3 and macOS desktop source 0.5.0/build 14.
- Include four manual emotion sequences and the latest static-tail correction.
- Include optional DS Bot integration as a patch pinned to an exact baseline.
- Omit local secrets, user data, diagnostic logs, old Mira bridge and legacy recorded clips.
- Record versions and update boundaries; automatic updating is not implemented.
