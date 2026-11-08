# Philharmonic iOS 2.5.0 — debug history

Settings → Playback Diagnostics is renamed **debug**, as requested. The existing
native UI release (2.4.0, build 78) is preserved, including the station globe,
three zoom levels, city choices and global quality presets. ShazamIO remains on
hold; Android, widgets and Live Activities are unchanged.

## Source and integration

This work adapts the user-provided `Pasted text.txt` recovery bundle from the
[Work-mode Philharmonic misc chat](https://chatgpt.com/g/g-p-6aae94825b4481919113b55b64a49a6b-philharmonic/c/6aefd765-8c40-83eb-94ca-18351cf79cca).
The pasted source was read directly; the linked private chat was not accessible.
The wrapper Python was parsed as data, not executed. Original extracted files
and their checksum are retained locally in
`artifacts/debug-24h/recovered-source/provenance.json`.
Pasted source SHA-256:
`9e826cf457fb34f76b95ecb561b4121c74ee8335da593a28ad8946bccda98ec9`.

The recovered actor's structured JSONL event model and immutable share file are
integrated with the app's existing observable diagnostics facade and actual
scheduler callbacks. A separate actor name avoids replacing the facade relied
on by the engine and existing first-failure regression tests. UUID generations
are retained as strings rather than inventing integer generations.

## Retention and sharing

- The journal records locally without first opening debug or starting a capture.
  Wall-clock UTC timestamps and monotonic nanoseconds accompany each event.
- Records persist under Application Support across app launches. Hourly,
  size-bounded segments avoid repeatedly rewriting a whole day's log. Records
  older than 24 hours are pruned on activity, with exact filtering when viewed
  or exported. File protection permits logging while locked after first unlock.
- The journal has emergency bounds of 64 MiB and 100,000 events. Any removals
  for those bounds are counted in the export header. Ordinary snapshots are
  sampled every 10 seconds; state changes and failures are recorded immediately.
- The existing optional per-second focused capture still freezes its first
  failure before teardown. Starting/stopping it does not erase daily history,
  and its current-launch evidence is included in a shared report.
- Share Report creates a separate JSONL file that later events or clearing
  cannot alter. View/Copy Recent Logs use a bounded recent excerpt. The full
  retained history is shared through the native activity sheet. Clear Local Log
  is an explicit, confirmed action, with a fence against late queued records.
- URLs, credentials, private paths and email addresses are redacted; route
  records contain port types, not device names or hardware IDs. No audio is
  saved and no report is uploaded automatically.

History begins with this implementation; the previous memory-only feature
cannot supply earlier-launch logs. No app code can collect events while iOS
is not executing it. Foreground/background and clock-change records make those
boundaries visible without claiming that a notification was delivered.

## Event coverage audit

| Evidence | Instrumented path |
|---|---|
| App version/build, OS, model, launch and scene lifecycle | `AppModel` startup, `PhilharmonicApp` scene changes |
| Selected station, source, kbps, preset, Play/Pause/Stop | Coordinator actions and state transitions |
| Stream attempt, failure, cancellation, stale callback, retry budget/outcome | `startConnection`, `connectionFailed`, retry policy and observed media progression |
| First media data / successful playback | AVPlayer media clock advances while playing; never inferred merely from `play()` |
| Readiness, waiting reason, rate, buffer-empty/keep-up and loaded ranges | Native player observations and bounded snapshots; opening/sharing debug forces a current snapshot |
| Native access/error log, bytes, observed/indicated bitrate, stalls | AVPlayerItem access/error/stall notifications |
| HTTP request, response/status, timing, byte count, failure | KUSC HLS preparation fetches; source URLs and headers are not logged |
| System path status, Wi-Fi/cellular, constrained/expensive | Read-only NWPathMonitor; not a claim of station reachability |
| Audio activation attempt/success/error, category/options, device/software volume, interruption/resume, route/reset | Existing audio-session coordinator entry points and snapshots |
| Scheduled creation/replacement/cancellation/attempt, phases, expiry | Existing request/generation and scheduler transitions |
| Scheduled playback confirmation | Actual media progression after target time with positive software gain |
| Notification authorization, scheduling success/error, removal, response | Notification coordinator; scheduling acceptance is distinct from delivery |
| Notification foreground presentation request/suppression | Notification delegate, without inferring actual system delivery |
| Metadata request/result/error and work/composer presence | Metadata coordinator, without logging piece text |
| Battery/power, sleep timer and significant time changes | Existing policy callbacks |
| Persistent-storage errors, malformed records and quota removals | Journal status and export metadata |

Logging observes these decisions; it does not change playback, scheduled-start,
notification, interruption, route or retry policy. Pause remains live-only.

## Verification and packages

Focused validation passed in [run 79](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42465088172)
at source `6c90cb44f0c56a75b4158feb1855b640f8c7b9f5`:

- 16 core tests: four persistent journal/retention/share/redaction tests and
  twelve existing focused-capture tests.
- 69 hosted simulator tests: five engine cases, two live-only settings cases,
  six media-service recovery cases, three diagnostics integration cases,
  41 scheduled-start boundary cases and twelve station-switch cases.
- One native UI case: Settings → debug, persisted history visible before a
  focused capture, recent-log navigation, capture start/stop, Copy Recent Logs
  and an actual native file share sheet. Three original simulator screenshots
  were reviewed in `artifacts/ios-2.5.0/ui-preview.html`.
- Both Release device targets compiled with their embedded extensions.

The final source additionally includes read-only device-volume/category fields
and requests a current engine snapshot on opening, refreshing or sharing debug.
The existing successful tests were not repeated for those small additions;
both final Release targets are built again in run 80. Local source validation
parsed 89 Swift files with no structural errors; that check is not type checking.

All 23 event names suggested by the pasted integration guide have corresponding
instrumentation. The table above documents the actual callback semantics;
matching a name alone does not prove a real-device event occurred.

No physical-device installation, audible output, unattended locked-phone
scheduled start or real 24-hour device endurance run was performed. The rolling
cutoff and relaunch persistence were tested with controlled timestamps and
reopened files. The native UI fixture does not establish live station reachability.

Final packages passed [run 80](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42466161082)
from source **`c04149df91c67d049443c358fd3af810a1996510`**, version **2.5.0**,
build **80**, with Xcode 26.6 and iPhoneOS SDK 26.5. The build-only run deliberately
skipped repeat tests. CI checked arm64 iOS platform, deployment targets, signing
material and package structure. Downloaded archives passed CRC, source/build,
version, identifier, App Group, extension and CI checksum checks.

| Target | IPA bytes | SHA-256 |
|---|---:|---|
| Philharmonic-17 | 1,814,541 | `585e61daf549bc67bcca7de7f6d8e534c04b0d691a52f724ac73860e40512df6` |
| Philharmonic-SE | 1,779,938 | `223fe8320f8533e6081ef08d748a987a81f2d4f97397ae22ff9d464a5495cbfb` |

Local packages and machine-readable verification:

- `artifacts/ci-42466161082/Philharmonic-17/Philharmonic-17-unsigned.ipa`
- `artifacts/ci-42466161082/Philharmonic-SE/Philharmonic-SE-unsigned.ipa`
- `artifacts/ci-42466161082/verified-builds.json`

The modern Live Activity and classic widget extensions remain embedded with
their existing identifiers/App Groups. Widget and Live Activity presentation
sources match pre-flag revision `11997c8`; app-only flags remain in the main
asset catalogue. The IPAs require AltStore signing before installation and
have not been installed on a phone in this validation.
