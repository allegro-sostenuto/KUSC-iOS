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

[Build 7, run 35523118927](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/35523118927) at `2c0b98866d4bbe65d7c1d3f7c844cb1001cdbc4a` passed both Release device builds and all 87 portable tests, including 12 diagnostic-log tests. Both simulator jobs stopped before hosted/UI tests because Swift timed out while type-checking the Debug-only segment fixture in AppModel. Build 7 was not an all-checks-passing result. The follow-up splits that fixture and its test equivalent into typed intermediate values.

[Build 8, run 35523594653](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/35523594653) builds source `9c6045f6e1cb0da01659132e24b6347571b810cc` with Xcode 26.6 (17F113) and the iPhoneOS 26.5 SDK. Both Release device jobs passed. Both downloaded artifact ZIP checksums match the expected download hashes; safe extraction and local `validate_ipa.py` checks passed. Each IPA's SHA-256 matches its packaged manifest. Packaged build information confirms the source commit and build 8; app and extension Info.plists agree on version 1.0 (8).

| Artifact | SHA-256 |
|---|---|
| KUSC-17.zip | `917cc0e90d89d91de1b271c7a47514a50bc6a6a94885963419d3c658c73711f6` |
| KUSC-17-unsigned.ipa | `898346d4f65bb0fae06ad59d0e3c9e524cf8b4d7701fa15785a218745f9a57ac` |
| KUSC-SE.zip | `33b3394ea51b75a3bba0885c07cef13c33e3e6ea01d7298d38df2bd882057a8f` |
| KUSC-SE-unsigned.ipa | `bc06f6d3d2fe4e623e0287f81eaccf5fc76cb85b38fbcf2639795e1b75d8a641` |

The KUSC-17 IPA is 857,401 bytes: arm64 iOS device code, iOS 26 minimum, with one matching Live Activity extension. The KUSC-SE IPA is 802,409 bytes: arm64 iOS device code, iOS 16 minimum, with no extension. Both are ordinary targets without an owner signing identity or provisioning; AltStore must sign them for installation. Local copies are under `artifacts/ci-35523594653/KUSC-17/` and `artifacts/ci-35523594653/KUSC-SE/`.

All four build 8 jobs passed. Each of the iPhone 17 and SE simulator jobs passed 100 hosted tests (87 core, seven engine, four scheduled-start, and two diagnostic model tests), plus five native UI tests. All 29 captured-image hashes per profile were validated against their native manifests, and the diagnostic screens were visually checked. Both simulator profiles use the iOS 26.5 runtime; the SE deployment target of iOS 16 does not establish an iOS 16 runtime test. The native fixtures exercise the shared KUSC-SE test host on both device profiles; both ordinary app targets also compile separately. Local native evidence is under `artifacts/ci-35523594653/iphone17-review/iphone17/` and `artifacts/ci-35523594653/se-review/se/`.

These results validate the diagnostic implementation, packaging, and the completed simulator checks. The subsequent owner report identifies lost program-date mapping when an HLS refresh advances from sequences 1–3 to 2–4 without repeating the date tag. The [clock carry-over correction](buffer_clock_fix_2026-09-21.md) tracks that investigation and its separate validation. Build 8 remains a diagnostic build, and simulator fixtures do not establish physical-device audio continuity or background/route behavior.
