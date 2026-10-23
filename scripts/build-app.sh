#!/usr/bin/env bash
# Builds "build/Agentic Voice.app" from source: the menu bar app, plus the Node MCP server,
# hooks and TTSBridge laid out under Contents/Resources/agentic-voice exactly as in this
# repository, so MCP's paths work unchanged, and the official Node runtime they run on, so
# users don't need Node installed. Ad-hoc signed for this Mac; not notarized.
set -euo pipefail

# The bundled runtime; client configs and hooks point at it. Bump to ship a newer Node.
NODE_VERSION="26.12.1"
NODE_DIST="node-v$NODE_VERSION-darwin-arm64"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Agentic Voice.app"
CONTENTS="$APP/Contents"
PLUGIN="$CONTENTS/Resources/agentic-voice"
BRIDGE_DIR="$PLUGIN/bridge/.build/release"

cd "$ROOT"
npm ci
npm run build
swift build -c release --package-path bridge --product TTSBridge
swift build -c release --package-path bridge --product AgenticVoice
BIN="$(swift build -c release --package-path bridge --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Frameworks" "$BRIDGE_DIR"
cp bridge/AgenticVoice-Info.plist "$CONTENTS/Info.plist"
cp "$BIN/AgenticVoice" "$CONTENTS/MacOS/AgenticVoice"
cp "$BIN/TTSBridge" "$BRIDGE_DIR/TTSBridge"

# Official build, checked against nodejs.org's published SHA-256. Cached between builds.
NODE_CACHE="$ROOT/build/cache"
mkdir -p "$NODE_CACHE"
if [[ ! -f "$NODE_CACHE/$NODE_DIST.tar.gz" ]]; then
  curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/$NODE_DIST.tar.gz" -o "$NODE_CACHE/$NODE_DIST.tar.gz.partial"
  mv "$NODE_CACHE/$NODE_DIST.tar.gz.partial" "$NODE_CACHE/$NODE_DIST.tar.gz"
fi
EXPECTED="$(curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" | awk -v f="$NODE_DIST.tar.gz" '$2 == f { print $1 }')"
ACTUAL="$(shasum -a 256 "$NODE_CACHE/$NODE_DIST.tar.gz" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  rm -f "$NODE_CACHE/$NODE_DIST.tar.gz"
  echo "Node $NODE_VERSION download failed its checksum; run the build again." >&2
  exit 1
fi
mkdir -p "$PLUGIN/node/bin"
tar -xzf "$NODE_CACHE/$NODE_DIST.tar.gz" -C "$NODE_CACHE"
cp "$NODE_CACHE/$NODE_DIST/bin/node" "$PLUGIN/node/bin/node"
cp "$NODE_CACHE/$NODE_DIST/LICENSE" "$PLUGIN/node/LICENSE"

cp package.json package-lock.json "$PLUGIN/"
cp -R dist hooks opencode "$PLUGIN/"
(cd "$PLUGIN" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund)

# SwiftPM resource bundles are looked up next to the executable; frameworks from binary
# targets are found through rpaths.
shopt -s nullglob
for bundle in "$BIN"/*.bundle; do
  cp -R "$bundle" "$BRIDGE_DIR/"
  cp -R "$bundle" "$CONTENTS/Resources/"
done
for framework in "$BIN"/*.framework; do
  cp -R "$framework" "$BRIDGE_DIR/"
  cp -R "$framework" "$CONTENTS/Frameworks/"
done
if ! otool -l "$CONTENTS/MacOS/AgenticVoice" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS/MacOS/AgenticVoice"
fi

# Sign inside out: nested code first, then the app.
for framework in "$BRIDGE_DIR"/*.framework "$CONTENTS/Frameworks"/*.framework; do
  codesign --force --sign - "$framework"
done
codesign --force --sign - "$BRIDGE_DIR/TTSBridge"
# Node keeps its official signature: re-signing would only replace it with an ad-hoc one.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Move it to /Applications (launch at login works best from there), then open it."
