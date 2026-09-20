# KUSC installation using a Mac

This appendix describes the optional direct-Xcode route. The primary Windows workflow is in [installation_guides.md](../installation_guides.md).

This package contains native Swift source and an Xcode project. Build and sign it on a Mac, then install it on each phone. It is not a pre-signed IPA: a transferable, permanently installable iPhone binary cannot be produced without the owner's Apple signing identity and device provisioning. The project was prepared in a Linux environment; Xcode compilation and physical-device validation remain to be performed.

## 1. Choose the correct build

| Device | Minimum installed iOS | Xcode scheme | Dynamic Island extension |
|---|---|---|---|
| iPhone SE, 2nd generation (2020) | iOS 16.0 | `KUSC-SE` | No |
| iPhone SE, 3rd generation (2022) | iOS 16.0 | `KUSC-SE` | No |
| iPhone 8 | iOS 16.0 | `KUSC-SE` | No |
| iPhone SE, original (2016) | Unsupported by this project | None | No |
| iPhone 17 | iOS 26.0 | `KUSC-17` | `KUSCLiveActivity` |

Check the model and OS at **Settings → General → About**. The original four-inch SE cannot run iOS 16; Apple's iOS 16 compatibility list includes only the second- and third-generation SE. This app does not lower the requested iOS 16 minimum. [Apple: iOS 16 compatibility](https://support.apple.com/en-us/103267).

The SE build also runs on a supported SE updated beyond iOS 16; there is no need to downgrade it. The iPhone 17 build uses the available safe area and size class and does not require a manually selected screen resolution.

## 2. Mac, Xcode, and account preparation

