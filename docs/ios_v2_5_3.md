# Philharmonic iOS 2.5.3 — scheduled audio recovery attempt

This patch addresses the user's November 9 failed scheduled start on an iPhone
running iOS 26.7.2. It is a debug attempt requiring physical-device confirmation,
not a claim that unattended live radio is guaranteed after iOS suspends an app.

## Evidence

The supplied recent-log excerpt has 140 events. At 08:20:00.629 Shanghai time,
the scheduler attempted Yle Klassinen at 64 kbps. Speaker activation requested
nonmixing audio and failed at 08:20:00.661 with OSStatus 560557684 (`!int`,
`cannotInterruptOthers`). No further activation attempt appears before expiry
at 08:40:51.365, immediately before foreground events. The log establishes the
activation failure; process suspension during the subsequent gap is an inference.
It does not establish the earlier standby history or the installed app build.

## Changes

- Unattended scheduled activation uses mixing while the application is inactive
  or backgrounded, including when requesting the built-in speaker. Foreground
  scheduled takeover and explicit Play/notification intent keep their prior focus
  behavior. Another app's audio may continue alongside a background start.
- Speaker configuration honors the requested mixing flag and checks category
  options as well as category, so changing mixing on an existing speaker session
  actually reconfigures it. The public speaker override and route verification
  remain; a failed override never authorizes playback on headphones.
- An audio wait preserves existing standby and attempts to restore a mixable
  session. A retry keeps standby through stream preparation and releases it only
  when the stream is ready and advancing. Stream teardown still ensures that a
  retry joins live safely.
- Foreground and genuine accessory-route changes can wake a pending retry within
  the existing expiry window. Duplicate wake events coalesce. Pause, deletion,
  interruption and battery policies retain priority.
- The rolling 24-hour journal records resolved session options, application
  state, previous category/options, other-audio state, exact failing API step,
  error domain/code, standby lifecycle, retry scheduling/wake, execution gaps,
  and the last audio error on expiry. Schedule-state events retain their actual
  reason text and target time.

Apple references: [mixing supports playback and play-and-record](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers),
[background activation error](https://developer.apple.com/documentation/coreaudiotypes/avaudiosession/errorcode),
[background execution lifecycle](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background).

## Validation and delivery

Eight new hosted regressions cover background speaker options with another app
playing, cold late starts, rejected speaker routing, standby continuity through
retry/preparation, foreground and accessory-triggered retries, pause/deletion,
explicit Play focus, and persistent failure/execution-gap evidence. They run with
the existing scheduler, media-recovery, station, live-only and journal checks.

[Run 88](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42543585020)
completed successfully for source `5bb118dcff79872aeac807d1197a331f4ab356ec`:

| Check | Result |
|---|---|
| Schedule policy / diagnostic core / rolling journal | 42 passed (26 + 12 + 4) |
| Hosted schedule coordinator | 49 passed, including all eight new regressions |
| Hosted engine / media-services recovery / diagnostics | 14 passed (5 + 6 + 3) |
| Hosted live-only settings / station switching | 16 passed (3 + 13) |
| Both ordinary Release device targets and embedded extensions | Compiled and package-verified |
| Local source parsing | 93 Swift files, no structural errors; not a local type check |

All 79 hosted cases ran on an iPhone 17 / iOS 26.5 simulator with the silent
coordinator fixture where applicable. The new tests exercise session-policy and
failure injection; they do not make another app play audio, reproduce the actual
iOS 26.7.2 focus refusal, or prove overnight background execution. No UI screenshot
sweep was repeated because presentation sources are unchanged. The SE target
received Release compilation and package inspection, not an iOS 16 UI run.

The simulator evidence is saved at `artifacts/ios-2.5.3/native-audio88/`.

No UI, station catalogue, quality default, widget presentation, app identifiers,
saved preferences, Android or recognition implementation is changed. AlarmKit
remains a separate proposal. The supplied log remains unmodified.

Physical validation must use the user's iOS 26.7.2 phone: locked/background start,
Bluetooth connected with speaker selected, another app playing, cancellation and
an overnight start. Simulator results cannot establish these device behaviors.

Version **2.5.3**, build **88**, source
`5bb118dcff79872aeac807d1197a331f4ab356ec`. CI used Xcode 26.6 and iPhoneOS SDK
26.5. Both downloaded IPAs passed ZIP CRC, source/version/build, CI checksum,
identifier, App Group, app-only flags and embedded-extension checks. CI also
checked arm64 device platform, deployment targets and signing material.

| Target | IPA bytes | SHA-256 |
|---|---:|---|
| Philharmonic-17 | 1,845,652 | `9498610f9aa1e10f4079d89367fad8e082a0d87d10654d032366a85e06defa2f` |
| Philharmonic-SE | 1,811,043 | `4288b4d4ca7da30517c452339cfdc16f0c5c162e33f5bb735f0ed6700c14538c` |

Packages and verification are under `artifacts/ci-42543585020/`. AltStore signing
is required before installation; no installation has been observed. Widget and
Live Activity presentation sources still match `11997c8`.

After the next locked-phone test, use Settings → debug → **Share Report** to
export the full rolling journal. **Copy Recent Logs** is a 64 KiB tail preview,
so it can omit the original schedule setup and earlier standby evidence.
