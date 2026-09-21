# KUSC for iPhone

Native private-use KUSC FM 91.5 player, with shared Swift/SwiftUI source and separate iOS 16 and iOS 26 app targets. Build from Windows through the included public-repository GitHub Actions workflow, then install with AltStore Classic and AltServer. Exact steps for both phones are in **[installation_guides.md](installation_guides.md)**; no local Mac or paid Apple membership is required for that route.

**Delivery status:** the starting revision `1cc5ae6` passed the [unsigned device workflow](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/35489878713); installation, background playback, and Live Activity were subsequently reported working by the owner. The September 20 update revises the interface, rolling-buffer timeline, and scheduled start. Its separate build/test results and remaining device checks are recorded in [the update report](docs/update_2026-09-20.md). Earlier successful playback does not validate the new implementation.

## Windows build and installation

1. Extract the KUSC folder and publish its contents at the root of a public GitHub repository, including `.github`. Keep the app bundle prefix stable and leave `DEVELOPMENT_TEAM` blank for this route.
2. The **Build unsigned iPhone apps** workflow runs Foundation tests and unsigned device builds on a standard `macos-26` runner. Download the appropriate `KUSC-SE-unsigned-ipa` or `KUSC-17-unsigned-ipa` artifact.
3. Extract the artifact ZIP. Import its IPA using **AltStore Classic → My Apps → +**, with AltServer for Windows reachable. Keep the Live Activity extension in the iPhone 17 build.
4. Enable Developer Mode and verify initial playback and manual Refresh All. Background refresh is attempted automatically; a missed refresh still requires intervention. The existing build is re-signed without a weekly source rebuild.

