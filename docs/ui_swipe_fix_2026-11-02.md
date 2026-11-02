# iPhone swipe and header correction — 2 November 2026

Version 1.1.1, build 54. App source: 71a2200c751cbbb8bac9395a59f3ea47bd43fde1.
[Build and focused checks](https://github.com/allegro-sostenuto/philharmonic/actions/runs/41424826615).

The first portrait swipe opens Program without a preparatory swipe. Both layers
remain mounted, and a native horizontal recognizer stays on the fixed viewport
instead of disabling its ScrollView during the drag. Portrait opens right and
returns left. Vertical scroll/refresh, the fixed footer, and the divider remain.

The header identifies the current station as KUSC 91.5 FM. Program has the same
25-point semibold type. Its vertical watch-window roll is driven by panel progress.
With b(t) = exp(-1/t) for t > 0 and 0 otherwise, the roll is
h(p) = b(p)/(b(p) + b(1-p)), extended by 0 and 1 outside the unit interval.
This is a C-infinity position curve with flat endpoints and a steeper midpoint;
touch sampling and display frames do not establish a C-infinity physical trajectory.

The panel itself has at most three points of light drag resistance. Release
velocity projects a 0.18-second free movement and initializes the settling spring:
m = 1, k = 380, c = 2 sqrt(mk), with bounded initial velocity to avoid overshoot.
Header progress follows that panel motion.

Program is portrait-only. It has no view, gesture recognizer or page controls in
landscape. Landscape keeps the artwork-left/details-right player. Program locks
the app to portrait until it is closed; the artwork player can then rotate again.
The app name remains Philharmonic; Android and multi-station work remain deferred.

Both Release device builds passed. On an iPhone 17 simulator with iOS 26.5, nine
policy tests and six focused UI tests passed, covering actual first-swipe page
selection in light/dark, return, vertical scrolling/refresh, fixed controls,
landscape exclusion, portrait lock and restored rotation. Native captures were
inspected. The earlier header-existence-only assertion was insufficient and was
replaced with selected-page and hit-testing checks. The full audio and layout
suites were not run for this correction. Physical installation is not verified.

The iPhone 17 IPA is under
artifacts/ci-41424826615/Philharmonic-17/Philharmonic-17-unsigned.ipa.
SHA-256: f0b0426bfb0477ccff90de2897a79f5bac9dc4f73ac7ac947cce351d59fa2fb9.
Version/build, source record, app/extension identity, App Group and checksum passed
local verification. Install through AltStore with the widget extension retained.
