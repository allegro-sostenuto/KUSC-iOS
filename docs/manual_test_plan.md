# KUSC manual acceptance and device test plan

**Physical-device execution status: Not run.** The local Windows editing host has no signed iOS build, iPhone, CarPlay head unit, or Xcode runtime. Native builds and simulator checks run separately in macOS CI; their exact results are recorded in `update_2026-09-20.md`. Every actual-device check below remains **Not run**. Source review, policy tests and simulator layouts do not establish an audible continuity, background, hardware-route, or provisioning pass.

## Test records

Create a separate record for each device and build. Record the device model and generation, OS version and build, app scheme and build identifier, signing profile expiration, network, connected audio route, battery percentage, charging state, and whether the debugger was attached. Include observed behavior, timestamps, screenshots where useful, and device/Xcode logs for failures. A failed or blocked test must retain that status and its reason; do not mark it passed because a related unit test passed.

| Device configuration | Status |
|---|---|
| iPhone SE 2nd or 3rd generation, minimum supported iOS 16 installation | Not run |
| Owner's SE and its actual installed supported iOS version | Not run |
| iPhone 17 and its actual installed iOS 26 or later version | Not run |
| Approved CarPlay target with physical CarPlay head unit | Not run |

The original 2016 SE is outside this project's iOS 16 deployment range. Run the ordinary scheme first. Test the CarPlay scheme separately after the account and profile contain Apple's granted entitlement.

Before background and scheduled-start checks, stop debugging and launch KUSC from its Home Screen icon. Use actual station responses and identifiable music transitions. Network fault injection and controlled local response fixtures can supplement testing in a development build; fixture results do not establish that a live station field exists or is reliable.

## Specification acceptance matrix

Numbers correspond to the supplied specification's 38 acceptance criteria. “Within platform limits” means the documented adjustment in `platform_limits.md` must be recorded explicitly, not silently counted as exact compliance.