Public standard runners are free under [GitHub's runner policy](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). [AltStore documents](https://faq.altstore.io/altstore-classic/your-altstore) the seven-day expiry, background attempts, and manual fallback. Current AltStore 2.3 requires iOS 17.4; an SE on iOS 16 needs AltServer's documented last-compatible-version selection. The original 2016 SE cannot run this app.

The two ordinary schemes already exclude restricted entitlements and serve as the personal-sideload configurations. CI never builds the optional CarPlay variants and never receives Apple signing secrets. [Workflow viability and entitlement audit](docs/windows_workflow_review.md) distinguishes documentation/source verification from the still-unrun GitHub build and device tests.

Direct Mac/Xcode installation remains available in [mac_installation.md](docs/mac_installation.md). No existing app feature was removed to support unsigned compilation.

The KUSC app itself needs no third-party SDKs, API keys, backend, analytics, or account system. AltStore installation uses the owner's Apple Account separately. Project generation is already complete. `scripts/generate_project.py` can regenerate the project after source-file changes; it uses Python's standard library. The app icon is included in every required PNG size, with its original vector source.

| Scheme | Minimum OS | Features |
|---|---|---|
| KUSC-SE | iOS 16.0 | Shared full player, native system media controls |
| KUSC-17 | iOS 26.0 | Shared player plus interactive Live Activity |
| KUSC-SE-CarPlay | iOS 16.0 | SE build plus restricted CarPlay audio entitlement |
| KUSC-17-CarPlay | iOS 26.0 | iPhone 17 build plus restricted CarPlay audio entitlement |

CarPlay variants intentionally use the corresponding normal app's bundle identifier. Install one variant per device; installing another updates/replaces that app. Default schemes do not request the restricted entitlement.

## Implemented behavior

- High-quality-only KUSC streaming, background audio session, system Play/Pause, interruption handling, automatic speaker fallback after output disconnection, and a one-minute reconnect window returning to ordinary Play.
- Default zero-minute history; optional 1–15 minute wheel-controlled compressed rolling storage. A single HLS download path feeds playback and capture. Seeking clamps to retained audio. Resume Live is the default; Resume Where Paused clamps aged-out cursors to the oldest retained audio.
- Timestamped metadata, bounded album-art cache, programme and host information, five previous and up to ten station-published upcoming items relative to heard audio.
- Reference-based portrait and artwork-left landscape layouts, separate work/movement typography, timed programme rows, and Dynamic Type. Standard transport follows the rendering's Live / Play-Pause / overflow row; minimalist portrait enlarges Play-Pause above Live and overflow. Dark app surfaces and controls stay pure black with borders. Native system picker highlights retain their system appearance.
- Native programme long press with one selection haptic after eligibility is rechecked, no single-tap seeking, and no system scrub/skip commands.
- Zero-to-twelve-hour sleep wheel, app-pause timer choices, broadcast-item endpoint/fallback/retry decisions, linear fades, and network shutdown on completion.
- One-time scheduled start within 24 hours: real muted playback begins one minute early, then fades over the final ten seconds. Short/late readiness retains the original deadline where possible. Observed output preferences default to notification-only fallback if the selected route is unavailable. Charging policy, unplug grace, interruptions, and explicit user actions govern execution.
- iPhone 17 Live Activity with locally encoded artwork, Play/Pause and Live; optional CarPlay Now Playing and informational programme lists.

## Station interfaces and refresh

All URLs are centralized in `Shared/StationConfiguration.swift`. On 19 September 2026 the following official station/CDN interfaces returned usable responses:

| Purpose | Endpoint | Behavior |
|---|---|---|
| 96 kbps HE-AAC HLS | `https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.m3u8` | Follow master variant and session media playlist; buffered mode downloads each new AAC segment once |
| Current broadcast metadata | `https://schedule.kusc.org/v3/songs/KUSC/now?includeImage=true` | Refresh every 30 seconds during playback; 5 seconds while sleep endpoint retries are pending |
| Playlist and programmes | `https://schedule.kusc.org/v3/combined/KUSC?date=YYYY-MM-DD&combinedFormat=true&reversed=true&env=master` | Current Los Angeles date every 60 seconds; adjacent dates every 15 minutes |
| Programme schedule | `https://schedule.kusc.org/v3/programs/KUSC/day?env=master` | Verified reference; programme data is already in the combined feed |

The official [station listening page](https://www.classicalcalifornia.org/articles/how-to-listen-to-classical-california) publishes the AAC service; the station's web-player source identifies the metadata URLs. Full field mappings, sample responses, source links, and HTTP evidence are in [endpoints.md](docs/endpoints.md). The HLS format includes `EXT-X-PROGRAM-DATE-TIME`, allowing transport time to drive metadata lookup. Metadata failures never stop audio.

## Platform and source limits

These limits affect the requested acceptance criteria and are not hidden behind inactive controls:

- **Future pieces:** observed future programme blocks contain no songs. At live time the upcoming list therefore explains that pieces have not been published. Delayed playback can show already-broadcast pieces as upcoming relative to the listener. No playlist entries are fabricated.
- **Movement timing:** the feed gives explicit broadcast-item start/end timestamps, not an independently named movement boundary. The timer treats that supplied item endpoint as the reliable boundary; when absent it uses the next piece/programme start, retries for up to a minute, then fades. A multi-movement broadcast item cannot be split accurately without station data.
- **Lock Screen Live:** Apple's public remote command interface has no custom Live command. System controls provide Play/Pause, with seeking and track skips disabled. Live is available in the app, the custom iPhone 17 Live Activity, and the optional CarPlay Now Playing button. See [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter).
- **Dynamic Island:** iOS controls visibility, competition with native media UI, authentication and lifetime. Pausing does not explicitly end the app's activity. Apple limits an active Live Activity to eight hours; it is not guaranteed permanently visible. [Apple ActivityKit documentation](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
- **CarPlay:** full custom app UI requires an Apple-approved audio entitlement and matching profile. Adding the entitlement file alone does not grant access. [Apple CarPlay entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements).
- **Background execution:** silent standby is best effort, not an alarm guarantee. A paused capture can be suspended. Force-quit, system termination, or reboot may defeat automatic playback; an already-scheduled notification remains the fallback when the system can deliver it. Opening a delivered scheduled-start notification explicitly starts live, regardless of Auto-play preference.
- **Interrupted audio:** automatic resumption respects the system's `shouldResume` interruption flag. A denied audio session cannot be forced to resume safely.
- **Buffered segment joins:** local HLS AAC packets feed one continuous audio renderer, preserving decoder state across ordinary downloaded-file boundaries. The owner's build 9 test exposed regular dips with the former per-file player queue; physical acceptance of this replacement, exact seek precision, AirPlay and multi-hour operation remain required. See [audio_engine.md](docs/audio_engine.md).

The original requested specification is retained in [build_specification.md](docs/build_specification.md). [platform_limits.md](docs/platform_limits.md) explains the Apple restrictions and required device checks.

## Code layout

- `Shared/AppModel.swift`: playback intent, lifecycle, timers, schedule and integration coordinator.
- `Shared/Audio`: HLS/ADTS parsing, acquisition, strict local retention and continuous buffered playback.
- `Shared/Core`: Foundation-only tested policy definitions and timeline models.
- `Shared/Metadata`: station response parsing, refresh cache and inline artwork handling.
- `Shared/UI`: responsive native views, wheels, output picker and programme gesture.
- `Shared/System`, `Shared/Timers`: system media, notifications, artwork and silent standby.
- `Modern`, `Widget`: iOS 26 Live Activity attributes, media intents and presentation.
- `CarPlay`: isolated entitled scene and informational programme view.
- `Tests`: policy, stream-format and real station-schema regression tests.
- `.github/workflows/ios-device-build.yml`: two free personal-device CI artifacts.
- `scripts/build_unsigned_ipa.sh`, `scripts/validate_ipa.py`: unsigned packaging and device-binary validation.

Preferences use UserDefaults. Audio lives only in disposable temporary storage, excluded from backup and removed at a new process launch. No delayed cursor or active sleep timer is restored after process death. Only a pending scheduled date is persisted; reopening an app cannot make iOS retrospectively run a missed background timer.

## Validation on a Mac

```sh
cd KUSC
swift test
./scripts/build_and_test.sh
```

The script runs Foundation tests and unsigned simulator builds for all four schemes. It does not sign, install, or claim a hardware pass. For hosted XCTest execution, select `KUSC-SE`, choose an installed iPhone simulator, and press Command-U. Complete the separate physical-device checklist with the debugger detached. No test depends on live station availability; source fixtures are captured station data used only in tests.
