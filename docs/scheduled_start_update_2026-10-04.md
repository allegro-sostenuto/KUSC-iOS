# Scheduled-start update — 4 October 2026

Build **25**, source `29f43edc35ea005c96165fbaf8383b2ae10c17dc`, passes [the complete CI workflow](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/37207716538).

## Behavior

The scheduling sheet offers two output modes:

| Mode | Behavior |
|---|---|
| Always speaker | Applies the public speaker override at preparation, even with headphones connected. Output changes and audio interruptions retain the request; playback retries when iOS permits it. |
| Selected output | Uses the confirmed system output's UID/transport identity. If unavailable or no longer selected, the chosen fallback is either the iPhone speaker or notification-only. Arbitrary remembered Bluetooth/AirPlay destinations cannot be reconnected programmatically. |

**Allow while unplugged** enables standby and scheduled playback on battery. Battery protection starts its countdown only while both unplugged and below the selected X%. It stops after Y continuous minutes in that condition. Charging or recovery to the threshold resets the countdown; unknown readings restart observation rather than inventing a low-battery condition. X cannot be below 25%, and Y cannot be below 20 minutes. The timer uses monotonic uptime. Protection remains active after the fade reaches normal volume.

The optional speaker-only **Ignore everything except battery** setting enables battery operation and retains playback intent through Pause, sleep timers, output changes, session interruptions and network failures. Explicit cancellation requires **Delete Scheduled Start** in the app. Battery protection can still stop playback, leaving the request visible. Stopping or deleting releases the audio session. A notification-permission failure does not disarm this mode.

Speaker recovery handles interruptions without a corresponding end event, including during silent standby. Unchanged output notifications do not restart the gain envelope. The selected-output speaker fallback remains on the speaker for that run. A ready stream still begins silently one minute early and fades over the final ten seconds; recovery after the target uses a fresh ten-second fade.

The power controls use black surfaces and borders in dark appearance, with accessible labels, values and adjustment actions. Normal starts continue to honor manual Pause, preserving existing rewind history after the scheduled fade finishes. Older saved requests and settings remain decodable.

## Verification

Xcode 26.6 (17F113), iPhoneOS SDK 26.5, iOS 26.5 simulator runtime:

- Both unsigned Release arm64 device packages build and validate.
- 113 portable tests pass in each device-build job.
- 24 focused native audio tests pass.
- 162 hosted tests and seven UI tests pass on each of the iPhone 17 and SE simulator profiles.
- The hosted scheduling suite covers headset loss, selected-output fallbacks, continuous low-battery timing and resets, persistent Pause/sleep behavior, explicit deletion, late callbacks, session/network recovery, and preservation of the rewind transport when a normal scheduled start is paused after its fade.
- The UI suite checks accessible battery values, mandatory battery operation in persistent mode, reachable controls, and 31 native layout captures per profile, including the new power card in light/dark appearance.

Both downloaded IPAs were checked against the GitHub artifact digest, embedded source/build record, checksum manifest, bundle versions, device architecture, deployment target and unsigned packaging.

| Package | SHA-256 |
|---|---|
| KUSC-17-unsigned.ipa | `4f65cc9548fec883f256d3c6dc0dbec18cf42977067ef958010aa4761eb655fc` |
| KUSC-SE-unsigned.ipa | `0d4a10f654594022af6ed8d97c7814a697dc73b9e55dcd478ac2e2c2d3922f43` |

Local packages, test logs and verification records are under `artifacts/ci-37207716538/`. The iPhone 17 app and Live Activity extension both identify as version 1.0, build 25. Simulator layout fixtures retain the project's Debug build number 1; their capture manifests and source record identify the matching source.

Visual inspection used the checksum-verified build 24 captures of both phone profiles under `artifacts/ci-37169574129/`, confirming black bordered power controls and readable layouts. The UI source, UI tests and capture collector are unchanged between builds 24 and 25; build 25 repeats all 31 captures and the interaction suite on each profile.

## Physical-device checks

Real headphone, Bluetooth, USB/wired and AirPlay routing, audible fades, locked/background behavior and the twenty-minute battery safeguard still require the owner's iPhone. Follow the October checklist in [manual_test_plan.md](manual_test_plan.md). An easy battery test is to choose X above the current battery percentage, keep Y at 20 minutes, and unplug; charging before expiry must reset the countdown.

iOS still controls audio-session availability and process execution. Calls may delay playback, and force-quit, termination, reboot or a powered-off phone prevent a guaranteed automatic start. A retained persistent request can recover when KUSC is relaunched, but battery observation restarts after process death. These limits are detailed in [platform_limits.md](platform_limits.md).
