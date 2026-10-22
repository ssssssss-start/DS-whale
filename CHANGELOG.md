# Changelog

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

## Desktop 0.5.1 — 2026-10-22

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
