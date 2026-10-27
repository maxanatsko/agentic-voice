#!/usr/bin/env bash
# Builds MLX's Metal shader library, mlx.metallib, next to the release binaries in
# bridge/.build/release. The Voxtral voices run on MLX, which fails with "Failed to load the
# default metallib" without it (SwiftPM doesn't compile Metal sources). Adapted from
# speech-swift's scripts/build_mlx_metallib.sh (Apache 2.0).
#
# Needs Xcode's Metal toolchain: xcodebuild -downloadComponent MetalToolchain
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$(swift build -c release --package-path "$ROOT/bridge" --show-bin-path)"
MLX="$ROOT/bridge/.build/checkouts/mlx-swift/Source/Cmlx/mlx"
KERNELS="$MLX/mlx/backend/metal/kernels"
OUT="$BIN/mlx.metallib"

if [[ ! -d "$KERNELS" ]]; then
  echo "error: MLX kernels not found at $KERNELS; run swift build first" >&2
  exit 1
fi

# Rebuild only when a kernel source or header changed since the last build.
if [[ -f "$OUT" ]] && [[ -z "$(find "$KERNELS" -newer "$OUT" \( -name '*.metal' -o -name '*.h' \) -print -quit)" ]]; then
  echo "mlx.metallib is up to date"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
AIR=()
# The *_nax kernels need newer GPUs and are skipped, as upstream does.
while IFS= read -r source; do
  air="$TMP/$(printf '%s' "${source#"$KERNELS/"}" | shasum -a 256 | cut -c1-16).air"
  if ! xcrun -sdk macosx metal -x metal -std=metal3.2 -mmacosx-version-min=26.0 -g0 -fno-fast-math \
      -Wno-c++17-extensions -Wno-c++20-extensions \
      -c "$source" -I"$KERNELS" -I"$MLX" -o "$air" 2>"$TMP/metal.err"; then
    grep -q "missing Metal Toolchain" "$TMP/metal.err" && echo "error: run xcodebuild -downloadComponent MetalToolchain" >&2
    cat "$TMP/metal.err" >&2
    exit 1
  fi
  AIR+=("$air")
done < <(find "$KERNELS" -type f -name '*.metal' ! -name '*_nax.metal' | LC_ALL=C sort)

xcrun -sdk macosx metallib "${AIR[@]}" -o "$TMP/mlx.metallib"
mv "$TMP/mlx.metallib" "$OUT"
echo "Built $OUT"