| # | Procedure and expected observation | SE | iPhone 17 |
|---|---|---|---|
| 1 | Clean install; launch with the default auto-play setting. Confirm current KUSC high-quality audio and the configured station URL. Disable auto-play, terminate, and reopen; playback remains idle until Play. | Not run | Not run |
| 2 | Play, lock the screen for 15 minutes, unlock, then background for another 15 minutes. Audible playback continues. Repeat while delayed. | Not run | Not run |
| 3 | Interrupt active playback with a call and then Siri. Resume when the system permits. Repeat from paused state and with a user pause during interruption; no unintended resume. | Not run | Not run |
| 4 | Unplug wired headphones and disconnect Bluetooth during active playback. Audio continues on the system-selected remaining route, ordinarily the speaker. Repeat while paused; no unintended play. | Not run | Not run |
| 5 | Remove network while playing. Verify visible elapsed reconnection status, recovery within 60 seconds, and normal idle Play after a full unsuccessful window. No separate Retry control appears. | Not run | Not run |
| 6 | Test every integer retention setting from 0 through 15. At each nonzero value, allow history to accumulate and seek through available audio. At zero, confirm the deliberate rewind range disappears. | Not run | Not run |
| 7 | Keep 15-minute retention active for at least 2 hours. Inspect temporary files and bounds; expired audio is immediately ineligible and files are deleted when execution permits. Check stale-file cleanup after relaunch. | Not run | Not run |
| 8 | Test both resume preferences. Pause briefly, then longer than retention. Resume Live returns live; Resume Where Paused resumes retained audio or the oldest available retained point after expiration. | Not run | Not run |
| 9 | From delayed and paused playback, press Live. Confirm audible live-edge playback and matching metadata. Repeat after network recovery. | Not run | Not run |
| 10 | Drag to both slider ends and intermediate positions. Hold the thumb while the oldest boundary advances, then release. The resulting position remains inside the current retained range. | Not run | Not run |
| 11 | Buffer across an identifiable piece transition, seek across it repeatedly, and compare title, movement, composer, performers, artwork, and programme context with the audible item. | Not run | Not run |
| 12 | Inspect portrait at standard text size. Confirm artwork, title/movement, composer, performers, retained range, and controls in the specified hierarchy. Long names wrap and remain scrollable. | Not run | Not run |
| 13 | Swipe right over the normal information region. Programme content replaces that region. Swipe left or use the back chevron to restore now playing. Vertical scrolling must not switch panels. | Not run | Not run |
| 14 | With sufficient published station context, show five previous and ten upcoming items relative to the heard timestamp. If the station provides fewer, show available real items and a truthful unavailable state without fabricated entries. | Not run | Not run |
| 15 | Long-press a retained item start. Verify one native selection haptic and seek on completion. Single tap, short hold, scrolling, future items, and expired starts must not seek. Test a boundary expiring during the hold. | Not run | Not run |
| 16 | Enable minimalist mode. Metadata, artwork, and programme swipe disappear; Play/Pause, Live, buffer control, gear, and all three overflow actions remain available. System metadata remains present. | Not run | Not run |
| 17 | Rotate in both directions, including the small SE landscape size. Normal artwork is left and information/controls right. Programme content remains scrollable. | Not run | Not run |
| 18 | Choose System, Light, and Dark. Change system appearance while System is selected. Check main screen and every sheet. | Not run | Not run |
| 19 | Test default, largest ordinary, and largest accessibility text sizes in both orientations. Long metadata and growing programme rows remain readable; settings, timers, and playback actions remain reachable by scrolling. | Not run | Not run |
| 20 | Check Lock Screen and Control Center metadata and Play/Pause. Attempt previous, next, skipping, and scrubbing. Verify disabled commands cannot seek. Record the unavailable custom system Live command under platform limits. | Not run | Not run |
| 21 | Exercise headset/Bluetooth Play/Pause and previous/next buttons. Only the supported playback actions change state. | Not run | Not run |
| 22 | Test compact artwork, expanded metadata and controls, paused retention, and delayed metadata in the separate Live Activity. Check locked controls, system placement, dismissal, and the eight-hour limit. | Not applicable: no Dynamic Island target | Not run |
| 23 | With an approved profile, inspect CarPlay current metadata, artwork, Play/Pause, Live, programme/host, and previous/upcoming context. Rows are informational and sleep-timer controls are absent. | Not run; requires entitlement/head unit | Not run; requires entitlement/head unit |
| 24 | First-use sleep value is zero. Set and reopen several durations, including 11:59 and 12:00. Selecting hour 12 forces minute 0; a value above 12 hours cannot be started. The chosen duration persists. | Not run | Not run |
| 25 | With a timer active, press Pause in app and exercise each Keep counting / Pause timer / Cancel timer action. Remote pauses display no in-app choice and keep counting. | Not run | Not run |
| 26 | At sleep expiry, test a reliable movement end within 10 minutes and one beyond 10 minutes. Finish the former at its end; begin fade immediately for the latter. If the live feed never supplies reliable timing, record that hardware case as unverified. | Not run | Not run |
| 27 | Capture volume/output behavior across a nominal 60-second fade. Verify linear gain, no sudden restart, and stop at zero. Test compressed fade when the chosen endpoint is less than 60 seconds away. | Not run | Not run |
| 28 | Test missing movement-end timing with next-start fallback within and beyond 10 minutes. With all timing absent, verify up to one minute of retries followed by fade. Audio and ingestion stop on completion. | Not run | Not run |
| 29 | Set a one-time start within 24 hours. Test near-now and near-24-hour boundaries, rejection of stale/past times, replacement, and cancellation. No repeat schedule exists. | Not run | Not run |
| 30 | Run the charging, unplug-grace, and battery-threshold matrix below without debugger attachment. Record actual standby survival and fallback behavior. | Not run | Not run |
| 31 | Schedule on battery with ordinary auto-play disabled. When the notification arrives, tap it from locked and unlocked states. The app opens and begins live playback. | Not run | Not run |
| 32 | Reach a scheduled time while already playing delayed audio. Playback and the listening position remain unchanged. | Not run | Not run |
| 33 | Force-quit while delayed, then reopen. Repeat after actual system termination. The old cursor is discarded; auto-play preference still determines whether live playback starts immediately. | Not run | Not run |
| 34 | Open Settings from the top-right gear in standard, programme, and minimalist layouts. | Not run | Not run |
| 35 | Open the overflow menu in standard and minimalist modes. Sleep Timer, Scheduled Start, and Audio Output are separate functional actions. | Not run | Not run |
| 36 | Inspect the installed icon at Home Screen and system sizes: red treble clef, white background, no text in the artwork. | Not run | Not run |
| 37 | Inspect all settings and overflow controls. No stream-quality selector exists. | Not run | Not run |
| 38 | Inspect the complete interface. No accounts, advertising, analytics interface, station browsing, on-demand content, or unrelated radio features exist. | Not run | Not run |

