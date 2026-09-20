#!/bin/bash
# Capture real SwiftUI/UIKit simulator output with DEBUG-only, silent layout data.
# Usage: bash scripts/capture_ui.sh [artifact-directory] [all|iphone17|se]
# KUSC_CAPTURE_PROFILE selects the profile when the second argument is omitted.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ] || ! command -v xcodebuild >/dev/null; then
    echo 'Native UI capture requires macOS, Xcode and an installed iOS simulator runtime.' >&2
    exit 1
fi

root="$(pwd)"
output="${1:-artifacts/native-ui}"
profile="${2:-${KUSC_CAPTURE_PROFILE:-all}}"
case "$profile" in
    all|iphone17|se) ;;
    *) echo 'Capture profile must be all, iphone17, or se.' >&2; exit 2 ;;
esac
mkdir -p "$output"
output="$(cd "$output" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/kusc-ui.XXXXXX")"
baseline="$work/baseline"
baseline_ref="${KUSC_BASELINE_REF:-1cc5ae6236f9d113c61c10778ee1aa3ccf926715}"
simulators="$work/simulators.tsv"
touch "$simulators"
report="$output/capture-report.txt"
cleanup() {
    while IFS='|' read -r label device type runtime; do
        [ -n "$device" ] || continue
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
    done < "$simulators"
    if [ -d "$baseline" ]; then git worktree remove --force "$baseline" >/dev/null 2>&1 || true; fi
    # Only this invocation's mktemp directory is removed.
    case "$work" in */kusc-ui.*) rm -rf "$work" ;; esac
}
trap cleanup EXIT

{
    echo "Native simulator layout capture"
    echo "Commit: $(git rev-parse HEAD)"
    echo "Requested device profile: $profile"
    echo "UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    xcodebuild -version
    echo 'Fixtures are synthetic layout state; audio and network are disabled.'
    echo 'Fixture work/host/performer names are labeled test data. Artwork is unavailable.'
    echo 'Output names, when available, come from the simulator audio session; no devices are fabricated.'
    echo 'These screenshots do not verify real playback, background scheduling, Bluetooth or AirPlay.'
    echo 'More menu capture is requested by native XCUITest using a real tap; test outcomes are recorded below.'
    echo 'All updated-layout screenshots use KUSC-SE shared UI; both simulator schemes are built, and KUSC-17 is installed on the iPhone17 profile.'
    echo 'Updated layouts wait for visible fixture controls in XCTest; no fixed launch delay accepts a blank image.'
    echo 'Large text uses accessibility3. Landscape rotates XCUIDevice and asserts the logical app.frame orientation.'
    echo 'Full-screen XCUIScreen captures avoid app-window cropping; raw dimensions, EXIF and logical orientation are recorded independently.'
    echo 'Named PNGs are copied byte-for-byte from XCTest attachments; pixels are never rotated or synthesized.'
    echo 'Open each profile index.html for a CSS-oriented display of the unchanged native PNGs.'
} > "$report"

# Create our own devices from installed runtimes; never reset a developer's simulator.
python3 - "$simulators" "$profile" <<'PY'
import json, subprocess, sys
def sim(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True)
runtimes = [r for r in json.loads(sim('list', 'runtimes', '--json'))['runtimes']
            if r.get('isAvailable') and 'iOS' in r['name']]
def version(value): return tuple(int(x) for x in value.split('.'))
runtimes.sort(key=lambda r: version(r['version']), reverse=True)
if not runtimes or version(runtimes[0]['version']) < (26,):
    raise SystemExit('An installed iOS 26+ simulator runtime is required; none was found.')
runtime = runtimes[0]['identifier']
types = json.loads(sim('list', 'devicetypes', '--json'))['devicetypes']
def choose(names):
    for name in names:
        result = next((t for t in types if t['name'] == name), None)
        if result: return result
    return None
selections = [('iphone17', choose(['iPhone 17', 'iPhone 17 Pro'])),
              ('se', choose(['iPhone SE (3rd generation)', 'iPhone SE (2nd generation)']))]
if sys.argv[2] != 'all':
    selections = [entry for entry in selections if entry[0] == sys.argv[2]]
with open(sys.argv[1], 'w') as stream:
    for label, kind in selections:
        if not kind:
            raise SystemExit(f'Required simulator device type unavailable: {label}')
        device = sim('create', 'KUSC layout '+label, kind['identifier'], runtime).strip()
        stream.write('|'.join([label, device, kind['name'], runtime])+'\n')
        stream.flush()
PY

