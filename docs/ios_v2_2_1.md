# Philharmonic iOS 2.2.1

Reverts the 2.2.0 flag changes in home-screen widgets and Live Activities,
including expanded Dynamic Island labels. Their views return to the pre-flag
implementation, and widget targets no longer compile the flag-label helper,
station catalogue or flag asset catalogue. App station labels retain their flags.

This is the requested scope correction to the small flag update. The two view
files match commit `11997c8` exactly. Portable syntax validation parsed 77 Swift
files with no errors; both Release device builds passed in
[run 73](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42358817167),
source `869c864d43c21de2f2b8c326966a3a8d6eb0df61`.

Both app and embedded extension report 2.2.1 (build 73). ZIP integrity, CI
checksums, source record, bundle identifiers, App Groups and the expected
widget extensions were verified. All thirteen flag names remain in the app
asset catalogue; neither widget extension contains the added flag catalogue.
Extended playback, simulator UI and physical-device checks were not rerun.
AltStore must sign these unsigned packages before installation.

| Package | SHA-256 |
|---|---|
| Philharmonic-17 | `a1799c8146ab30a53b1001c44206696022da3ce791ee14dcc22765d78de785b9` |
| Philharmonic-SE | `d803a5d6c217b08c8b2ff4d7323899933254699f419e99d0df4d07e0dc9baaa9` |

Local IPAs and `verified-builds.json`: `artifacts/ci-42358817167/`.
