# Philharmonic iOS 2.3.0

The saved UI backlog is implemented in ascending difficulty, in separate commits:

| Order | Requested update | Implementation |
|---|---|---|
| 1 | Quality values and v/ø alignment | One trailing bitrate column, identical 14-point indicator slots; unavailable choices remain disabled. |
| 2 | Missing artwork | The selected station's bundled logo replaces the missing album image in the app, including landscape. |
| 3 | More control becomes square on dismissal | A persistent circular host draws the surface and border separately from UIKit's animated menu button. |
| 4 | Clipped rounded corners | Border paths are inset inside their bounds; album artwork uses the outer square for its mask and border. |
| 5 | Apple Settings layout and vertical centering | Native Form sections and rows, system controls, 52-point regular rows, shared rounded section outlines and native inset separators. Appearance uses the native navigation picker. |
| 6 | Horizontal channel-name / Program transition | Header labels move with the horizontal panel reveal, using the existing smooth roll curve and critically damped spring. |
| 7 | Directional station transitions | Next pushes the current name upward and brings the following name from below; Previous reverses it. Saved order and wraparound are used. |

The shared Quality container, single-quality ø marker and unavailable-Program
restriction were already delivered and remain in place. Values scale with
Dynamic Type; at accessibility sizes each quality label has space above its
right-aligned control. This avoids truncating the channel name or kbps value.

Settings geometry follows the user's supplied Apple reference. Dark backgrounds
and cards remain pure black with borders; light Settings uses the native grouped
background. The existing iPhone landscape arrangement and fixed transports remain.
Programme mode remains portrait-only and unavailable for station-only channels.

Station header motion uses an unwrapped catalogue position. A new button tap
retargets the existing animation rather than queuing a delayed station switch.
The nonlinear curve is evaluated on every animation frame, as in the previous
Program roll. Reduce Motion removes the station roll. Station selection itself
still changes immediately, and the audio engine and live-only rules are unchanged.

Artwork fallback is a view concern: it does not overwrite programme artwork,
widget snapshots, system artwork or any station metadata. Widgets and Live
Activities retain their pre-flag code and resources. Android is deferred.

## Verification

Portable structural validation parsed 80 Swift files without syntax errors.
The focused shell script passed `bash -n`. These checks do not type-check Swift.

[Run 74](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42382534977)
passed all 13 core header/panel policy tests and five of the six selected native
UI cases: light/dark quality selection and equal trailing-control bounds, menu
brightness during updates, the first Program swipe, held header-layout captures,
and transport/wraparound with logo fallback and landscape controls.

The sixth case reached the native Appearance page but searched for a static
text node; the exported accessibility hierarchy identifies Light as a Button.
Only that selector was corrected. The Appearance-only rerun in
[run 75](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42384562554)
passed. All 13 core tests also passed again. All six targeted UI cases therefore
passed across the two runs. App code is identical between the runs; test and CI
files changed. The five already-passing UI cases were not rerun.

The native captures were visually inspected for shared section borders, aligned
quality values, row centering, artwork fallback and both header axes. Local
preview gallery: `artifacts/ios-2.3.0/ui-preview.html`. Original images and test
results are under `artifacts/ci-42382534977/native-station-captures/`; the
successful large-text Appearance captures are under
`artifacts/ci-42384562554/native-station-captures/`.

The historical screenshot sweep and live-stream probes were skipped. Captures
use an iPhone 17 / iOS 26.5 simulator with deterministic Debug fixtures (local
build 1). They do not establish physical-device animation performance or audio
output. iOS 16 is a compilation target without an iOS 16 runtime check.

## Verified packages

Both Release device builds passed in run 75, source
`ae6c52eaac7bdd2036988d0f36b5799a0d3fa75b`. App and embedded extension both report
2.3.0 (build 75). ZIP integrity, CI checksums, source record, app and extension
versions, identifiers, App Groups and the expected widget extension were checked.
Flag assets remain app-only; widgets have no added asset catalogue. Widget and
Live Activity view source matches `11997c8` exactly. AltStore must sign the IPAs.

| Package | SHA-256 |
|---|---|
| Philharmonic-17 | `5bc75895a46104b9e38ae1e7dd5aa045d5f6a3fab0dbec1f415099dba1331494` |
| Philharmonic-SE | `995d58f3cb6d0cd2e72133dd00fadb3c27a0c40e411e017509c15bf4ae829ce9` |

Local IPAs and `verified-builds.json`: `artifacts/ci-42384562554/`.
