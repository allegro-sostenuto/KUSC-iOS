# Windows build and installation viability review

Review date: 2026-09-19 (UTC). Scope: the supplied Windows/GitHub/AltStore handoff and this project's existing targets, property lists, entitlement files, and Live Activity implementation.

## Finding

**The workflow is viable in design for personal installation of the ordinary KUSC iPhone app, with two material qualifications: automatic renewal is best effort, and the full custom CarPlay interface is excluded.** An unsigned device IPA is an intermediate artifact for AltStore to sign; it does not run unsigned on an iPhone. Actual clean macOS compilation, signing with the owner's Apple Account, installation, and background renewal still require an Actions run and the physical phones. Those steps have not been exercised by this review.

The handoff's strict requirement of guaranteed automatic renewal with no occasional intervention is **not established**. AltStore's own documentation says it attempts background refresh and provides manual `Refresh All`. The correct promise is no weekly **source rebuild**, with periodic **re-signing** still required. The existing app can be renewed without compiling it again. [AltStore: Getting Started](https://faq.altstore.io/altstore-classic/your-altstore), [AltStore source repository](https://github.com/altstoreio/AltStore).

## Confirmed facts and corrections

| Handoff topic | Verified conclusion |
| --- | --- |
| Windows installation | Officially documented. AltServer currently requires Windows 10 or later. No local Mac is required for this installation path. |
| Signing location | Treat this as an AltStore/AltServer workflow. AltStore's implementation description says the iPhone app re-signs applications and passes them to AltServer to install. Do not assert that every signing operation happens on Windows. |
| Free provisioning | Apple documents 10 App IDs, 3 devices, and 3 installed apps per device; App IDs/device registrations and provisioning profiles have seven-day limits. |
| Active-app budget | Budget one of the three slots for AltStore itself and one for the chosen KUSC app. Do not describe the limit as three additional applications beyond AltStore. |
| Extensions | Each extension requires an additional App ID. Keep the modern KUSC Live Activity extension during installation. |
| Routine renewal | Refresh the installed app through AltStore. No source rebuild or Actions run is needed just to renew its provisioning. |
| Automatic renewal | Best effort. Local AltServer must be running and reachable when iOS gives AltStore execution time. PC sleep, network discovery failure, or lack of background execution can prevent renewal. |
| Direct AltServer IPA import | The official release notes describe direct AltServer-only sideloads as requiring manual reinstallation after seven days. Import KUSC through AltStore's My Apps interface for tracked refresh. |
| Expired AltStore | Reinstall AltStore using AltServer without deleting the existing AltStore app first. |
| Full CarPlay interface | Requires Apple's managed CarPlay capability. Exclude the `*-CarPlay` targets from the free build. |

Sources: [AltStore downloads and platform requirements](https://altstore.io/), [Apple developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account), [AltStore active apps](https://faq.altstore.io/altstore-classic/activating-apps), [AltStore App IDs](https://faq.altstore.io/altstore-classic/app-ids), [AltServer operation](https://faq.altstore.io/altstore-classic/altserver), [AltServer release notes](https://faq.altstore.io/release-notes/altserver), [Apple managed capabilities](https://developer.apple.com/help/account/reference/provisioning-with-managed-capabilities).

The slot calculation applies Apple's three-app rule to AltStore, which is itself a sideloaded app. KUSC-SE and KUSC-17 have different application identifiers; installing both on one phone would consume two KUSC app slots. Install the model-appropriate build only. App ID counts below are KUSC's incremental requirements, not the account's total: AltStore and other installed applications can use further IDs.

## GitHub build configuration

GitHub lists `macos-26` as a standard public-repository runner. Standard hosted runners are free for public repositories; larger runners are separate billed products. The supplied workflow has a public-repository guard and uses no signing secrets. Its matrix builds the two existing ordinary shared schemes, runs `swift test`, and packages actual `iphoneos` outputs. [GitHub runner policy](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

The selected `/Applications/Xcode_26.6.app` is present in the reviewed [macOS 26 arm64 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md). This avoids depending on the current Xcode 27 preview label. The runner image is maintained by GitHub and can change; a missing pinned installation causes an explicit failure rather than a silent compiler change. Checkout and artifact-upload actions are pinned to their verified official v7.0.1 release commits. [Checkout release](https://github.com/actions/checkout/releases/tag/v7.0.1), [upload-artifact release](https://github.com/actions/upload-artifact/releases/tag/v7.0.1).

No duplicated PersonalSideload target is needed: ordinary schemes already isolate CarPlay, and the unsigned build script clears owner signing/provisioning settings. Stable bundle identifiers and one shared build-number override keep app and extension versions aligned. IPA validation is an additional structure/platform check after a real successful compilation; it does not compile the app itself.

## Completely unsigned input is supported by the signer

The source audit followed AltStore's [AltSign dependency](https://github.com/altstoreio/AltStore/tree/marketplace/Dependencies/AltSign) to its pinned signer implementation. The [entitlement reader](https://github.com/rileytestut/AltSign/blob/790b9ccdaf2cec831689395c527e80f1f2838041/AltSign/ldid/alt_ldid.cpp) tolerates an absent `LC_CODE_SIGNATURE`; the [pinned ldid implementation](https://github.com/rileytestut/ldid/blob/6a6a92de56ae2110e4d6f292b315df0f586d6af5/ldid.cpp) creates the needed signature command when signing. The app's empty entitlement configuration therefore does not require a preliminary ad-hoc signature in GitHub Actions. This is code-path evidence, not a successful install of this KUSC build.

## Version-specific findings

The current official AltStore Classic release notes list **2.3**, dated September 14, 2026, with a minimum of **iOS 17.4**. This minimum applies to the app release, not just its new Remote AltServer feature. The KUSC-SE deployment target remains iOS 16.0, but that alone does not mean current AltStore 2.3 runs on iOS 16. AltServer's published compatibility selection downloads a compatible AltStore version for an older device; availability and operation of that legacy combination have not been tested here. Use iOS 17.4 or later for the current AltStore path on an SE 2nd/3rd generation. KUSC-17 requires iOS 26.0 or later. [AltStore Classic release notes](https://faq.altstore.io/release-notes/altstore), [AltServer compatibility selection](https://faq.altstore.io/release-notes/altserver).

Windows AltServer's current release notes list **1.7.4**, dated March 24, 2026, which fixes sideloaded apps crashing on iOS 26.4. An old Windows AltServer installation is therefore not adequate evidence of current iPhone 17 compatibility. Use the current official Windows installer and keep it updated. [AltServer release notes](https://faq.altstore.io/release-notes/altserver).

AltStore 2.3 also introduces Remote AltServers. Its documentation specifies initial PC pairing, LocalDevVPN, and Wi-Fi rather than cellular; subsequent refresh need not reach the owner's local PC. This is a separate alternative to the handoff's local-server method. The reviewed page does not establish a price or a guaranteed renewal service, so it is not required by the zero-cost installation guide. The local AltServer method remains documented. [Remote AltServers](https://faq.altstore.io/altstore-classic/remote-altservers).

## Project capability and extension audit

These findings follow from the source files and generated Xcode project. “Retain” means no restricted entitlement was found for the implemented feature; it does not assert successful device execution.

| Component | Project evidence | Free personal build disposition |
| --- | --- | --- |
| KUSC-SE main app | `Configuration/App.entitlements` is an empty dictionary; `.classic` bundle ID; iOS 16.0 deployment target | Retain; one KUSC App ID; no extension in this target. |
| KUSC-17 main app | Same empty entitlement dictionary; `.modern` bundle ID; iOS 26.0 deployment target | Retain; one main-app App ID. |
| KUSC Live Activity extension | `.modern.activity` bundle ID, `com.apple.widgetkit-extension` in `Configuration/Widget.plist`, no `CODE_SIGN_ENTITLEMENTS` setting | Retain inside the modern app; one additional App ID. Choose to keep app extensions in AltStore. |
| Local ActivityKit updates | `NSSupportsLiveActivities` in app plist; `Activity.request(..., pushType: nil)` in `Modern/LiveActivityCoordinator.swift` | Retain. The implementation requests and updates locally and does not require an APNs entitlement. |
| Interactive Live Activity controls | `LiveActivityIntent` and `AudioPlaybackIntent` implementations in `Modern/PlaybackIntents.swift`, also compiled into the extension | Retain. No custom managed entitlement or App Group appears in this implementation. Controls still need physical-device validation. |
| Background audio | `UIBackgroundModes = [audio]` in app plist; application audio engine | Retain. This is a background-mode declaration rather than a CarPlay entitlement. iOS lifecycle restrictions still apply. |
| Lock-screen/system Now Playing | `MPNowPlayingInfoCenter` and remote commands in `Shared/System/NowPlayingController.swift` | Retain. No additional explicit signing entitlement is requested by the project. |
| Local timer notifications | UserNotifications implementation in `Shared/System/NotificationCoordinator.swift`; no `aps-environment` key | Retain. Local notification permission remains a user decision; remote push is not implemented. |
| Full CarPlay UI | `com.apple.developer.carplay-audio = true` in `Configuration/CarPlay.entitlements`; CarPlay scene in `App-CarPlay.plist`; `CARPLAY` compilation flag | Exclude from free IPA generation. Existing separate CarPlay targets can remain as source but are not free-signing deliverables. |
| App Groups, iCloud, push notifications, associated domains, keychain sharing | No corresponding entitlement is present in either ordinary app target or the Live Activity extension | No such capability needs provisioning in this workflow. |
| XCTest bundle | Test target only | Run in CI/simulator as configured; do not package the test bundle as a separately installed companion app. |

Apple describes local ActivityKit updates separately from push updates and implements Live Activities in widget extensions. The project follows that local architecture. This supports retaining the extension; it does not constitute a signed-device test. [Apple: Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

Full CarPlay exclusion does not disable ordinary audio routing to a car. On current systems, Apple also allows Live Activities to appear automatically in CarPlay; their buttons do not perform actions there. That system presentation is distinct from the custom CarPlay templates guarded by this project's managed entitlement. [Apple: CarPlay](https://developer.apple.com/carplay/), [Apple: Live Activity presentations and controls](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

## Windows prerequisites checked

AltStore's current Windows guide still specifies iTunes **and** iCloud installers obtained directly from Apple. It provides an alternate procedure for a required Microsoft Store iCloud installation. The documented setup includes USB pairing/trust, iTunes Wi-Fi sync, AltServer with private-network access, trusting the installed developer profile, and Developer Mode on iOS 16 and later. The guide does not establish Apple Devices alone as a replacement for these dependencies. [Official Windows setup](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), [Official troubleshooting](https://faq.altstore.io/altstore-classic/troubleshooting-guide).

Do not embed Apple credentials, signing certificates, profiles, or device identifiers into the public repository or Actions configuration. Supply Apple Account authentication only through the AltStore/AltServer installation flow. Preserve each build's bundle identifiers and use the same signing account when installing updates.

## Evidence boundary

Confirmed here: current primary documentation; the project's source entitlement and extension inventory; the distinction between compilation and renewal; the need to exclude full CarPlay from this free route.

Not confirmed here: a successful GitHub-hosted Xcode build; signing of the resulting IPA with the owner's account; launch on either physical phone; Live Activity behavior after re-signing; preservation of application data across a real update; reliable renewal on the owner's Windows/network setup. The local source checks and CI configuration cannot replace these device acceptance checks.

The first device acceptance sequence is: install through AltStore, launch and play KUSC, lock the phone and verify audio/Now Playing, manually refresh successfully, then observe the expiry date advance after a background renewal. Repeat for each phone. Keep the Windows computer available during local-server refresh. A successful observed background renewal demonstrates this setup worked at that time; it cannot guarantee every future renewal.
