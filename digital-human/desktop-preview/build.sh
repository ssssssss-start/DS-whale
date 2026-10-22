#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$project_dir/Whale Companion.app/Contents"
mkdir -p "$app_dir/MacOS" "$app_dir/Resources"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/whale-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc -module-cache-path "${TMPDIR:-/tmp}/whale-swift-cache" "$project_dir"/*.swift -o "$build_dir/WhaleCompanion"
"$build_dir/WhaleCompanion" --self-test
cp "$project_dir/Info.plist" "$app_dir/Info.plist"
cp "$project_dir/assets/wave-reference-full.png" "$app_dir/Resources/wave-reference-full.png"
if [ -d "$project_dir/assets/wave-tweens" ]; then
    mkdir -p "$app_dir/Resources/wave-tweens"
    cp "$project_dir/assets/wave-tweens/"[0-4]-[0-4]-*.png "$app_dir/Resources/wave-tweens/"
fi
if [ -d "$project_dir/assets/lift-v3" ]; then
    for ((frame=0; frame<=96; frame++)); do
        printf -v frame_name 'lift-%03d.png' "$frame"
        if [ ! -f "$project_dir/assets/lift-v3/$frame_name" ]; then
            echo "Missing registered lift frame: $frame_name" >&2
            exit 1
        fi
    done
    mkdir -p "$app_dir/Resources/lift-v3"
    cp "$project_dir/assets/lift-v3/"lift-*.png "$app_dir/Resources/lift-v3/"
fi
mkdir -p "$app_dir/Resources/emotions-v1"
for emotion in shy surprised sad sleepy; do
    for ((frame=0; frame<=32; frame++)); do
        printf -v frame_name '%s-%02d.png' "$emotion" "$frame"
        if [ ! -f "$project_dir/assets/emotions-v1/$frame_name" ]; then
            echo "Missing expression frame: $frame_name" >&2; exit 1
        fi
        cp "$project_dir/assets/emotions-v1/$frame_name" "$app_dir/Resources/emotions-v1/$frame_name"
    done
done
mkdir -p "$app_dir/Resources/tail-v1"
cp "$project_dir/assets/tail-v1/root-source.png" "$app_dir/Resources/tail-v1/root-source.png"
mkdir -p "$app_dir/Resources/sounds"
for name in welcome poke-hum headpat; do
    if [ -f "$project_dir/assets/sounds/$name.mp3" ]; then
        cp "$project_dir/assets/sounds/$name.mp3" "$app_dir/Resources/sounds/$name.mp3"
    fi
done
mv "$build_dir/WhaleCompanion" "$app_dir/MacOS/WhaleCompanion"
plutil -lint "$app_dir/Info.plist"
echo "Built: $project_dir/Whale Companion.app"
