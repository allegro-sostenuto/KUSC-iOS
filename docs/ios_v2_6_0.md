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

The light/dark native UI case passed in
[run 89](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42573135014):
setup opens from Audio Output, Done updates the saved percentage, and reopening
then Cancel returns to Scheduled Start. Four original simulator captures are at
`artifacts/ios-2.6.0/previews/`; the local gallery is
`artifacts/ios-2.6.0/ui-preview.html`. The visible layout and saved row were
reviewed. `MPVolumeView` does not supply a working slider in these simulator
captures; actual volume adjustment remains a physical-device check.

Run 89 also passed 43 focused core/journal cases and 92 hosted simulator cases,
including 13 setup cases. The final run adds the disappearing-during-restoration
regression for 14 setup cases.

Review then fixed cancellation while restoration was already in progress: a
disappearing sheet cannot leave exclusive access waiting for an invisible route
picker. Late notifications cannot create background cleanup after observation
ends. A central session guard prevents pending coordinator work from changing
the temporary session. The UI source is identical between runs 89 and 90.

The final source is `6e70961515778841cec8ba698b0e68c666784e2f`, version 2.6.0,
build 90, in [run 90](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42574049329).
Both ordinary Release targets and embedded extensions compiled with Xcode 26.6 /
iPhoneOS SDK 26.5. Downloaded IPAs passed ZIP CRC, source/version/build, CI checksum,
identifiers, App Groups, app-only flags and embedded-extension checks. CI also
checked arm64 device platform, deployment targets and signing material.

| Target | IPA bytes | SHA-256 |
|---|---:|---|
| Philharmonic-17 | 1,920,196 | `82d19718b26d758ea2ad624070345ae435abeb44ba81e1a0f044a61d3d7c0be8` |
| Philharmonic-SE | 1,887,325 | `274d471a4b2ac9f328c78afc06e6051b4e7073586574c215d0b17c84b908d466` |

Packages and machine-readable verification are under `artifacts/ci-42574049329/`.
AltStore signing is required. No installation is implied. Local structural
parsing covered 97 Swift files; this is not a local type check.

Run 90 passed all 43 focused core/journal cases and 93 hosted iOS 26.5 simulator
cases with zero failures, including all 14 speaker-volume setup regressions.
The downloaded `native-audio-results` evidence is at
`artifacts/ios-2.6.0/native-audio90/` (`tests.log` and `Audio.xcresult`). These
fixture checks establish operation ordering and our state handling, not physical Bluetooth routing,
system-volume changes or interruption/resumption of another real app. Those
require the user's iOS 26.7.2 phone. Apple documents that native volume/route
changes cannot be exercised in the simulator in its
[MPVolumeView reference](https://developer.apple.com/documentation/mediaplayer/mpvolumeview).
The SE target received Release
compilation and package inspection, not an iOS 16 simulator run.

No station, quality, identifier, widget/Live Activity presentation, Android,
recognition or AlarmKit changes are included.
