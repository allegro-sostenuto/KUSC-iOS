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
headphone rejection, actual activation failures, foreground focus, retaining an
established override, and a new accessory arriving after an ordinary speaker start.

## Validation

Pending: focused core/journal and hosted audio regressions, both ordinary Release
device targets, and a further native probe held in the background for 30 seconds
using silent standby before the category calls. The latter checks the actual
application state and elapsed background time. It is still an iOS 26.5 simulator
experiment, not physical iOS 26.7.2 or overnight validation.

This is a targeted fix attempt for the demonstrated app failure. It does not
establish why iOS 26.7.2 rejected the category transition, nor guarantee a
background switch from an accessory to Speaker. Physical validation remains
necessary. No automatic system-volume setting, AlarmKit, station, quality,
widget presentation, Android or recognition change is included.
