# iOS v2 validation — 2 November 2026

Version 2.0.0 on `codex/rendering-buffer-schedule`. Implementation and migration
behavior are described in [iOS v2](ios_v2.md); source URLs, short decoder
measurements, metadata capabilities and logo attribution are in
[station sources](station_sources_v2.md).

## Completed checks

[Run 61](https://github.com/allegro-sostenuto/philharmonic/actions/runs/41440829343),
source `8225b66edf66c10cc5d4e8c39e1dcb243fc30a66`:

- Both Release arm64 device packages compiled, with their widget extensions.
- 155 portable core tests passed.
- 84 hosted native playback/schedule/switching checks passed, including all
  eleven real broadcaster streams becoming ready and advancing the native
  decoder clock by at least one second. All eleven passed on their first
  attempt in this run.
- Four native picker tests passed: portrait/landscape grid and list, horizontal
  last-entry reachability, drag reordering, visible move actions, persistence,
  cyclic station transport, paused selection, and accessibility-size landscape
  names and reorder controls. Light/dark and reordering captures were inspected.
- Nine swipe policy tests passed. Five of six focused native player checks
  passed; the lightly diagonal first swipe remained unresolved at this point.

Earlier run 60 had one Orpheus Large-Scale Works startup failure
(`CoreMediaErrorDomain -16830`); its same official source passed run 58, current
network/decoder rechecks, and run 61. The native source check now exercises up to
three connections within a one-minute window and retains every failure in its
report. This matches the app's existing bounded reconnect behavior; it does not
establish long-term reliability or audible station identity.

## Native UI checks

[Run 62](https://github.com/allegro-sostenuto/philharmonic/actions/runs/41444159892),
source `646dcfb51114c979d6db50dcbcb0a592f269ff26`, passed both device builds,
nine swipe policy tests, all six focused native player tests and all four picker
tests. The first right swipe and first left return passed in light/dark without
a warm-up gesture. Reverse horizontal scrolling in the station page preserves
selection/order and leaves Program closed underneath it. Portrait/landscape
grid/list, large text, drag/move actions and persistence passed again.

Fixture-only native traces confirm an eligible touch, correctly attached pan,
horizontal direction, accepted release and completed transition. The earlier
failure's cause is not proven; no speculative native-recognizer change was made.
UI-only runs generate a scheme containing only the UI test bundle; swipe policy
checks run separately through Swift Package Manager. This avoids building and
launching an unrelated hosted unit-test app before the UI checks.

[Run 63](https://github.com/allegro-sostenuto/philharmonic/actions/runs/41446744234),
source `50f51b1863a9dbccdd7de4608953eed9956892f4`, passed both Release device
builds and the native Release first-swipe/return smoke test. This test runs
without a DEBUG fixture or diagnostic probe, verifies the first lightly diagonal
right swipe, the first left return and fixed transport placement, and saves
native captures. It passed rather than skipping. The passing playback/schedule
and picker suites were not repeated for this test-only addition.

## Verified delivery packages

Both packages are version **2.0.0, build 63**, from the run-63 source above.
Local verification checked ZIP integrity, recorded source revision, version/build,
bundle IDs, exactly one widget extension, matching App Groups and SHA-256 against
the CI checksum files. CI separately validated arm64 iOS device platform,
deployment targets and signing structure. Installation identities remain
`org.personal.kusc.modern` and `org.personal.kusc.classic`; both extensions remain
included for AltStore provisioning.

| Package | Local path | SHA-256 |
|---|---|---|
| iPhone 17 / iOS 26+ | `artifacts/ci-41446744234/Philharmonic-17/Philharmonic-17-unsigned.ipa` | `c4eec931023dedb1bdbdd5bff92716b176dd4487d652b9858190ebbacc490f5c` |
| iOS 16+ / SE | `artifacts/ci-41446744234/Philharmonic-SE/Philharmonic-SE-unsigned.ipa` | `b94cdcbf3e85b7ba3f1cbf5a659b1d3c096362ffc49698962f32cfc397123b3c` |

Native capture manifests and PNGs are retained locally under
`artifacts/ci-41444159892/station-captures`,
`artifacts/ci-41444159892/swipe-captures` and
`artifacts/ci-41446744234/release-swipe-captures`.
The earlier run-61 grid/list, dark, reordering and large-text captures are also
retained under `artifacts/ci-41440829343/station-captures/gallery`.
No physical installation is claimed.

## Scope of evidence

The focused native checks used the shared Philharmonic-SE app target on a
disposable iPhone 17 / iOS 26.5 simulator. The iOS 16 deployment target compiled;
an iOS 16 runtime was not exercised. Both ordinary device targets and their
extensions compiled. Actual WidgetKit/ActivityKit presentation remains a system
and device check, separate from the tested snapshot/intent/session boundaries.

Short stream probes and simulator decoder advancement do not verify Shanghai
network acceptance, sound quality by ear, background playback on a physical
iPhone, Bluetooth/AirPlay routing or unattended scheduled starts. Those remain
device checks. Metadata is implemented for KUSC, P2 Musik and HR Klasik; the
other entries display honest station/live information without invented works,
programmes or artwork. Android and server/delayed-playback implementation remain
deferred.
