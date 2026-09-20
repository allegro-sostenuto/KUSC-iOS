#!/bin/bash
# Build a device IPA for subsequent signing/import in AltStore Classic.
# Usage: bash scripts/build_unsigned_ipa.sh KUSC-SE|KUSC-17 [output-directory]
# Requires macOS and Xcode 26.x. No Apple account or signing material is used.
set -euo pipefail
cd "$(dirname "$0")/.."

scheme="${1:-}"
case "$scheme" in
  KUSC-SE|KUSC-17) ;;
  *) echo 'Usage: build_unsigned_ipa.sh KUSC-SE|KUSC-17 [output-directory]' >&2; exit 2 ;;
esac
if [ "$(uname -s)" != Darwin ] || ! command -v xcodebuild >/dev/null; then
  echo 'This device build requires Xcode on macOS; use the included GitHub Actions workflow.' >&2
  exit 1
fi

output="${2:-dist}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
build_number="${KUSC_BUILD_NUMBER:-1}"
case "$build_number" in
  ''|*[!0-9]*) echo 'KUSC_BUILD_NUMBER must be a positive integer.' >&2; exit 2 ;;
esac
if [ "$build_number" -lt 1 ]; then
  echo 'KUSC_BUILD_NUMBER must be a positive integer.' >&2
  exit 2
fi

# Keep the identifiers from the project configuration stable across updates.
bundle_prefix="$(python3 - <<'PY'
import re
from pathlib import Path
text = Path('Configuration/Signing.xcconfig').read_text()
matches = re.findall(r'^\s*KUSC_BUNDLE_PREFIX\s*=\s*([A-Za-z0-9.-]+)\s*$', text, re.M)
if len(matches) != 1:
    raise SystemExit('Expected exactly one literal KUSC_BUNDLE_PREFIX in Configuration/Signing.xcconfig')
print(matches[0])
PY
)"
work="$(mktemp -d "${TMPDIR:-/tmp}/kusc-ipa.XXXXXX")"
trap 'rm -rf "$work"' EXIT

xcodebuild \
  -project KUSC.xcodeproj \
  -scheme "$scheme" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$work/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" PROVISIONING_PROFILE="" \
  "CURRENT_PROJECT_VERSION=$build_number" \
  clean build

app="$work/DerivedData/Build/Products/Release-iphoneos/$scheme.app"
if [ ! -d "$app" ]; then
  echo "Expected device app was not built: $app" >&2
  exit 1
fi
mkdir -p "$work/package/Payload"
/usr/bin/ditto "$app" "$work/package/Payload/$scheme.app"
ipa="$output/$scheme-unsigned.ipa"
# Starting a fresh archive prevents files from an earlier build surviving.
rm -f "$ipa"
(cd "$work/package" && /usr/bin/ditto -c -k --norsrc --keepParent Payload "$ipa")
python3 scripts/validate_ipa.py "$ipa" --scheme "$scheme" --bundle-prefix "$bundle_prefix"
(cd "$output" && shasum -a 256 "$scheme-unsigned.ipa" > "$scheme-unsigned.ipa.sha256")
{
  echo "Scheme: $scheme"
  echo "Configuration: Release (ordinary iPhone target; CarPlay excluded)"
  echo "Build number: $build_number"
  echo "Bundle prefix: $bundle_prefix"
  echo "Source commit: $(git rev-parse HEAD 2>/dev/null || echo 'unavailable')"
  echo "Built UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  xcodebuild -version
  echo "iPhoneOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
  echo 'Signing: app and extension have no owner signing identity or provisioning; AltStore must sign before installation.'
  echo 'Embedded libraries may retain verified Apple vendor signatures.'
  echo 'Validation: structure, bundle identifiers, arm64 iOS platform, deployment targets and signing material checked.'
  echo 'Device launch and automatic AltStore refresh require testing on the receiving phone.'
} > "$output/$scheme-build-info.txt"
echo "Created $ipa"
