#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Awake Lock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement \
  "$ROOT/Sources/main.swift" "$ROOT/Sources/Panel.swift" -o "$APP/Contents/MacOS/AwakeLock"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" -framework IOKit \
  "$ROOT/Sources/helper.swift" -o "$APP/Contents/Resources/awake-lock-helper"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AwakeLock.icns" "$APP/Contents/Resources/AwakeLock.icns"
cp "$ROOT/scripts/install-helper.sh" "$ROOT/scripts/uninstall-helper.sh" "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Resources/awake-lock-helper"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/AwakeLock" --self-test
"$APP/Contents/Resources/awake-lock-helper" --self-test
printf '\nBuilt: %s\n' "$APP"