## Scheduled-start and lifecycle matrix

For each run, schedule a new near-future event, confirm notification permission and the displayed mode, then perform the action. Observe audible playback, notification presentation, foreground status, and logs. Do not infer notification delivery from silent-standby success.

| Scenario | Expected result to examine | SE | iPhone 17 |
|---|---|---|---|
| Charging, app foreground | Standby transitions to live at the selected time, if the session remains valid. | Not run | Not run |
| Charging, screen locked | Best-effort automatic start; fallback notification remains scheduled. | Not run | Not run |
| Charging, another app foreground | Same best-effort policy without debugger assistance. | Not run | Not run |
| Unplug for 9 minutes, remain at least 30%, replug | Standby eligibility continues during grace and after replug. | Not run | Not run |
| Remain unplugged for 10 minutes | Standby ends; scheduled start uses notification mode. Test the exact boundary in policy tests and approximate it with device logs. | Not run | Not run |
| Unplugged battery at 30% | Grace remains eligible until the time boundary or a reading below 30%. | Not run | Not run |
| Unplugged battery falls below 30% | Standby stops promptly and fallback remains. | Not run | Not run |
| Replug after fallback mode was entered | Record notification-mode behavior; do not assume a new automatic standby grant. | Not run | Not run |
| Phone initially on battery | Notification is the start path. Tap launches live even with normal auto-play off. | Not run | Not run |
| Scheduled time while delayed playback is already active | No live jump, restart, or metadata re-anchor. | Not run | Not run |
| Call/Siri interrupts standby near scheduled time | No unauthorized audio-session takeover; fallback remains usable. | Not run | Not run |
| Force-quit before scheduled time | Standby cannot survive the process. Inspect fallback notification and tap-to-play behavior. | Not run | Not run |
| Actual system termination before scheduled time | Record the termination reason from device logs; fallback behavior is observed independently. Force-quit is not a substitute for this test. | Not run | Not run |
| Reboot before scheduled time | Standby is lost. Inspect actual notification delivery after boot, unlock state, and successful tap-to-play. | Not run | Not run |
| Notification permission denied | Scheduling reports inability to establish the required fallback; no silent assumption of delivery. | Not run | Not run |
| Notification permission revoked after scheduling / Focus active | Record system suppression and app state; no guarantee of visible delivery is inferred. | Not run | Not run |
| Replace and then cancel a schedule | Only the latest schedule applies; cancellation removes pending delivery and standby. | Not run | Not run |

## Network, timing, and resource checks

The owner reports immediate intermittent pauses only when retention is enabled; Off is the control case. Record Off for five minutes, then 1, 5 and 15 minutes of retention on the same route/network, including initial startup and at least 30 minutes of segment joins. Correlate each audible pause with the debug queue depth, item transition, advertised/downloaded edge and last confirmed cursor. Repeat on speaker, Bluetooth and AirPlay. Specifically delay an arrival until the queue drains while later downloaded files already exist: playback must consume those files without waiting for another network arrival. A matching UI timestamp alone is not an audio pass.

