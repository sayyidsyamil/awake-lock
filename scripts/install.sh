#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Awake Lock.app"
if [[ ! -d "$APP" ]]; then bash "$ROOT/scripts/build.sh"; fi
if pgrep -x AwakeLock >/dev/null; then
  printf 'Quit Awake Lock before installing an update.\n' >&2
  exit 1
fi
mkdir -p "$HOME/Applications"
ditto "$APP" "$HOME/Applications/Awake Lock.app"
open "$HOME/Applications/Awake Lock.app"
printf 'Installed to %s/Applications/Awake Lock.app\n' "$HOME"
