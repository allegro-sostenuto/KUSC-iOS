#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
    echo 'Xcode on macOS is required for iOS builds.' >&2
    exit 1
fi
swift test
for scheme in KUSC-SE KUSC-17 KUSC-SE-CarPlay KUSC-17-CarPlay; do
    xcodebuild -project KUSC.xcodeproj -scheme "$scheme" -configuration Debug \
        -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
done
# To run the hosted tests: xcodebuild -project KUSC.xcodeproj -scheme KUSC-SE \
#   -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' test
