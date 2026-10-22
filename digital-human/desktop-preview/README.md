# Whale desktop companion

See the repository [setup guide](../../README.md). Build with `bash build.sh`. Current runtime artwork is in `assets/`. Optional locally supplied gesture recordings may be placed in `assets/sounds/` as `welcome.mp3`, `poke-hum.mp3`, and `headpat.mp3`. Missing recordings are skipped.

### Layered tail (v0.5.1)

The tail is separated from the original character into a rear layer. Its root stays fixed under the skirt; a small root rotation and a delayed distal rotation move only tail vertices. The cycle is 4.8 seconds, with root/tip amplitudes of approximately 1.8/1.4 degrees and a 0.42-second tip phase lag. The original visible art is retained; built-in imagegen supplies a small hidden-root patch. No clothing, legs or hair are driven by the tail rig. Idle Motion eases the movement on/off. Greeting frames retain their existing full-character tail, with a short settle before switching and a gradual restart afterward.

`--export-tail /absolute/output/folder` exports silent layer checks and an animated preview. The checks verify root anchoring, continuous tip movement, and pixel reconstruction of the neutral original. Source and prompt: `assets/tail-v1/`. This supersedes the static-tail correction.

### Hidden hair and readable expressions (v0.5.2)

A stationary reconstructed hair patch now sits behind the moving tail and original foreground, filling the previously occluded area. Its top/left edges are feathered under the original hair and skirt. Head pats smoothly increase both tail-joint amplitudes to 2.5 times idle, then restore idle movement.

The former 0.28-second blink used a full smiling-face texture. It is now a deliberate, infrequent idle smile: 0.55-second entry, 2-second full smile, 0.85-second recovery, with subsequent starts 14–22 seconds apart. Head pats enter over 0.6 seconds and normally hold the full smile for 3.2 seconds before a 1-second recovery. Speech interruptions retain the smile until at least 3.5 seconds after onset. Keeping the mouse held extends the head-pat hold; releasing it allows a gradual return, and dragging or speech releases the hold. Emotion menu timings are unchanged.

The expression preview export additionally verifies idle-smile holds and a sustained head pat. `assets/tail-v1/HAIR-PROMPT.md` records the built-in imagegen prompt; only the hidden-hair patch is used from that generated image.
