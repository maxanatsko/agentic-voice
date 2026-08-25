#!/usr/bin/env bash
# Converts an official Kokoro-82M voice (hexgrad/Kokoro-82M on HuggingFace)
# into the flat [510,256] fp32 .bin format FluidAudio's Kokoro-ANE backend
# reads directly from its model cache. No Python/torch needed: a Kokoro
# .pt voice file is an uncompressed zip; the raw tensor storage lives at
# "<voice>/data/0" and is already byte-identical to the .bin format.
set -euo pipefail

VOICE="${1:?usage: convert-voice.sh <voice-id, e.g. af_bella>}"
CACHE_DIR="$HOME/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE"
DEST="$CACHE_DIR/$VOICE.bin"

if [[ -f "$DEST" ]]; then
  echo "already present: $DEST"
  exit 0
fi

mkdir -p "$CACHE_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -sL "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/voices/${VOICE}.pt" -o "$tmp/${VOICE}.pt"
size=$(stat -f%z "$tmp/${VOICE}.pt" 2>/dev/null || stat -c%s "$tmp/${VOICE}.pt")
if [[ "$size" -lt 500000 ]]; then
  echo "unexpected download size ($size bytes) — voice id '$VOICE' probably doesn't exist" >&2
  exit 1
fi

unzip -p "$tmp/${VOICE}.pt" "${VOICE}/data/0" > "$DEST"

payload=$(stat -f%z "$DEST" 2>/dev/null || stat -c%s "$DEST")
if [[ "$payload" -ne 522240 ]]; then
  echo "unexpected payload size ($payload bytes, expected 522240) for '$VOICE'" >&2
  rm -f "$DEST"
  exit 1
fi

echo "converted: $DEST"
