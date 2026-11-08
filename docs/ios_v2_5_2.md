# Philharmonic iOS 2.5.2 — native motion and transport morph

The user's updated priority is Apple-native, idiomatic motion wherever it fits.
App-specific transitions use smooth interior geometry where there is no suitable
system transition; endpoint snaps are explicitly acceptable. This audit preserves
the live-only player, fixed controls, panel directions and confirmed landscape.

## Animation audit

| Surface | Outcome |
|---|---|
| Settings/timer/output sheets, navigation, city chooser and share sheet | Retain native presentation, dismissal and interactive gestures |
| More menu, quality menus, segmented controls, date/time wheels, toggles, refresh and route picker | Retain native feedback and transitions |
| Map zoom/pan/rotation | Retain native MapKit movement; shortcuts now respect Reduce Motion |
| Program reveal and horizontal heading | Retain Apple's existing critically damped interpolating spring and the C-infinity heading blend; allow page-button retargeting and close unsupported Program content through the spring |
| Drag-to-settle handoff | Explicit continuous transaction for UIKit gesture updates; use the actual resistance derivative for signed release velocity, including cancelled short drags |
| Previous/Next vertical station heading | Retain the same spring/roll; external station changes choose the nearest unwrapped target across the last/first seam |
| Stations grid/list | Stable native LazyVGrid and AnyLayout preserve card/content identity while layout changes; native default animation for mode/reorder operations |
| Station selection indicator | Native SF Symbol replacement, with Magic Replace where available |
| Quality and scheduled-value numbers | Native numeric text transition on supported iOS versions |
| Scheduled output/power sections and notification deep-link scrolling | Scoped native layout/scroll animation, respecting Reduce Motion |
| Play/Pause | Two solid, corresponding outlines physically morph between triangle halves and pause bars; native spring timing, no opacity replacement |
| Artwork and unrelated metadata updates | Keep immediate, honest content updates without blending different works or moving the fixed transport |
| Appearance, rotation and initial/restored layouts | Retain native presentation/layout and safe endpoint resets |
| Widgets and Live Activities | Presentation sources unchanged |

The More-menu circle/background isolation is preserved. Animations are scoped to
user actions or specific glyph/number values, rather than every playback tick.
Reduce Motion disables the app's optional glyph/number/layout motion, changes
panels immediately and suppresses animated map shortcuts. System gestures remain
under iOS control.

## Interior smoothness

The existing heading map is
`h(p) = b(p) / (b(p) + b(1-p))`, with `b(t) = exp(-1/t)` for positive `t`
and zero otherwise, evaluated through stable log odds. It is C-infinity with
flat endpoint extensions. The transport morph uses this same smooth parameter
to move corresponding convex vertices and corner-control points, with both
paths filled throughout. A triangle becoming two bars is not a global
diffeomorphism: the parts meet at the play endpoint, as the user's endpoint
exception permits.

The drag resistance is now the odd analytic function `x - a*tanh(x/l)`, scaled
to the viewport width. It removes the previous curvature change through zero,
keeps immediate hand coupling and costs at most three points. Only viewport
endpoints clamp. Apple's interpolating spring handles timing and overlapping
velocity; there is no polling loop or custom display-link animator.

This describes the custom geometry's mathematical interior, not a claim that
sampled display frames or every opaque iOS transition are globally C-infinity.

Apple references: [interpolating springs preserve velocity](https://developer.apple.com/documentation/swiftui/animation/interpolatingspring),
[stable layout identity](https://developer.apple.com/documentation/swiftui/composing-custom-layouts-with-swiftui),
[native numeric/symbol transitions](https://developer.apple.com/documentation/swiftui/contenttransition).

## Stations selection

All station choices remain in Stations. A direct map pin keeps the current map
camera and zoom; choosing a station from a multi-station city dismisses only the
city choice sheet and returns to that same map. Selected map-marker glyphs and
accessibility state update in place. Grid/list choices retain their existing
position and stay open. Back to player remains explicit.

## Verification and packages

All 17 distinct focused curve/geometry checks passed in runs 86 and 87. All seven
native motion/picker cases passed across those runs: numeric quality/preset
changes at regular/accessibility text sizes, Reduce Motion with unsupported
Program closure, solid transport morph poses and repeated real button actions
with fixed controls, scheduled power controls, map selection staying in place,
drag reordering, and grid/list rotation and horizontal reachability in both
appearances.

All six panel cases passed across the same runs: intermediate heading layout,
horizontal/vertical gesture locking, landscape controls, portrait-only Program,
pull-to-refresh with paging, and opening Program on the first swipe after a fresh
launch in both live and dark fixtures. Run 86's fresh-swipe attempt received
direction acceptance without a native pan-began callback; the isolated repeat
passed in run 87 with unchanged app sources. The broad rotation case previously
hit the job time limit; its focused repeat also passed. Only CI scope/time
allowances changed between these runs.

Run 87 completed successfully. Its captures include triangle/midpoint/bars,
repeated real button actions in light mode, Reduce Motion, both station layouts
in portrait/landscape and both appearances, plus successful first-swipe screens.
The original simulator images were visually reviewed; a local gallery is at
`artifacts/ios-2.5.2/ui-preview.html`. These are iPhone 17 / iOS 26.5 Debug fixture
checks; the SE/iOS 16 target received Release compilation and package inspection,
not an iOS 16 simulator UI run. Local structural parsing covered 93 Swift files.

Both Release device packages passed in
[run 87](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42497231281),
source `1bb251167b3b925e0390f526d8fe50917c48e328`, version 2.5.2, build 87,
with Xcode 26.6 and iPhoneOS SDK 26.5. Downloaded IPAs passed ZIP CRC, source,
version/build, CI checksum, identifier, App Group and embedded extension checks.
CI also checked arm64 iOS platform, deployment targets and signing material.

| Target | IPA bytes | SHA-256 |
|---|---:|---|
| Philharmonic-17 | 1,838,168 | `a6e854c7bc7687c24e1a5bf97cdb1e6d903a5d79037c4d0671c5664f253e370f` |
| Philharmonic-SE | 1,803,716 | `9cf7b8d99182295dcfe3eca2e06cc4c713e46cbfbb5042c8724bd4187882ad89` |

Local packages and machine-readable verification:

- `artifacts/ci-42497231281/Philharmonic-17/Philharmonic-17-unsigned.ipa`
- `artifacts/ci-42497231281/Philharmonic-SE/Philharmonic-SE-unsigned.ipa`
- `artifacts/ci-42497231281/verified-builds.json`

AltStore must sign the packages before installation. No physical-device
installation, frame-rate or hitch measurement is implied by these builds.
Android and recognition remain deferred. The 24-hour debug journal remains
included, and widget/Live Activity presentation sources still match `11997c8`.
