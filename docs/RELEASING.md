# Releasing Awake Lock

Releases are built by `.github/workflows/release.yml` on any `v*` tag, or manually
through **Actions → Release → Run workflow**.

## Without an Apple Developer account

Nothing to configure. The workflow builds a universal, ad-hoc signed app, publishes
the zip, and notes in the release body that the build is not notarized. The Homebrew
cask clears the quarantine flag so tap installs launch without a prompt.

## With Developer ID signing and notarization

Add these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `CODESIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `MACOS_CERT_P12` | base64 of your exported `.p12` certificate |
| `MACOS_CERT_PASSWORD` | password for that `.p12` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | your 10-character team identifier |
| `APPLE_APP_PASSWORD` | app-specific password from appleid.apple.com |
| `TAP_TOKEN` | token with write access to `sayyidsyamil/homebrew-tap` |

Export the certificate with:

```bash
security find-identity -v -p codesigning
# then, in Keychain Access: select the Developer ID Application identity,
# export as .p12, and run:
base64 -i DeveloperID.p12 | pbcopy
```

`TAP_TOKEN` is optional and only enables the automatic cask checksum update.

The nested `awake-lock-helper` is signed before the enclosing bundle, which is what
notarization requires; do not reorder the signing steps in `scripts/build.sh`.

## Local notarized build

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool store-credentials AC_PASSWORD \
  --apple-id you@example.com --team-id TEAMID --password app-specific-password
bash scripts/build.sh
bash scripts/notarize.sh
```

## Cutting a release

```bash
git tag -a v0.2.0 -m "Awake Lock 0.2.0"
git push origin v0.2.0
```

The workflow sets `CFBundleShortVersionString` from the tag and `CFBundleVersion`
from the run number, so `Resources/Info.plist` does not need a manual bump.