1. Download Xcode from the Mac App Store or [Apple Developer Downloads](https://developer.apple.com/download/all/). Install the iOS platform components when prompted.
2. Use an Xcode release that supports both the Mac's macOS and the actual OS installed on the phone. **For an SE still running iOS 16, use Xcode 26.x.** Apple's matrix lists iOS 15+ device support for Xcode 26.x; Xcode 27 lists iOS 17+ device support even though its deployment targets include older systems. Do not confuse build deployment support with the ability to install/debug on an older device. [Apple: Xcode system requirements](https://developer.apple.com/xcode/system-requirements).
3. As a baseline, Xcode 26/26.0.1 requires macOS Sequoia 15.6 or a supported macOS Tahoe 26 version. Later 26.x releases have different Mac requirements; check the same matrix for the chosen version. Use a newer supported release if the phone's OS requires it.
4. Open Xcode once, accept its license, and allow component installation to finish.
5. In **Xcode → Settings → Accounts**, add the Apple Account used to sign the app. An account without paid membership appears as a **Personal Team**.
6. Extract the complete `KUSC` folder to a writable Mac folder. Keep the project, configuration, source, resources, and documentation together. Open **`KUSC.xcodeproj`**.

A free Personal Team can install for personal development. Apple's published limits include 10 App IDs, three devices, three installed apps per device, and provisioning expiration after seven days. Rebuild and reinstall when the profile expires. Paid membership removes this particular Personal Team workflow but still requires valid certificates and profiles; it does not produce permanent unsigned installations. [Apple: developer account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

There is no Windows/Linux Xcode installation path in this package. A physical Mac or an appropriately accessible Mac build environment is needed for Apple SDK compilation and signing. Initial USB installation is the simplest documented procedure below.

## 3. Configure signing once

The shared configuration is **`Configuration/Signing.xcconfig`**:

```xcconfig
KUSC_BUNDLE_PREFIX = org.personal.kusc
DEVELOPMENT_TEAM =
```

1. Replace `org.personal.kusc` with a stable identifier unique to the owner, for example `net.allegro.privatekusc`. Use letters, digits, dots, and hyphens; do not use spaces. If Xcode reports the identifier is unavailable, change this prefix.
2. Set `DEVELOPMENT_TEAM` to the ten-character team identifier shown for the Apple developer team, or choose the team in each relevant target's **Signing & Capabilities** tab. The latter writes a target-level setting that can override the shared configuration.
3. Keep **Automatically manage signing** enabled for the normal targets.
4. Select the project in the left navigator. For `KUSC-SE`, verify the selected Team and that no signing error remains.
5. For `KUSC-17`, set the same Team on both **`KUSC-17`** and **`KUSCLiveActivity`**. The extension must be signed by the same team as the containing app.

The resulting ordinary identifiers are:

| Target | Identifier |
|---|---|
| `KUSC-SE` | `$(KUSC_BUNDLE_PREFIX).classic` |
| `KUSC-17` | `$(KUSC_BUNDLE_PREFIX).modern` |
| `KUSCLiveActivity` | `$(KUSC_BUNDLE_PREFIX).modern.activity` |

Changing only the app identifier while leaving the extension identifier unchanged causes an extension-prefix signing error. Change the shared prefix to update both. No App Group registration is required. Live Activity artwork is included in a bounded payload.

## 4. Install on iPhone SE

These instructions apply to the second- or third-generation SE on iOS 16 or later.

1. Connect the SE to the Mac using a data-capable Lightning cable. Unlock the SE and accept **Trust This Computer** if shown.
2. In Xcode, open **Window → Devices and Simulators**, select the phone, and wait for pairing and device preparation. Newer Xcode versions may present device management under **Device Hub** instead.
3. On the SE, open **Settings → Privacy & Security → Developer Mode**. Turn it on, restart when prompted, then confirm after restart and enter the device passcode. If the setting is absent, initiate pairing from Xcode first. [Apple: enabling Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
4. Return to Xcode. In the top toolbar choose the **`KUSC-SE`** scheme and the connected physical SE as the run destination. Do not select an iPhone simulator or “Any iOS Device”.
5. Confirm the `KUSC-SE` signing Team under **Signing & Capabilities**. Leave CarPlay variants unselected unless Apple has granted that capability.
6. Choose **Product → Run** or press **Command-R**. Allow Xcode to register the device and create development signing assets when prompted. Keep the phone unlocked for the initial installation.
7. If the phone reports **Untrusted Developer**, follow the displayed trust instruction under **Settings → General → VPN & Device Management**, selecting the signing identity for this build. The exact label varies with iOS and profile type.
8. When KUSC opens, allow notifications if scheduled-start fallback is required. Launch defaults to playing the live station; a failed connection returns to Play after the reconnect window.
9. End the Xcode debug session, then open **KUSC** from its Home Screen icon. Disconnect the cable after installation. Test background playback from this independent launch rather than treating a debugger-attached session as proof of background behavior.

The SE interface has no Dynamic Island. Metadata and Play/Pause use the normal system Now Playing surfaces; Live is available in the app. The rolling buffer defaults to zero minutes. Set the desired duration with the wheel under the top-right Settings gear.

## 5. Install on iPhone 17

1. Confirm **Settings → General → About → iOS Version** is at least 26.0. Install an Xcode version compatible with that particular OS version.
2. Connect the phone to the Mac with a data-capable USB-C cable. Unlock it and accept the computer-trust prompt.
3. Pair the phone in Xcode's device-management window. Enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm as described above.
4. Open `KUSC.xcodeproj`, choose the **`KUSC-17`** scheme, and choose the physical iPhone 17 destination.
5. Verify **Automatically manage signing** and the same Team on `KUSC-17` and `KUSCLiveActivity`. Build the app scheme; the extension is embedded automatically. Do not run the extension scheme as the main app.
6. Choose **Product → Run** / **Command-R**. Complete any profile-trust prompt on the phone.
7. Open KUSC once in the foreground and start playback. Grant notification permission when configuring Scheduled Start.
8. In the iPhone's Settings, open **Apps → KUSC → Live Activities** and allow them if that setting is offered. Also check the system's locked-screen Live Activities setting if activities are hidden while locked. Live Activity availability remains controlled by iOS.
9. Return to the Home Screen while audio plays. Touch and hold the KUSC activity to inspect its expanded controls. Confirm Play/Pause and Live against the app's listening position. The system may choose the native media activity or another active task for prominent display.
10. Stop debugging and relaunch KUSC from its icon before testing locked playback, pausing, long-duration listening, and scheduled standby.

Custom activity artwork and controls do not replace Apple's system media panel. Its placement, lifetime, and authentication behavior are described in [platform_limits.md](platform_limits.md). An eight-hour activity expiry does not mean the audio itself has an eight-hour limit.

## 6. Keep a Personal Team installation working

Before or after its seven-day profile expires, reconnect the same phone, select the same scheme and Team, and press **Command-R** again. Use the same bundle prefix to update the existing app. Deleting the app first removes its settings and is unnecessary for an ordinary refresh. Each phone needs its own successful installation. Xcode must be able to contact Apple's signing services when renewal is required.

With paid membership, inspect the actual provisioning profile's expiration and renew it as required. No certificate, profile, password, or Apple Account credentials are included in this project.

## 7. Optional full CarPlay installation

The normal schemes install without the restricted CarPlay entitlement. Audio may play through a vehicle's selected output without enabling the custom CarPlay app.

Full CarPlay requires Apple approval and a matching provisioning profile:

1. Submit an audio-app request through [Apple's CarPlay entitlement process](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements). The capability required here is **CarPlay Audio App (CarPlay framework)**, represented by `com.apple.developer.carplay-audio`.
2. After approval, enable that additional capability on the exact app identifier in the developer account and generate a development profile containing the capability and the intended phone.
3. Choose **`KUSC-SE-CarPlay`** or **`KUSC-17-CarPlay`**, matching the phone. Set the signing Team on the corresponding target. The 17 variant also embeds `KUSCLiveActivity`; sign it with the same Team.
4. If automatic signing cannot obtain the approved profile, select the CarPlay target, disable automatic signing, and choose the downloaded development profile. Do not alter the ordinary targets to require CarPlay.
5. Build and run on the phone, then connect it to a compatible CarPlay head unit. Confirm programme rows are informational, with no seeking or sleep-timer controls.

Simulator display of a CarPlay interface does not prove that a physical phone has the required provisioning. If the build reports a missing CarPlay entitlement, install the ordinary scheme until the account/profile issue is resolved. Copying an entitlement key into a plist cannot substitute for Apple approval.

## 8. First-use checks on both phones

| Check | Procedure |
|---|---|
| Independent launch | Open from the Home Screen with no debugger; confirm current KUSC audio. |
| Background audio | Lock the phone for several minutes and use Play/Pause from the system controls. |
| Buffer | Set 2 minutes, wait for capture, seek back, then press Live. Metadata should match the heard audio. |
| Pause policy | Select Resume Where Paused, pause, then resume before and after the retained interval expires. |
| Layout | Rotate to landscape; increase system text size; artwork stays left in the normal landscape layout. |
| Scheduled Start | Permit notifications; schedule within 24 hours; test battery notification and charging standby separately. |
| Process death | Force-quit, reopen, and verify live playback rather than a restored delayed cursor. |

Use [manual_test_plan.md](manual_test_plan.md) for the remaining device and long-duration checks. These checks are instructions, not claimed results.

## 9. Troubleshooting

| Symptom | Action |
|---|---|
| Signing requires a development team | Select the same valid Team in each app/embedded extension target being built. |
| Bundle identifier unavailable | Change `KUSC_BUNDLE_PREFIX`; keep the extension derived from the app prefix. |
| Extension bundle identifier must begin with containing app identifier | Restore the shared-prefix relationship and rebuild. |
| iPhone listed as unavailable | Unlock it, finish pairing/Developer Mode, and use a compatible Xcode release. For iOS 16 devices, use Xcode 26.x. |
| App worked last week and now will not open | Renew the development profile by rebuilding and reinstalling with the same Team and identifiers. |
| Missing CarPlay capability/profile | Use the ordinary scheme or provision the approved CarPlay profile. |
| Dynamic Island activity absent | Verify the 17 scheme, embedded extension signing, Live Activities settings, and a foreground playback start. iOS can dismiss or deprioritize activities. |
| Scheduled notification absent | Check notification authorization, Focus, and device power state. Charging standby is best effort; process termination defeats it. |
| Play returns to idle after about a minute | Check network reachability and station service; the reconnect budget has expired. Press ordinary Play to begin a fresh attempt. |
| Older delayed audio is unavailable | It exceeded retention, capture paused/suspended, or the app restarted. Only retained audio can be sought. |

Keep the same source package and signing configuration for future rebuilds. The package includes no App Store submission or public distribution step.
