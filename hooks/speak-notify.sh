#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$(basename "$PWD")"
REASON="${1:-finished}"

case "$REASON" in
  finished) TEXT="$PROJECT finished." ;;
  input) TEXT="$PROJECT needs your input." ;;
  *) TEXT="$PROJECT: $REASON" ;;
esac

node "$REPO_DIR/dist/src/cli.js" "$TEXT" >/dev/null 2>&1 || true
