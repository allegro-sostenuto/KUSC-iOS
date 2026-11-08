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
| Readiness, waiting reason, rate, buffer-empty/keep-up and loaded ranges | Native player observations and bounded snapshots |
| Native access/error log, bytes, observed/indicated bitrate, stalls | AVPlayerItem access/error/stall notifications |
| HTTP request, response/status, timing, byte count, failure | KUSC HLS preparation fetches; source URLs and headers are not logged |
| System path status, Wi-Fi/cellular, constrained/expensive | Read-only NWPathMonitor; not a claim of station reachability |
| Audio activation attempt/success/error, interruption/resume, route/reset | Existing audio-session coordinator entry points |
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

Pending focused core journal/redaction tests, hosted coordinator/engine checks,
native debug/share UI evidence and both Release device builds.
