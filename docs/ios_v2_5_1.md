# Philharmonic iOS 2.5.1 — continuous map zoom and native quality presets

This update follows the user's explicit patch version, 2.5.1.

## Map

- Pinch, double-tap, pan and rotation use the native Apple map. Globe,
  Continent and Country are animated shortcuts, rather than zoom restrictions.
- The selected segment follows native camera distance and viewport scale.
  Thresholds use native fitted continent/country rectangles for the current
  base city and viewport. An 8% dead band prevents rapid selection changes at
  a threshold. Following a
  gesture only updates the segment and never sends a new camera request.
- Settings → Map → Map Style offers Political and Satellite, saved with the
  existing preferences. Satellite remains the default on upgrade.
- Political uses Apple's standard map with realistic elevation. Satellite uses
  native realistic imagery at outer Globe zoom and native hybrid imagery with
  borders/labels from Continent zoom inward, following the user's clarification.
  The imagery stays satellite throughout; no custom boundary overlays force a
  flat projection. Apple controls the geographic detail and its availability.
- Apple's political/standard style does not support a spherical globe, as
  [Apple Developer Technical Support confirms](https://developer.apple.com/forums/thread/823043).
  Political therefore uses the native flat world map throughout; its outer
  shortcut reads World. Satellite retains Globe and continuous spherical zoom.
  Settings states this limitation explicitly rather than promising a political
  globe that MapKit cannot provide.
- All shortcuts use native map animation and retain the active map style.
  Native region fitting still accommodates portrait/landscape country framing.
  Single-city selection, multiple-station choice sheets, saved order and paused
  playback intent remain in place.

API references: [Apple's map configuration overview](https://developer.apple.com/videos/play/wwdc2022/10035/),
[native camera distance](https://developer.apple.com/documentation/mapkit/mkmapcamera/centercoordinatedistance),
[native map-rectangle fitting](https://developer.apple.com/documentation/mapkit/mkmapview/maprectthatfits(_:edgepadding:)).

## Quality

Lowest / Balanced / Highest now use the native segmented control, matching the
map shortcut control. Only an explicitly applied global preset is highlighted.
An individual station choice clears selection, even if all bitrates happen to
match a preset again. Reapplying a preset selects it. This state survives
relaunch, and a same-source choice does not reconnect audio.

The implementation uses UIKit's explicit
[no-segment state](https://developer.apple.com/documentation/uikit/uisegmentedcontrol/selectedsegmentindex).
Bitrate choices, KUSC-based balancing and the single reconnect boundary remain
unchanged. New optional raw-value preferences preserve older saved settings and
fall back safely for unknown future style/preset values.

## Verification

Focused validation passed in
[run 82](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42472156510)
at source `3cbdb3d196b0b55bb1e95282defe93b9a8c323d7` (build 82):

- 18 core policy tests: ten catalogue/migration cases, five geography/zoom cases
  and three quality-preset cases, including threshold crossing and hysteresis.
- 16 hosted simulator cases: three saved-settings/migration cases and thirteen
  station/quality coordinator cases. These cover persistent map style/preset
  state, custom choices that still match preset bitrates, no unnecessary
  reconnect, paused intent and the existing station/scheduled-start boundaries.
- Five native UI cases: real pinch zoom in and out updates the selected tab;
  Political is selected through Settings and displayed at all three shortcuts;
  direct city selection, Paris/Moscow choice sheets, cancellation, grid/list and
  landscape still work. Quality presets, the unselected custom state, numeric
  bitrate menus and paused intent pass in light/dark and regular/accessibility
  text sizes.
- Both Release device targets compiled with their existing embedded extensions.
  Local structural validation also parsed 89 Swift files without errors; that
  local script does not type-check or execute the tests.

Native captures use an iPhone 17 / iOS 26.5 simulator with Debug fixtures.
23 original captures are collected in `artifacts/ios-2.5.1/ui-preview.html`.
Satellite overview/continent/country and native selected/custom quality controls
were visually reviewed, including accessibility text size. Political overview
and style-picker captures landed during navigation transitions; those frames
are labelled as such and are not settled-map visual evidence.

The final source only adds the Political/World label and the accurate Settings
description of Apple's flat political map. The successful tests were not
repeated for these text changes; both Release packages are built again in run 83.
iOS 16 has compilation coverage only. Live station probes, the historical
screenshot sweep and physical-device checks were not run. The fixture does not
establish live audio, unattended scheduling or a physical phone installation.

## Final device packages

Both Release device builds compiled in
[run 83](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42473703011),
source `0abb8ba3cbf93de9f35974a789358358a6c257e0`, with version 2.5.1,
build 83, Xcode 26.6 and iPhoneOS SDK 26.5. Downloaded IPAs passed ZIP CRC,
source/build/version, identifiers, App Groups, embedded extension and CI
checksum checks. CI also checked arm64 iOS platform, deployment targets and
signing material.

| Target | IPA bytes | SHA-256 |
|---|---:|---|
| Philharmonic-17 | 1,817,492 | `e6a28e6996ccbac6c9e092a3e8dcf54ee167d67f3211a44936771b0db7d1311f` |
| Philharmonic-SE | 1,784,353 | `f9eb956e8393402be0972698293a47c434644d7c3e2e60b5a15c68ae9482121d` |

Local packages and machine-readable verification:

- `artifacts/ci-42473703011/Philharmonic-17/Philharmonic-17-unsigned.ipa`
- `artifacts/ci-42473703011/Philharmonic-SE/Philharmonic-SE-unsigned.ipa`
- `artifacts/ci-42473703011/verified-builds.json`

AltStore signing is required before installation. Neither IPA is claimed to
have been installed or tested on a physical iPhone.

Android and recognition work remain deferred. Widgets and Live Activities keep
their existing presentation, identifiers and extensions. The 24-hour debug
journal from 2.5.0 remains included.
