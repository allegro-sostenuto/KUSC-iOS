# Philharmonic iOS 2.0.1

Settings has a **Quality** section: channel names on the left, selected kbps on
the right. Tap a bitrate to open that channel's available codec/bitrate menu.
Each channel's choice persists independently. Defaults target roughly KUSC's
96 kbps; eight channels default to 96–128. Radio Chopin (≈320 AAC) and Orpheus
Large-Scale/Russian Classical (192 MP3) retain their only verified/published
sources. [Full choices, sources and exceptions](station_sources_v2.md).

There are 22 verified source choices across eleven channels. Changing the active
channel's quality rejoins live while preserving Play/Pause intent, metadata,
timers, scheduled station and interruption policy. Changing another channel's
saved quality leaves current playback running. Old settings acquire the defaults
without resetting other preferences; an obsolete saved source falls back only
for its own channel. Network buffering, retry timing, installation identifiers,
widget extensions and Android are unchanged.

## Verification

[Run 65](https://github.com/allegro-sostenuto/philharmonic/actions/runs/41454592113),
source `fc55f2d5c69f9a9549425dbf876a2511f63d7745`, passed its 23-test hosted native job:
nine catalogue tests, two settings/migration tests, eleven station/coordinator
tests and one source test covering all 22 choices. Every source became ready
and advanced the decoder by at least one second on its first attempt. Complete
probe elapsed times, including that decoder advancement, ranged from 2.08 to
6.78 seconds. These short checks do not establish long-term network reliability
or audibility on a physical phone.

[Run 66](https://github.com/allegro-sostenuto/philharmonic/actions/runs/41456671329),
source `0c5da3796e5062006bf721768a7ad26e1841f662`, rebuilt both ordinary Release
device targets and their widget extensions as 2.0.1 (build 66). The only changes
since the passing native run are a UI-test query correction and its focused CI
selection; app, audio, settings and catalogue sources are identical. The first
UI run stopped on a duplicate channel-name text query before opening the menu.
The corrected test passed in light and dark: it opens the channel dropdown,
selects AAC 192, reopens Settings with that selection retained, selects MP3 128,
returns to AAC 96 and confirms the player remains paused. Four native PNGs
capture the channel rows and numeric dropdowns in both appearances; all four
were visually inspected for names on the left, aligned kbps controls on the
right, readable dropdown choices and dark backgrounds. Evidence is
in `artifacts/ci-41456671329/quality-captures/attachments/`.

Local portable validation parsed 76 Swift files with no syntax errors and
checked project/plist/icon structure; this is not local Swift type checking.
Xcode 26.6 / iOS SDK 26.5 supplied authoritative compilation. Hosted/native UI
checks use a disposable iPhone 17 / iOS 26.5 simulator. iOS 16 was compiled,
without an iOS 16 runtime check. The historical swipe/layout suites were not
rerun for this patch. Physical installation, sustained Shanghai connectivity,
background playback and Bluetooth/AirPlay remain device checks.

## Verified build 66 packages

Both local IPA hashes match their CI checksum files. ZIP integrity, source
revision, version/build in the app and extension, existing bundle identifiers,
matching App Groups and the expected embedded widget extension were verified.
CI also validated arm64 device binaries, deployment targets and ad-hoc widget
capabilities. AltStore must sign the packages; neither is claimed installed.

| Target | SHA-256 |
|---|---|
| Philharmonic-17 | `c25a9ed08833fff2fab92484dc2c5fd0ee19d88a0e81d9a433f5108b72b357f1` |
| Philharmonic-SE | `0e2e93f4f9e8c0cb57bbd3fef30ce08f448da27c96e707ffe618eb019067179d` |

Local packages and `verified-builds.json` are in
`artifacts/ci-41456671329/`; run 65's parsed source summary and job log are in
`artifacts/ios-2.0.1/`. The delivered packages preserve PhilharmonicLiveActivity
(modern) and PhilharmonicWidgets (classic), respectively.
