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

Planned checks are limited to relevant header/panel policy tests and native UI
cases for quality selection/alignment, artwork fallback, station transport and
wraparound, Settings at accessibility size, header intermediate-frame captures,
first Program swipe and menu appearance during updates. The historical screenshot
sweep and live-stream probes are not required by these presentation changes.

Exact results, native captures, release source revision, build and IPA checksums
will be recorded after CI completes. Static fixtures show layouts; they do not
establish physical-device animation performance or audio output.
