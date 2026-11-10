# Philharmonic iOS 2.6.1 — scheduled start on an existing speaker route

The November 10 log shows nine background attempts to change from mixable
`playback` to `playAndRecord`, each rejected at `set_category` with OSStatus
560557684. Speaker was already selected, system volume was 70%, mixing was
requested, and standby was running. Ordinary mixable playback restoration
succeeded after every failure. The 01:29:49 Shanghai schedule expired without
playing at 01:39:49. The supplied excerpt begins at 01:39:00 and does not identify
the installed build or initial setup.

## Reproduction before the fix

Source `f7a4701` retains the old Release playback behavior. In the
[baseline run](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42737806427),
the coordinator replay injects only the captured recording-category error;
ordinary playback remains available. It reproduced **nine category failures,
zero stream connections, and expiry**. The new success regression failed with
five assertions. A headphone control passed, confirming that a rejected switch
does not authorize playback on the wrong output. This is a replay of the app's
failure given the phone's error, not reproduction of the OS's decision to reject.

A separate native probe launched the app, started its real silent standby,
pressed Home, and called Apple's actual session APIs while backgrounded. The
iOS 26.5 simulator accepted both `playback` and `playAndRecord` with mixing, so
the real OS refusal was **not reproduced on that simulator**. No fake API errors,
radio network requests or volume writes are used by that probe. Its raw results
and the red regression are saved in `artifacts/ios-2.6.1/repro-probe/` and
`artifacts/ios-2.6.1/repro-native/`. The input fingerprint and event counts are in
`artifacts/ios-2.6.1/reproduction-input.json`.

## Change

Session configuration reads the actual output route before choosing a category.
When Speaker is already selected without an established forcing session, retain
ordinary playback and still request activation with the existing mixing/focus
policy. Request `playAndRecord` only when routing to Speaker is needed, or retain
an already established speaker-override session so changing category cannot send
audio back to a connected accessory. Existing route validation and mute-before-
reroute handling remain in force.

Activation diagnostics now distinguish the requested speaker policy, whether
Speaker was already selected, and whether a speaker-forcing session is required.
The foreground volume setup remains unchanged. Tests cover the captured replay,
headphone rejection, injected activation failures, foreground focus, retaining an
established override, and a new accessory arriving after an ordinary speaker start.

## Validation

Both ordinary Release device targets compiled in
[run 92](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42739839763),
source `ead2d58c9f5db6e021ffe2608a77370c2c38623f`, version 2.6.1, build 92.
The downloaded IPAs passed ZIP CRC, source/version/build, CI checksum,
identifiers, App Groups, app-only flags and embedded-extension checks. CI used
Xcode 26.6 / iPhoneOS SDK 26.5 and also checked arm64 device platform, deployment
targets and signing material. Widget presentation and the foreground volume
setup sources match 2.6.0.

| Target | IPA bytes | SHA-256 |
|---|---:|---|
| Philharmonic-17 | 1,920,542 | `607213597b8ff361680da6f706a768165c9127022d5b7225632074088a07ddcd` |
| Philharmonic-SE | 1,887,919 | `69b746943c5f7bb83c949650b73bc7fb98b0a269dcf005eff9c6e7ccbca5637b` |

Packages and machine-readable verification are in `artifacts/ci-42739839763/`.
AltStore must sign them before installation; no installation has been observed.
Local structural checks reported zero errors; a local Swift parser/compiler was
unavailable. CI compilation is the authoritative type check.

All 43 focused core/journal cases and 98 hosted audio cases passed with zero
failures, including five speaker-category regressions and all 14 existing
foreground volume-setup cases. The original replay was retained across the fix:

| Captured-error replay | Baseline `f7a4701` | Fix `ead2d58` |
|---|---:|---:|
| Category failures | 9 | 0 |
| Stream connections | 0 | 1 |
| Playing before expiry | No | Yes |
| Expired without playing | Yes | No |

The passing hosted evidence is in `artifacts/ios-2.6.1/fix-native/`. These silent
fixtures establish coordinator behavior with injected failures, not audible
radio output or OS policy on the user's phone.

The further native probe also passed its experimental preconditions: the actual
application state remained backgrounded at 32.09–32.41 seconds, with silent
standby running. All three real background API calls succeeded, including
`playAndRecord` with options 9. The OS refusal therefore was not reproduced by
either immediate or delayed iOS 26.5 simulator experiments. This is not physical
iOS 26.7.2 or overnight validation. Its evidence is in
`artifacts/ios-2.6.1/fix-probe/`; extracted raw API results are in
`artifacts/ios-2.6.1/native-probe-delayed.json`. The before/after coordinator results are in
`artifacts/ios-2.6.1/replay-comparison.json`.

Both simulator experiments passed one UI-driven probe case each; they were not
production UI layout sweeps. Production UI presentation is unchanged. The SE target
received Release compilation and package inspection, not an iOS 16 simulator run.

This is a targeted fix attempt for the demonstrated app failure. It does not
establish why iOS 26.7.2 rejected the category transition, nor guarantee a
background switch from an accessory to Speaker. Physical validation remains
necessary. No automatic system-volume setting, AlarmKit, station, quality,
widget presentation, Android or recognition change is included.