| Check | Procedure and observation | SE | iPhone 17 |
|---|---|---|---|
| No network at launch | Confirm visible connection handling and return to ordinary Play after the retry window. Restore connectivity and use Play. | Not run | Not run |
| Wi-Fi to cellular and back | Switch while live, delayed, and paused. Record discontinuities and reconnection behavior. No Wi-Fi-only restriction applies. | Not run | Not run |
| Repeated stream failure | Perform at least five short interruptions plus one lasting beyond 60 seconds. Confirm no overlapping players or retry storm. | Not run | Not run |
| Metadata/artwork failures | Fail those requests independently while audio remains reachable. Audio continues and the app does not fabricate metadata or timing. | Not run | Not run |
| Late/malformed station data | Use a clearly marked development fixture for malformed data, then retest the real service. Verify graceful omission and audio continuity. | Not run | Not run |
| Paused background capture | Compare bytes actually retained while foregrounded versus locked/backgrounded. Document suspension gaps; do not claim unconditional background downloading. | Not run | Not run |
| Retention shrinks while delayed | Move from 15 to 1 to 0 minutes. Old timestamps become unseekable immediately; zero removes deliberate history and file writes. | Not run | Not run |
| Discontinuity in buffered audio | Seek across a network gap. The cursor resolves to available audio, and timestamps/metadata do not claim missing segments. | Not run | Not run |
| Sleep expiry after a seek | Seek or jump Live while the sleep policy is waiting or fading. Confirm endpoint reevaluation and eventual stop. | Not run | Not run |
| Sleep completion resource stop | Inspect network, player, reconnect activity, and buffer files after timer completion. No audio ingestion or buffer writes continue for the stopped stream. | Not run | Not run |
| Multi-hour playback | Play for at least 4 hours, including one hour delayed and repeated seeks. Record memory, storage, battery, data volume, audio continuity, and caches. | Not run | Not run |
| Activity lifetime | Continue playback beyond eight hours and inspect system removal/replacement of the custom activity. Audio remains independently controllable in app. | Not applicable | Not run |
| AirPlay | Change from speaker to AirPlay and back while live and delayed; confirm playback and metadata remain coherent. | Not run | Not run |
| Appearance/text size while active | Change appearance and system text size during playback, with every sheet open in turn. State and controls remain reachable. | Not run | Not run |
| Process-death cleanup | Accumulate temporary segments, force-quit, and reopen. No stale cursor is restored; stale temporary files are removed. | Not run | Not run |

## Sign-off

The package is **not device-validated**. Sign-off requires recorded results for both actual phones, resolved build/signing failures, bounded-storage and sleep-stop evidence, and an explicit account of platform-limited requirements. CarPlay sign-off additionally requires the approved entitlement and a head-unit run. Keep blocked checks visible with their reason; do not substitute an inferred pass.

## Windows / GitHub / AltStore workflow acceptance

Installation/runtime entries below are **Not run**. CI results apply only to the recorded commit; see `update_2026-09-20.md` for the latest build and screenshot evidence. Record the GitHub run URL/commit, AltServer and AltStore versions, device model, OS, and result when performing each remaining check.

| Check | Required observation | Status |
|---|---|---|
| Clean public-repository Actions run | Both Foundation test runs and iphoneos builds pass without Apple secrets | Passed at 85f1381, run 35508504490; subsequent changes require a new run |
| Artifact guard | Both actual IPAs pass validate_ipa.py and appear in the run artifacts | Passed at 85f1381 in CI and after local download |
| SE legacy AltStore selection, if applicable | On iOS 16–17.3 AltServer installs a compatible older AltStore | Not run |
| SE signing/install | Correct IPA imports through AltStore, appears in My Apps, and launches | Not run |
| iPhone 17 signing/install | App and kept Live Activity extension are provisioned and launch | Not run |
| Signed audio behavior | Background audio, system controls, retained seeking and timers work | Not run |
| Live Activity after re-signing | Compact/expanded artwork and app playback actions work | Not run |
| Manual refresh on both phones | Refresh All succeeds and expiration advances with no GitHub rebuild | Not run |
| Background refresh on both phones | Expiration advances after a background renewal while AltServer is reachable | Not run |
| Unavailable AltServer | Expiry behavior is recognized; restored connectivity/manual refresh recovers it | Not run |
| AltStore expiry recovery | AltServer reinstalls AltStore without intentional deletion; managed KUSC refreshes | Not run |
| Source update identity | New IPA with stable identifiers/account updates existing app and preserves settings | Not run |
| CarPlay boundary | Ordinary IPAs do not claim provisioned custom CarPlay templates | Not run |

One successful background renewal is evidence of that event only; it does not establish guaranteed future renewal.
