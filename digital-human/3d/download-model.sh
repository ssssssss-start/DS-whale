#!/bin/bash
set -euo pipefail
model_dir="$(cd "$(dirname "$0")" && pwd)/whale-full-v0.3"
mkdir -p "$model_dir"
model_path="$model_dir/whale-full-v0.3.glb"
expected="ba975c4e889be98c2419953a57df97fd026aae69de1db7f570fe4ce0b5570a64"
if [ -f "$model_path" ] && [ "$(shasum -a 256 "$model_path" | cut -d ' ' -f 1)" = "$expected" ]; then
    echo "Full-detail 3D model already verified."
    exit 0
fi
if [ -e "$model_path" ]; then
    echo "Existing model differs; move it aside before downloading." >&2
    exit 1
fi
download_path="$(mktemp "$model_dir/.model-download.XXXXXX")"
trap 'rm -f "$download_path"' EXIT
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 'https://github.com/ssssssss-start/DS-whale/releases/download/v0.7.2/whale-full-v0.3.glb' -o "$download_path"
actual="$(shasum -a 256 "$download_path" | cut -d ' ' -f 1)"
if [ "$actual" != "$expected" ]; then
    echo "Model checksum mismatch; download was not installed." >&2
    exit 1
fi
mv "$download_path" "$model_path"
echo "Full-detail 3D model downloaded and verified."
