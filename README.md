# DS Whale 🐳

A macOS desktop companion for DeepSeek Harness and DS Bot, with expressive character animation, conversation binding, official Doubao streaming speech, voice calls and opt-in proactive notifications.

[中文说明](README.zh.md)

## Features

- Full-detail 3D mode preserves all 1,383,928 vertices, with turning, waving, walking in place and tail motion; switch back to 2D anytime.
- **◐ White Brightness** adjusts live and persists; the approved reference is **94%**, retaining the current blue hair and other saturated colors.

- Start once when entering Harness, with a manual Start/Show button above DS Bot; closing stays closed until manually reopened.
- Double-click to call a background Harness session without opening a chat page; native microphone capture, pause, resume and hangup.
- A readable phone badge follows the character and distinguishes connecting, listening, recognition, thinking, speaking and paused states.
- ASR-aware hearing and an Agent-owned digital body controlled through real gesture/expression tools.

- Transparent, draggable, resizable desktop character.
- Wave, poke and head-pat interactions; manual Shy, Surprised, Sad and Sleepy expressions.
- Read new direct replies in a bound conversation, or opt in with `[whale]`.
- Official Doubao bidirectional streaming TTS, local credential configuration and audio-driven speaking motion.
- DS Bot voice calls use the companion's selected voice through the optional DS Bot integration.
- Task notices, explicit reminders, companion check-ins, quiet hours and Do Not Disturb.

## Architecture and modification boundary

| Component | Location | Changes |
| --- | --- | --- |
| Whale Harness plugin | `digital-human/harness-voice/` | Independent plugin using public APIs |
| Native desktop companion | `digital-human/desktop-preview/` | Swift / AppKit / SpriteKit application |
| DS Bot integration | `integrations/ds-bot/` | Optional **DS Bot client changes** for right-click binding and voice calls |
| DeepSeek Harness core | External dependency | **No tracked core source changes** in the checked local checkout |

Installing Whale alone does not add DS Bot's context-menu entry or replace DS Bot voice calls. Those features require the supplied DS Bot patch. Basic opt-in speech and Follow Next Conversation work through the standalone Whale plugin.

## Build and setup

1. On macOS, install Apple's Command Line Tools and build the desktop app:
   ```sh
   bash digital-human/3d/download-model.sh  # optional full-detail 3D model
   bash digital-human/desktop-preview/build.sh
   open 'digital-human/desktop-preview/Whale Companion.app'
   ```
2. Install `digital-human/harness-voice` using Harness's public plugin manager and enable `dsh-whale-voice`.
3. Copy `voice-config.example.json` to `voice-config.local.json` beside the desktop source, set file permissions to `600`, and enter your own Doubao Speech API Key locally. Never commit it. Use **Reload Voice Config…** or **Connect Doubao Voice…**. API usage is billed by the provider.
4. Prepare Harness Voice Input and a chat model, then double-click to call; double-click again or use the red phone button to hang up. Calls use a bound session or create and reuse a normal voice session. See [desktop call setup](digital-human/harness-voice/README.md#desktop-voice-calls-plugin-050-desktop-060). For right-click binding and browser calls, follow [DS Bot integration](integrations/ds-bot/README.md).

The desktop runs on the Harness host. Desktop recognition uses the host's Voice Input service; DS Bot browser calls may also use browser recognition; the Bot's configured chat model supplies replies. A TTS key alone does not supply recognition or a chat model.

## Versions and updates

See [versions.json](versions.json), [CHANGELOG.md](CHANGELOG.md) and [中文更新说明](CHANGELOG.zh.md). Current source: desktop 0.7.2/build 25, Whale plugin 0.5.5. This repository establishes the source/version history; it does **not** implement automatic application updates. The [v0.7.2 release](https://github.com/ssssssss-start/DS-whale/releases/tag/v0.7.2) carries the plugin package and full GLB/Blender models. Update plugins through Harness's plugin manager and rebuild/reopen the desktop when no call is active.

## Validation and limitations

```sh
node --test digital-human/harness-voice/test/*.test.mjs
bash digital-human/desktop-preview/build.sh
```

These checks use mock transports/audio and do not prove live microphone quality or paid API latency. 2D expressions can be selected manually or requested through `whale_body`; 3D advertises only its currently supported actions. Phoneme-level lip sync is not implemented. The 2D tail uses a separate rear layer; 3D uses a skeletal tail. Rigging, blink and mouth shapes remain drafts without foot IK or hair/skirt physics. Fixed legacy greeting/poke/head-pat recordings and the unofficial Mira web bridge are not distributed; gestures remain available without those recordings. Dynamic Doubao speech is independent of them.

Only current runtime artwork is included. User data, real API configuration, logs, generated app bundles, old experiments and the third-party reference project are excluded. No redistribution license is declared yet; see [asset notes](digital-human/desktop-preview/assets/README.md).
