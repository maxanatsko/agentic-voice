#!/usr/bin/env bash
# Builds "build/Agentic Voice.app" from source: the menu bar app, plus the Node MCP server,
# hooks and TTSBridge laid out under Contents/Resources/agentic-voice exactly as in this
# repository, so MCP's paths work unchanged. Ad-hoc signed for this Mac; not notarized.
set -euo pipefail

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
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Move it to /Applications (launch at login works best from there), then open it."
