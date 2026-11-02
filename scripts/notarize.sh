#!/bin/bash
# Submits a built, Developer ID-signed app to Apple's notary service and staples
# the ticket to it. Requires:
#   CODESIGN_IDENTITY  a "Developer ID Application: ..." identity
#   NOTARY_PROFILE     a notarytool keychain profile (default: AC_PASSWORD)
#
# Create the profile once with:
#   xcrun notarytool store-credentials AC_PASSWORD \
#     --apple-id you@example.com --team-id TEAMID --password app-specific-password
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/Awake Lock.app}"
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

if [[ "${CODESIGN_IDENTITY:--}" == "-" ]]; then
  printf 'Refusing to notarize an ad-hoc build. Set CODESIGN_IDENTITY first.\n' >&2
  exit 1
fi
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Developer ID Application"; then
  printf 'App is not signed with a Developer ID identity: %s\n' "$APP" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ZIP="$WORK/$(basename "$APP" .app).zip"

printf 'Submitting %s to the notary service (this can take a few minutes)…\n' "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
printf '\nNotarized and stapled: %s\n' "$APP"
