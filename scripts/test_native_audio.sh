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
work="$(mktemp -d "${TMPDIR:-/tmp}/philharmonic-audio.XXXXXX")"
device=""
cleanup() {
    if [ -n "$device" ]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
    fi
    case "$work" in */philharmonic-audio.*) rm -rf "$work" ;; esac
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
print(sim('create', 'Philharmonic native audio', kind['identifier'], runtimes[0]['identifier']).strip())
PY
)"
python3 scripts/generate_project.py
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
tests=(
    -only-testing:PhilharmonicTests/BufferedAudioSampleSourceTests
    -only-testing:PhilharmonicTests/BufferedAudioRendererTests
    -only-testing:PhilharmonicTests/AudioEngineIntegrationTests
    -only-testing:PhilharmonicTests/LiveOnlySettingsTests
    -only-testing:PhilharmonicTests/ScheduleModelBoundaryTests
    -only-testing:PhilharmonicTests/SpeakerVolumeSetupTests
    -only-testing:PhilharmonicTests/StationSwitchTests
    -only-testing:PhilharmonicTests/StationSourcePlaybackTests
)
if [ "${PHILHARMONIC_STATION_SOURCES_ONLY:-0}" = 1 ]; then
    tests=(
        -only-testing:PhilharmonicTests/StationSourcePlaybackTests
        -only-testing:PhilharmonicTests/StationCatalogTests
        -only-testing:PhilharmonicTests/LiveOnlySettingsTests
        -only-testing:PhilharmonicTests/StationSwitchTests
    )
fi
if [ "${PHILHARMONIC_STATION_BOUNDARIES_ONLY:-0}" = 1 ]; then
    tests=(
        -only-testing:PhilharmonicTests/StationSwitchTests
        -only-testing:PhilharmonicTests/LiveOnlySettingsTests
    )
fi
if [ "${PHILHARMONIC_DEBUG_EVENTS_ONLY:-0}" = 1 ]; then
    tests=(
        -only-testing:PhilharmonicTests/PlaybackDiagnosticsIntegrationTests
        -only-testing:PhilharmonicTests/MediaServicesRecoveryTests
        -only-testing:PhilharmonicTests/ScheduleModelBoundaryTests
        -only-testing:PhilharmonicTests/SpeakerVolumeSetupTests
        -only-testing:PhilharmonicTests/StationSwitchTests
        -only-testing:PhilharmonicTests/LiveOnlySettingsTests
        -only-testing:PhilharmonicTests/AudioEngineIntegrationTests/testProgressiveStreamsNeverEnterTheHLSPreparationPath
        -only-testing:PhilharmonicTests/AudioEngineIntegrationTests/testNonKUSCHLSUsesNativePlayerWithoutKUSCManifestRequirements
        -only-testing:PhilharmonicTests/AudioEngineIntegrationTests/testStationReplacementRetiresLatePreparedAudio
        -only-testing:PhilharmonicTests/AudioEngineIntegrationTests/testOrdinaryEngineIgnoresLegacyRetentionAndCannotSeek
        -only-testing:PhilharmonicTests/AudioEngineIntegrationTests/testPauseWinsAfterPlayWhileDirectReplacementIsStillPreparing
    )
fi
if [ "${PHILHARMONIC_SPEAKER_REPRO_ONLY:-0}" = 1 ]; then
    tests=(-only-testing:PhilharmonicTests/ScheduledSpeakerCategoryTests)
fi
set +e
xcodebuild -project Philharmonic.xcodeproj -scheme Philharmonic-SE -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$work/build" \
    -resultBundlePath "$output/Audio.xcresult" -parallel-testing-enabled NO \
    "${tests[@]}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
    test 2>&1 | tee "$output/tests.log"
test_status=${PIPESTATUS[0]}
set -e

export_status=0
if [ -d "$output/Audio.xcresult" ]; then
    xcrun xcresulttool export attachments --path "$output/Audio.xcresult" --output-path "$output/attachments" || export_status=$?
fi
if [ "$test_status" -ne 0 ]; then exit "$test_status"; fi
exit "$export_status"