python3 scripts/generate_project.py
build_app() {
    local source="$1" scheme="$2" destination="$3" log="$4"
    xcodebuild -project "$source/KUSC.xcodeproj" -scheme "$scheme" \
        -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$destination" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build > "$log" 2>&1
}
build_app "$root" KUSC-SE "$work/current-se" "$output/build-KUSC-SE.log"
build_app "$root" KUSC-17 "$work/current-modern" "$output/build-KUSC-17.log"

# The original UI is built from the recorded starting commit. Its sole source
# change is a fixture guard suppressing launch/foreground work, not a UI edit.
# This makes the common idle / unavailable-artwork comparison deterministic.
baseline_app=""
if git cat-file -e "$baseline_ref^{commit}" 2>/dev/null; then
    git worktree add --detach "$baseline" "$baseline_ref" >> "$report" 2>&1
    python3 - "$baseline/Shared/AppModel.swift" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
for signature in ['func launch() {', 'func onForeground() {']:
    if text.count(signature) != 1:
        raise SystemExit('Cannot inject baseline fixture guard: '+signature)
    text = text.replace(signature, signature+'\n        if ProcessInfo.processInfo.environment["KUSC_UI_BASELINE"] == "1" { settings.autoplay = false; return }')
path.write_text(text)
PY
    if build_app "$baseline" KUSC-SE "$work/before" "$output/build-baseline.log"; then
        baseline_app="$work/before/Build/Products/Debug-iphonesimulator/KUSC-SE.app"
        echo "Baseline built: $baseline_ref; only launch/foreground networking was disabled." >> "$report"
    else
        echo 'UNEXECUTED: baseline capture; original source failed to build. See build-baseline.log.' >> "$report"
    fi
else
    echo "UNEXECUTED: baseline capture; commit $baseline_ref is unavailable locally." >> "$report"
fi

test_failures=0
while IFS='|' read -r label device type runtime; do
    mkdir -p "$output/$label"
    echo "Device: $label = $type; runtime=$runtime; simulator=$device" >> "$report"
    xcrun simctl boot "$device"
    xcrun simctl bootstatus "$device" -b
    xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100
    if [ -n "$baseline_app" ]; then
        bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$baseline_app/Info.plist")"
        xcrun simctl install "$device" "$baseline_app"
        SIMCTL_CHILD_KUSC_UI_BASELINE=1 xcrun simctl launch "$device" "$bundle" >> "$report" 2>&1
        sleep 3
        xcrun simctl io "$device" screenshot "$output/$label/before-unavailable.png" >> "$report" 2>&1
        xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true
        xcrun simctl uninstall "$device" "$bundle"
    fi
    if [ "$label" = iphone17 ]; then
        app="$work/current-modern/Build/Products/Debug-iphonesimulator/KUSC-17.app"
    else
        app="$work/current-se/Build/Products/Debug-iphonesimulator/KUSC-SE.app"
    fi
    bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")"
    xcrun simctl install "$device" "$app"
    result="$output/$label/Interactions.xcresult"
    if xcodebuild -project "$root/KUSC.xcodeproj" -scheme KUSC-SE -configuration Debug \
        -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$work/ui-tests" \
        -resultBundlePath "$result" -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
        test 2>&1 | tee "$output/$label/ui-tests.log"; then
        echo "PASS: $label hosted KUSCTests and native More menu, landscape slider/paging and large-text slider/paging tests." >> "$report"
    else
        echo "FAIL: $label hosted unit or native interaction tests; inspect ui-tests.log and Interactions.xcresult." >> "$report"
        test_failures=$((test_failures + 1))
    fi
    if xcrun xcresulttool export attachments --path "$result" \
        --output-path "$output/$label/test-attachments" >> "$report" 2>&1; then
        if ! python3 scripts/collect_ui_attachments.py "$output/$label/test-attachments" \
            "$output/$label" >> "$report" 2>&1; then
            echo "FAIL: $label native screenshot collection is incomplete or has invalid logical orientation metadata." >> "$report"
            test_failures=$((test_failures + 1))
        fi
    else
        echo "Attachment export unavailable for $label; original Interactions.xcresult is preserved." >> "$report"
        test_failures=$((test_failures + 1))
    fi
    xcrun simctl shutdown "$device"
done < "$simulators"

echo 'Native capture completed. Inspect PNGs for layout; capture-report.txt lists the precise limits.' >> "$report"
echo "Screenshots and evidence: $output"
if [ "$test_failures" -ne 0 ]; then exit 1; fi
