# Philharmonic iOS 2.5.1 — continuous map zoom and native quality presets

This update follows the user's explicit patch version, 2.5.1.

## Map

- Pinch, double-tap, pan and rotation use the native Apple map. Globe,
  Continent and Country are animated shortcuts, rather than zoom restrictions.
- The selected segment follows camera distance. Thresholds use native fitted
  continent/country cameras for the current base city and viewport. An 8%
  dead band prevents rapid selection changes at a threshold. Following a
  gesture only updates the segment and never sends a new camera request.
- Settings → Map → Map Style offers Political and Satellite, saved with the
  existing preferences. Satellite remains the default on upgrade.
- Political uses Apple's standard map with realistic elevation. Satellite uses
  native realistic imagery at outer Globe zoom and native hybrid imagery with
  borders/labels from Continent zoom inward, following the user's clarification.
  The imagery stays satellite throughout; no custom boundary overlays force a
  flat projection. Apple controls the geographic detail and its availability.
- All shortcuts use native camera animation and retain the active map style.
  Native region fitting still accommodates portrait/landscape country framing.
  Single-city selection, multiple-station choice sheets, saved order and paused
  playback intent remain in place.

API references: [Apple's map configuration overview](https://developer.apple.com/videos/play/wwdc2022/10035/),
[native camera distance](https://developer.apple.com/documentation/mapkit/mkmapcamera/centercoordinatedistance).

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

Pending focused geography/quality policy checks, hosted preference/coordinator
checks, native map gesture/style and quality UI checks, and both device builds.

Android and recognition work remain deferred. Widgets and Live Activities keep
their existing presentation, identifiers and extensions. The 24-hour debug
journal from 2.5.0 remains included.
