# Scheduled-start update — 5 October 2026

Build **29**, source `b5097ffd01dc8da3a5565fe4eb4cc14dd32f64ae`, passes [the CI workflow](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/37312008040). This revision follows the owner's build 26 reports about stale interruption state, silent standby stopping other apps, and pulsing dark-menu text.

## Playback and scheduling

Silent standby and the final minute of muted station preparation allow other apps to play. At the selected time, KUSC takes audio focus, applies the output policy, and fades in over ten seconds. The fade now starts at the selected time so that preparing KUSC does not stop another app early.

| Mode | Automatic playback |
|---|---|
| Always speaker | Applies the public speaker override at the selected time, even with headphones connected. Disconnects and interruptions retain the request and retry when iOS permits. |
| Selected output | Uses the confirmed system output's UID/transport identity. If unavailable or no longer selected, the chosen fallback is either the iPhone speaker or notification-only. Arbitrary remembered Bluetooth/AirPlay destinations cannot be reconnected programmatically. |

**Play** immediately requests audio access, ignoring stale app interruption state and automatic schedule power/output restrictions. Manual playback uses the current system output. Failed activation retries every five seconds for the first minute, then every fifteen seconds; a changed output also triggers an immediate attempt. Automatic recovery defers while another app plays before the scheduled target. iOS can still deny activation during a call.

**Pause** always silences current audio and cancels playback retries without deleting the schedule. Before the target, audio stays paused until Play or the target time; after the target, it stays paused until Play. The pause is saved across relaunch. Manual playback before the target leaves the future start armed; manual Play after the target takes control of current playback. Battery protection applies to automatic scheduled operation, not that explicit manual override.

**Allow while unplugged** enables standby and scheduled playback on battery. Battery protection starts only while both unplugged and below X%. It stops after Y continuous minutes in that condition. Charging or recovery to the threshold resets the countdown; unknown readings restart observation. X cannot be below 25%. Y is adjustable from **1 to 20 minutes**, with 20 as the maximum and default; previously saved longer delays are clamped to 20. The timer uses monotonic uptime and remains active after automatic playback reaches normal volume.

The speaker-only **Ignore everything except battery** option enables battery operation and retains the schedule through sleep timers, output changes, session interruptions and network failures. Manual Pause still wins. Explicit cancellation uses **Delete Scheduled Start**; battery protection may stop audio while leaving the request visible. Notification permission failure does not disarm this mode.

## Reminder and menu

A reminder is requested two minutes before the start. Starts less than two minutes away get it immediately. Tapping the notification or its **Tap to cancel** action opens Scheduled Start scrolled to **Delete Scheduled Start**. Opening the reminder does not cancel the request or command playback. The existing target-time playback fallback is separate. Deleting/replacing a request removes both notifications; old request IDs cannot affect its replacement.

The More button keeps one native UIKit menu while playback publishes updates, with a stable appearance and tint. Dark controls and cards remain pure black with borders. The native menu's text brightness has a temporal simulator check, alongside navigation to the delete button.

## Verification

Xcode 26.6 (17F113), iPhoneOS SDK 26.5:

- Both unsigned Release arm64 device builds pass.
- 114 portable tests pass in the checked iPhone 17 device-build log.
- All 24 focused native audio tests pass.
- All 176 hosted tests and nine UI tests pass on each of the iPhone 17 and SE simulator profiles (iOS 26.5). The dark-menu brightness check and reminder-to-delete navigation check both pass on both profiles.
- Both profiles complete the existing 31 native layout captures and their collection/metadata validation. This revision does not claim a new manual visual review of every capture.
- Local structural validation passes for 52 Swift files and project resources. This Windows check does not type-check Swift or execute XCTest.

Both downloaded IPAs pass artifact-digest, IPA-checksum, embedded-source, bundle-version, deployment-target and device-architecture checks. The iPhone 17 app and Live Activity extension both identify as version 1.0, build 29. They remain unsigned for the owner's installation workflow.

| Package | SHA-256 |
|---|---|
| KUSC-17-unsigned.ipa | `ed561d635a1155e9d2b65b951d8d10a8944730ea3216d782917285ae78c4b38d` |
| KUSC-SE-unsigned.ipa | `6872362d3e086609a915c857365ad9002857c1bd8055ea56f5d178f229954261` |

Packages, test logs and verification records are under `artifacts/ci-37312008040/`.

The added regression cases cover immediate manual Play, five-second retries and Pause cancellation, changes of output, mixable standby, takeover at the target for both output modes, manual recovery near/after the target, the reminder's timing and stale-ID handling, visible deletion navigation, and menu brightness during frequent model updates.

## Physical-device checks

Follow the October checklist in [manual_test_plan.md](manual_test_plan.md). Start with these reported failures: play another app before the target, disconnect headphones then press Play, pause before/after the target, and open the dark More menu during playback. For the reminder, schedule three minutes ahead and test its banner/action from a locked phone, another sheet, and a cold launch. Delete must remain a separate deliberate action.

Real headphone, Bluetooth, USB/wired and AirPlay routing, audible fades, locked/background behavior, notification delivery and battery timing still require the owner's iPhone. iOS controls session availability and process execution: force-quit, termination, reboot or a powered-off phone prevent a guaranteed automatic start. A retained persistent request can recover when KUSC is relaunched, respecting its saved manual pause; battery observation restarts after process death. See [platform_limits.md](platform_limits.md).
