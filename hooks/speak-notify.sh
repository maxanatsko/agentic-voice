#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEXT="${1:-Notification.}"
node "$REPO_DIR/dist/src/cli.js" "$TEXT" >/dev/null 2>&1 || true
