#!/bin/bash
# Builds a universal (arm64 + x86_64) Awake Lock.app.
#
# Signing is controlled by CODESIGN_IDENTITY:
#   unset or "-"  ad-hoc signature (works locally, Gatekeeper prompts on download)
#   "Developer ID Application: ..."  hardened runtime + secure timestamp
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Awake Lock.app"
BIN="$APP/Contents/MacOS/AwakeLock"
HELPER="$APP/Contents/Resources/awake-lock-helper"
ENTITLEMENTS="$ROOT/Resources/AwakeLock.entitlements"
MIN_MACOS="13.0"
IDENTITY="${CODESIGN_IDENTITY:--}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -target "$arch-apple-macosx$MIN_MACOS" \
    -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement \
    "$ROOT/Sources/main.swift" "$ROOT/Sources/Panel.swift" -o "$WORK/AwakeLock-$arch"
  swiftc -swift-version 5 -O -target "$arch-apple-macosx$MIN_MACOS" -framework IOKit \
    "$ROOT/Sources/helper.swift" -o "$WORK/awake-lock-helper-$arch"
done
lipo -create "$WORK/AwakeLock-arm64" "$WORK/AwakeLock-x86_64" -output "$BIN"
lipo -create "$WORK/awake-lock-helper-arm64" "$WORK/awake-lock-helper-x86_64" -output "$HELPER"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AwakeLock.icns" "$APP/Contents/Resources/AwakeLock.icns"
cp "$ROOT/scripts/install-helper.sh" "$ROOT/scripts/uninstall-helper.sh" "$APP/Contents/Resources/"

if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$HELPER"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
else
  # Inside out: the nested helper must be sealed before the bundle that contains it.
  codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" "$HELPER"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" "$APP"
fi
codesign --verify --deep --strict "$APP"

for binary in "$BIN" "$HELPER"; do
  archs="$(lipo -archs "$binary")"
  grep -q arm64 <<<"$archs"
  grep -q x86_64 <<<"$archs"
done

"$BIN" --self-test
"$HELPER" --self-test
printf '\nBuilt universal (%s), identity %s: %s\n' "$(lipo -archs "$BIN")" "$IDENTITY" "$APP"
