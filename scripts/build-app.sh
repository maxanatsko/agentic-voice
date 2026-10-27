#!/usr/bin/env bash
# Builds "build/Agentic Voice.app" from source: the menu bar app, plus the agentic-voice command
# (MCP server, CLI, client installer), TTSBridge, hooks and the opencode plugin laid out under
# Contents/Resources/agentic-voice exactly as in this repository, so their paths work
# unchanged. Ad-hoc signed for this Mac; not notarized.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Agentic Voice.app"
CONTENTS="$APP/Contents"
PLUGIN="$CONTENTS/Resources/agentic-voice"
BRIDGE_DIR="$PLUGIN/bridge/.build/release"

cd "$ROOT"
swift build -c release --package-path bridge --product TTSBridge
swift build -c release --package-path bridge --product agentic-voice
swift build -c release --package-path bridge --product AgenticVoice
BIN="$(swift build -c release --package-path bridge --show-bin-path)"
scripts/build-mlx-metallib.sh

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Frameworks" "$BRIDGE_DIR"
cp bridge/AgenticVoice-Info.plist "$CONTENTS/Info.plist"
cp "$BIN/AgenticVoice" "$CONTENTS/MacOS/AgenticVoice"
cp "$BIN/TTSBridge" "$BRIDGE_DIR/TTSBridge"
cp "$BIN/agentic-voice" "$BRIDGE_DIR/agentic-voice"
# MLX (the Voxtral voices) loads mlx.metallib from beside the binary that links it.
cp "$BIN/mlx.metallib" "$BRIDGE_DIR/mlx.metallib"
cp -R hooks opencode "$PLUGIN/"

# The app icon: a Liquid Glass icon from Icon Composer (the overlay's breathing orb). actool
# compiles it into Assets.car, which macOS renders in its default, dark, clear and tinted looks.
xcrun actool bridge/AppIcon.icon --compile "$CONTENTS/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "$ROOT/build/AppIcon-partial.plist" >/dev/null

# SwiftPM resource bundles are looked up next to the executable; frameworks from binary
# targets are found through rpaths.
shopt -s nullglob
for bundle in "$BIN"/*.bundle; do
  cp -R "$bundle" "$BRIDGE_DIR/"
  cp -R "$bundle" "$CONTENTS/Resources/"
done
# In the app, MLX runs inside AgenticVoice and finds its shaders as default.metallib in the Cmlx
# bundle; SwiftPM's own copy there is partial, so replace it with the full library.
cp "$BIN/mlx.metallib" "$CONTENTS/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
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
codesign --force --sign - "$BRIDGE_DIR/agentic-voice"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Move it to /Applications (launch at login works best from there), then open it."
