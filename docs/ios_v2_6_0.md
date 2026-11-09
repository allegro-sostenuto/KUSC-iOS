# Philharmonic iOS 2.6.0 — foreground speaker-volume setup

Implements the user's approved flowchart in
**··· → Scheduled Start → Audio Output → Scheduled Start Volume**.

| Initial output | Setup behavior |
|---|---|
| Already the built-in speaker | Show Apple's native volume control. Done saves the reference level; Cancel leaves it unsaved. No session activation, interruption, player suspension, routing or deactivation. |
| Another output | Capture the previous route/session/playback intent, silence Philharmonic temporarily, request exclusive nonmixing audio access, then immediately request the speaker. Show volume controls only after the speaker route is verified. |

Speaker confirmation and restoration use bounded waits, not an arbitrary silent
clip. Denied activation, failed routing, cancellation, backgrounding and audio
interruptions all run cleanup. Cleanup restores the original category/mode/options
and releases the temporary speaker override. If iOS does not restore the original
device, the native route picker lets the user restore it; finishing without that
output keeps Philharmonic paused. Exclusive access is released with
`notifyOthersOnDeactivation` so interrupted apps may resume themselves.

Philharmonic resumes at live only if it was previously playing, the prior output
is verified, and its playback intent has not changed. Pause, station changes and
interruptions invalidate resumption. Concurrent setup operations and late route
completions cannot release another setup or restart audio after cancellation.
Scheduler/transport work cannot undo the foreground setup's temporary session.
Background cleanup uses a bounded background task, not a scheduling keepalive.

The percentage is prepared using the visible, user-operated `MPVolumeView` or
hardware volume buttons. There are no hidden sliders, private volume APIs or
programmatic system-volume writes. The prepared reference level persists with
settings and schedule options, including an existing schedule's unchanged ID and
deadline. Old settings and requests decode without the new optional value.

This sets speaker volume **now**. Later user/system volume changes still apply;
the app cannot silently reapply the saved system volume at the scheduled time.
At scheduled speaker activation, debug records the prepared level and actual
system volume. The existing 24-hour journal also records setup, interruption
requests, verified routing, restoration, saved levels, failures and notifications
to other apps. Other apps' response and protected audio sessions remain under
iOS control.

## Validation

Pending focused core, hosted coordinator and native UI checks, plus both ordinary
Release device builds. The fixture tests can establish operation ordering and
our state handling, not physical Bluetooth routing, system-volume changes or
interruption/resumption of another real app. Those require the user's iOS 26.7.2
phone. Apple documents that native volume/route changes cannot be exercised in
the simulator.

No station, quality, identifier, widget/Live Activity presentation, Android,
recognition or AlarmKit changes are included.
