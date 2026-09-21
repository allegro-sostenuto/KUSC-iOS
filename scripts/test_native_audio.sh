#!/bin/bash
# Fast native media check, before the longer layout capture jobs finish.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ] || ! command -v xcodebuild >/dev/null; then
    echo 'Native audio tests require macOS and Xcode.' >&2
    exit 1
fi
output="${1:-artifacts/native-audio}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/kusc-audio.XXXXXX")"
device=""
cleanup() {
    if [ -n "$device" ]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
    fi
    case "$work" in */kusc-audio.*) rm -rf "$work" ;; esac
}
trap cleanup EXIT
device="$(python3 - <<'PY'
import json, subprocess
def sim(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True)
runtimes = [r for r in json.loads(sim('list', 'runtimes', '--json'))['runtimes']
            if r.get('isAvailable') and 'iOS' in r['name']]
runtimes.sort(key=lambda r: tuple(map(int, r['version'].split('.'))), reverse=True)
if not runtimes or int(runtimes[0]['version'].split('.')[0]) < 26:
    raise SystemExit('An installed iOS 26+ simulator runtime is required.')
types = json.loads(sim('list', 'devicetypes', '--json'))['devicetypes']
kind = next((t for name in ['iPhone 17', 'iPhone 17 Pro'] for t in types if t['name'] == name), None)
if kind is None:
    raise SystemExit('An iPhone 17 simulator device type is required.')
print(sim('create', 'KUSC native audio', kind['identifier'], runtimes[0]['identifier']).strip())
PY
)"
python3 scripts/generate_project.py
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcodebuild -project KUSC.xcodeproj -scheme KUSC-SE -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$work/build" \
    -resultBundlePath "$output/Audio.xcresult" -parallel-testing-enabled NO \
    -only-testing:KUSCTests/BufferedAudioSampleSourceTests \
    -only-testing:KUSCTests/BufferedAudioRendererTests \
    -only-testing:KUSCTests/AudioEngineIntegrationTests \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
    test 2>&1 | tee "$output/tests.log"
