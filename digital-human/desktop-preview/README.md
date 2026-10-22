# Whale desktop companion

See the repository [setup guide](../../README.md). Build with `bash build.sh`. Current runtime artwork is in `assets/`. Optional locally supplied gesture recordings may be placed in `assets/sounds/` as `welcome.mp3`, `poke-hum.mp3`, and `headpat.mp3`. Missing recordings are skipped.

### Layered tail (v0.5.1)

The tail is separated from the original character into a rear layer. Its root stays fixed under the skirt; a small root rotation and a delayed distal rotation move only tail vertices. The cycle is 4.8 seconds, with root/tip amplitudes of approximately 1.8/1.4 degrees and a 0.42-second tip phase lag. The original visible art is retained; built-in imagegen supplies a small hidden-root patch. No clothing, legs or hair are driven by the tail rig. Idle Motion eases the movement on/off. Greeting frames retain their existing full-character tail, with a short settle before switching and a gradual restart afterward.

`--export-tail /absolute/output/folder` exports silent layer checks and an animated preview. The checks verify root anchoring, continuous tip movement, and pixel reconstruction of the neutral original. Source and prompt: `assets/tail-v1/`. This supersedes the static-tail correction.
