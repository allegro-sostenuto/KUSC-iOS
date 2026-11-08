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

Pending focused curve/geometry tests, native motion/layout/map-selection and
panel interaction checks, and both Release device packages. Android and
recognition remain deferred. The 24-hour debug journal remains included.
