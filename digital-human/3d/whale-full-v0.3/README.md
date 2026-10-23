# Whale full-detail rig v0.3

Appearance takes priority by user request. All **1,383,928 original vertices**, mesh topology and original texture resolution are retained without decimation. Reduced v0.2 is no longer the selected result. The source is the character already imported in the user's live Blender scene; this work did not fetch third-party models or use a paid generator. No additional claim is made about the original model's generation provenance.

- `whale-full-v0.3.blend`: original-detail geometry, textures, 16 bones and seven clips in `Whale_Full_v03`. The original `Scene` is retained.
- `whale-full-v0.3.glb`: runtime export with 14 meshes, one skin and seven clips.
- `rig-validation.json`: vertex/topology preservation and weight coverage checks.
- `export-validation.json`: exported mesh, skin and animation checks.

## Playback

Enable one NLA track at a time on `WhaleFullRig`. `Turn_360` lasts eight seconds; `Wave`, `Idle`, `Listening`, `Thinking` and `Tail_Swish` last four seconds; `Walk_In_Place` loops over two seconds, at 24 fps. The saved default is a neutral pose.

Rebuild and reopen the companion, then choose `3D Character (Original Detail)` in its context menu. Toggle back to 2D at any time. New Agent commands require plugin 0.5.5; no Harness patches are involved. Listening and thinking have different head motions, and the existing phone badge still reports call phases.

## Remaining art work

This is an initial working rig/runtime integration, not final art approval. Fingers are not separately rigged; walking is in place without foot IK; long hair follows the head without hair/skirt collision or physics. Blink and mouth controls are local deformation drafts, not a complete retopologized facial rig. The four older expressions are not advertised to the Agent in 3D mode. No live microphone or paid speech-quality test was performed.

## Rebuild

Use the release project as described below; set the correct absolute `__file__` when running scripts. Preparation refuses to overwrite its named scene. Future performance work must preserve appearance and must not default to mesh reduction.

## Model download

The full GLB and Blender project are [v0.7.2 release assets](https://github.com/ssssssss-start/DS-whale/releases/tag/v0.7.2), not Git blobs. From the repository root run `bash digital-human/3d/download-model.sh` before building the desktop. It verifies SHA-256 before installation. Download the Blender project from the same release; `assets.json` records sizes and checksums.

The delivered Blender project contains both the original `Scene` and rigged `Whale_Full_v03`. Edit the latter and run `export.py` with the correct `__file__`. `prepare.py` documents the initial binding and requires an original project without the derived scene; do not rerun it on the already-rigged file.
