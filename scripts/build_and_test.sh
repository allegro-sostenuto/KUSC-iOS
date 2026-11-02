#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
    echo 'Xcode on macOS is required for iOS builds.' >&2
    exit 1
fi
swift test
for scheme in Philharmonic-SE Philharmonic-17 Philharmonic-SE-CarPlay Philharmonic-17-CarPlay; do
    xcodebuild -project Philharmonic.xcodeproj -scheme "$scheme" -configuration Debug \
        -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
done
# To run the hosted tests: xcodebuild -project Philharmonic.xcodeproj -scheme Philharmonic-SE \
#   -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' test
