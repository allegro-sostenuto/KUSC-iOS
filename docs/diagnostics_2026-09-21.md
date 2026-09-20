# Diagnose history clearing near 14 seconds

## Observed on the owner's device

On iPhone 17 / iOS 26 with retention enabled, the left history label reaches `−00:14` and never grows further. During playback the app then shows Reconnecting. When paused with the app in the foreground, history disappears and the screen shows Paused / Collecting audio for rewind…. Retention Off does not exhibit the reported intermittent pauses. These are user observations, not simulator audio measurements.

There is no configured 14-second retention limit. The current failure path clears buffered state; when playback intent is paused it stops acquisition without retrying. That path is consistent with the display, but the triggering download, parser, player or clock error is not yet known. No root cause or audio fix is claimed.

## Diagnostic update

Settings → Playback Diagnostics is available in ordinary Release builds. Capture is opt-in and remains in memory for the current app launch. The first failure freezes the report before engine cancellation, publication or the model's synchronous teardown. Reconnects cannot replace it; Start New Capture explicitly replaces the previous report. Copy Report and Share Report require a user action. Nothing is uploaded automatically and no audio is included.

The report contains app/build, iOS, generic device model, output port types, settings, monotonic elapsed and UTC wall times, acquisition stage and HLS sequence, response status/byte counts/timings, declared and encoded segment durations, acquisition/retention/playback clocks, queue count and first three segment timestamps, playback intent and player state. It includes NSError domain/code/description and up to four errors in the underlying chain. It excludes raw request URLs, friendly route names/UIDs, arbitrary error userInfo and local file paths; URL/path/credential redaction also applies to free-text events. The bounded ring retains 256 entries of at most 1,000 UTF-8 bytes each; longer failure summaries use numbered entries. The full report stays below 300 KiB.

The empty-buffer message now explains that collection stopped after an audio error instead of falsely saying it is still collecting. Acquisition rules, retention limits, player timeouts and recovery policy are unchanged. Instrumentation adds work and actor handoffs, so failure disappearing in this build alone would not establish a playback fix.

## Owner test after installing the diagnostic IPA

1. Disable Auto-play on launch, set Rolling buffer to 5 minutes, and cancel any active sleep timer or scheduled start. Force-quit KUSC from the app switcher, then reopen it to start with empty history and no automatic playback. Do this before capture; merely leaving the app does not reset audio. Keep the same network and output as the previous failing test.
2. Open Settings → Playback Diagnostics → Start New Capture. Return to Now Playing and tap Play. Wait until you hear audio and the left history label appears, then pause before it reaches `−00:14`. Do not pause while it still says Connecting. If it fails before you can pause, save that report anyway.
3. Keep KUSC open and unlocked for 45 seconds or until history disappears. Note the exact left label and visible state; do not start a second capture yet.
4. Return to Playback Diagnostics. If it says Failure captured, use Copy Report and paste the report into this task, or use Share Report. If it still says Recording after 45 seconds, tap Stop Capture and share that report instead. Keep the app open until the report is copied/shared, because it is memory-only.
5. Only after saving that report, start a new capture, return to Now Playing, tap Play again and stay at the live edge for 60 seconds without pausing. Start New Capture resets only diagnostics; it does not start audio. Send the second report separately. If either test no longer fails, report the maximum left history value observed.

The report's first failure origin and underlying error determine the next investigation. An acquisition error should be evaluated with the preceding segment/response events; a player error with item/queue state; a monitor timeout with the last confirmed playback and acquisition times. Retest a targeted fix using the same conditions before broader route/background acceptance.

## Validation status

Local structural checks pass; they parse Swift and validate project/resource structure without type-checking or running XCTest. New portable tests cover explicit capture lifecycle, first-failure preservation, retry protection, bounded storage and Unicode, wall-clock changes, URL/path/credential redaction, underlying-error bounds/cycles, and long error-chain preservation. Two hosted tests exercise first-failure evidence before synchronous paused-engine teardown and the corrected paused UI state. A new native UI test navigates to diagnostics, starts/stops capture, verifies report controls remain usable, and attaches a screenshot.

[Build 7, run 35523118927](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/35523118927) at `2c0b98866d4bbe65d7c1d3f7c844cb1001cdbc4a` passed both Release device builds. The iPhone 17 build log confirms all 87 portable tests passed, including all 12 diagnostic-log tests. Both simulator jobs stopped before running hosted/UI tests: the Swift compiler timed out while type-checking the Debug-only segment fixture in AppModel. The follow-up splits that fixture and the equivalent test fixture into typed intermediate values; its native test run remains pending. Build 7 is not an all-checks-passing result.
