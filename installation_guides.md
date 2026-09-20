# KUSC installation guides — Windows, iPhone SE, and iPhone 17

The supported zero-cost workflow is **public GitHub repository → standard macOS GitHub Actions runner → unsigned iPhone IPA → AltStore Classic with AltServer for Windows**. No local Mac, cloud-Mac subscription, paid Apple membership, or Apple credentials in GitHub are required. The Mac/Xcode runtime still performs compilation, on GitHub's runner. Standard runners are free for public repositories. [GitHub runner policy](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

**Automatic renewal is best effort.** Free provisioning still expires after seven days. AltStore attempts background refresh; it does not guarantee permanent availability or zero manual intervention. Refreshing an existing build does not require recompiling it. A failed background refresh is handled with **My Apps → Refresh All**. [AltStore refresh behavior](https://faq.altstore.io/altstore-classic/your-altstore), [Apple free provisioning limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

The workflow and packaging checks are included. No GitHub build or physical AltStore installation has been executed for this project in the current workspace. The first successful Actions run and device installation remain required evidence; no compiled IPA is claimed in this source ZIP. Full findings are in [windows_workflow_review.md](docs/windows_workflow_review.md).

## 1. Select the device build

| Phone | KUSC minimum OS | Actions artifact | File inside artifact ZIP |
|---|---|---|---|
| iPhone SE, 2nd generation (2020) | iOS 16.0 | `KUSC-SE-unsigned-ipa` | `KUSC-SE-unsigned.ipa` |
| iPhone SE, 3rd generation (2022) | iOS 16.0 | `KUSC-SE-unsigned-ipa` | `KUSC-SE-unsigned.ipa` |
| iPhone 17 | iOS 26.0 | `KUSC-17-unsigned-ipa` | `KUSC-17-unsigned.ipa` |
| Original iPhone SE (2016) | Unsupported | None | None |

Check **Settings → General → About** for the phone model and iOS version. The original SE cannot meet this project's iOS 16 deployment minimum. [Apple iOS 16 device compatibility](https://support.apple.com/en-us/103267).

**AltStore has its own OS requirement.** Current AltStore Classic 2.3 requires iOS 17.4 or later. For an SE still on iOS 16–17.3, current AltServer's documented compatibility selection downloads the latest compatible older AltStore release. Its availability and successful install must be checked on that phone; the current 2.3 IPA cannot be installed by ignoring its minimum OS. KUSC-SE itself retains the requested iOS 16 minimum. [AltStore release notes](https://faq.altstore.io/release-notes/altstore), [AltServer compatibility selection](https://faq.altstore.io/release-notes/altserver).

The SE package has no custom Dynamic Island extension. The iPhone 17 package includes one Live Activity extension. Both contain the same player core. Neither CI artifact includes the restricted full CarPlay app.

## 2. Put the source in a public GitHub repository

Install Git for Windows from [the official Git website](https://git-scm.com/downloads/win). Extract `KUSC_iOS_App.zip`. Work inside its `KUSC` directory, which contains `KUSC.xcodeproj`, `Shared`, `scripts`, and `.github`.

On GitHub, create an empty **public** repository named `KUSC`. Do not initialize it with another README or other files. [GitHub: create a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository).

Open PowerShell in the extracted `KUSC` directory. Replace `YOUR_GITHUB_NAME` in the remote URL:

```powershell
git init
git branch -M main
git add .
git commit -m "Add KUSC iPhone app and unsigned build workflow"
git remote add origin https://github.com/YOUR_GITHUB_NAME/KUSC.git
git push -u origin main
```

Complete GitHub's normal sign-in if requested. If Git requests a commit author, configure the intended Git username and email; GitHub supplies an optional no-reply address under account Email settings. This login is separate from Apple signing.

**Repository layout matters:** `.github/workflows/ios-device-build.yml` and `KUSC.xcodeproj` must both be at the repository root. Uploading the outer `KUSC` directory as a nested folder without moving `.github` to the root will prevent workflow discovery. Uploading only the ZIP does not create a buildable repository. Git includes the supplied `.github` directory through `git add .`.

Leave `DEVELOPMENT_TEAM` blank in `Configuration/Signing.xcconfig` for this route. Keep `KUSC_BUNDLE_PREFIX = org.personal.kusc` stable unless deliberately changing app identity. CI disables signing and does not need a unique registered developer identifier. AltStore performs personal provisioning during installation. Keep Apple passwords, certificates, profiles, and device identifiers outside the repository and GitHub secrets.

## 3. Compile both device IPAs on GitHub

1. Open the repository's **Actions** tab and enable Actions if GitHub requests it.
2. Open **Build unsigned iPhone apps**. Pushing to `main` or updating a pull request triggers it; **Run workflow** also starts it manually. Use the update's exact source revision when choosing an artifact.
3. Wait for the SE and iPhone 17 jobs to finish successfully. Each runs the Foundation test suite before building the actual `iphoneos` target.
4. Open the successful run's summary and download the artifact matching the phone from the table above. Artifact download may require signing into GitHub. [GitHub artifact downloads](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/downloading-workflow-artifacts).
5. Extract the downloaded artifact ZIP. The resulting `.ipa` is the file imported into AltStore. Keep a local copy; Actions artifacts in this workflow expire after 14 days.

The supplied workflow uses standard `macos-26`, an explicitly selected Xcode 26 installation, shared `KUSC-SE` / `KUSC-17` schemes, Release configuration, and **`generic/platform=iOS`**. The build is a device binary, not a simulator app. Apple signing is disabled. Packaging checks verify the app/extension structure, device architecture/platform, deployment versions, and absence of provisioning material before artifact upload.

The workflow runs only for public repositories. It excludes CarPlay schemes and contains no weekly schedule. GitHub rebuilds are needed after source changes or when an artifact needs to be regenerated; seven-day signing renewal happens through AltStore. Keep the standard runner label; larger runners are billed separately. [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

The September 20 update preserves the app and extension identifiers. Install its IPA over the existing KUSC app using the same Apple account and retain the iPhone 17 extension. The `native-ui-screenshots` artifact, when present, is simulator evidence, not an installable app. Scheduled output preferences refer to an output actually selected through iOS; keep that device connected and selected until the start, or explicitly choose current-output fallback. Automatic playback and fades still require on-device verification after installing the update.

If the job fails, open its failing step. A failed build produces no usable IPA. Xcode-image selection errors are resolved against GitHub's current [macOS 26 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), without switching the build to a simulator destination or adding Apple signing credentials.

## 4. Set up AltServer on Windows once

Use **AltStore Classic** for personal sideloading on Windows 10 or later. AltStore PAL is a different distribution route. Follow the current [official Windows installation instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) for the current AltServer release and its Apple software prerequisites.

1. Install the required iTunes and iCloud components. The official guide links the Apple-direct installers; it also links an alternate procedure for Microsoft Store iCloud installations.
2. Install AltServer for Windows. Enable its startup option and allow private-network access when Windows prompts.
3. Connect the phone by a data-capable USB cable, unlock it, and trust the computer. Use Lightning for the SE and USB-C for iPhone 17.
4. In iTunes, enable that phone's **Sync with this iPhone over Wi-Fi** setting and apply it.
5. Run AltServer as directed by its Windows guide. From its system-tray menu select **Install AltStore → the connected phone**.
6. Enter the normal free Apple Account in AltServer's local authentication prompt and complete its verification steps. The app project and GitHub workflow never request these credentials.
7. On the phone, trust the developer identity under **Settings → General → VPN & Device Management** if prompted. Enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm.
8. Open AltStore Classic, sign in as directed, and verify its connection to AltServer.

Use the current Windows AltServer release, particularly on recent iOS 26 versions: its 1.7.4 release specifically fixed apps crashing at launch on iOS 26.4. For two phones, install AltStore on both through the same Windows computer and Apple Account; official AltServer notes support that arrangement. [AltServer release notes](https://faq.altstore.io/release-notes/altserver).

## 5. Install on iPhone SE

1. Complete AltServer setup for the second- or third-generation SE. On iOS 16–17.3, verify that AltServer selected a compatible older AltStore; 2.3 requires iOS 17.4.
2. Download and extract `KUSC-SE-unsigned-ipa`, then place **`KUSC-SE-unsigned.ipa`** in the SE's Files app. A direct download to the phone also works; extract the GitHub artifact ZIP first.
3. Keep AltServer available on the same Wi-Fi network, or keep the phone connected by USB. Open **AltStore Classic → My Apps → +**, choose the IPA from Files, and complete the install.
4. Confirm that **KUSC** appears under AltStore's My Apps and shows an expiry date. Open KUSC from the Home Screen.
5. Confirm audio, lock-screen Play/Pause, background playback, rotation, and the in-app Live button. The buffer defaults to zero; its wheel setting is under the top-right gear.
6. Run **Refresh All** once while AltServer is reachable. Installation alone does not prove that refresh works.

Use the SE IPA even if the SE is updated to a newer supported iOS version. It does not need the iPhone 17 extension. The original 2016 SE remains unsupported.

## 6. Install on iPhone 17

1. Complete AltServer setup for the iPhone 17 on iOS 26 or later.
2. Download and extract `KUSC-17-unsigned-ipa`, then place **`KUSC-17-unsigned.ipa`** in Files.
3. With AltServer reachable, open **AltStore Classic → My Apps → +**, select the IPA, and install it.
4. If AltStore offers to remove app extensions, **keep the Live Activity extension**. Removing it removes the custom Dynamic Island presentation. This build uses one app App ID plus one extension App ID; AltStore's own registrations and other apps also consume the account's quota. [AltStore App ID accounting](https://faq.altstore.io/altstore-classic/app-ids).
5. Open KUSC and start playback in the foreground. Allow Live Activities in the phone's KUSC settings if offered. Inspect the compact and expanded activity, then test Play/Pause and Live. Its exact placement and lifetime remain controlled by iOS.
6. Run **Refresh All** once and verify that both AltStore and KUSC receive renewed expiration dates.

The local Live Activity does not use APNs, an App Group, or a CarPlay entitlement. Free signing has no identified restricted-entitlement blocker in this source configuration; successful provisioning and widget behavior still need an actual installation. System media controls continue working independently of the custom activity. Platform limits are documented in [platform_limits.md](docs/platform_limits.md).

## 7. Keep the existing build refreshed

For the local AltServer route documented here:

- Keep AltServer running on Windows and available during regular periods when the phone shares its Wi-Fi network; USB is a fallback.
- Keep AltStore's Background Refresh enabled, along with its applicable iOS Background App Refresh setting. Allow the computer to remain awake during refresh opportunities.
- Check that a manual **My Apps → Refresh All** succeeds after setup. Background refresh is a separate behavior that must be observed before relying on it.
- If refresh fails, reconnect to AltServer and use **Refresh All** before expiry. No new GitHub build or IPA download is required.
- If AltStore itself has expired, reinstall AltStore through AltServer using the same account, without deleting AltStore first; then refresh the managed KUSC app. [AltServer operation and recovery](https://faq.altstore.io/altstore-classic/altserver).

Do not rely on AltServer's separate direct **Sideload .ipa** command for this workflow. The documented direct-only route needs manual reinstall; importing through AltStore Classic puts KUSC under its refresh management. [AltServer sideloading and refresh](https://faq.altstore.io/release-notes/altserver).

AltStore Classic 2.3 also introduces Remote AltServer. That is a separate configuration; this guide does not require it. Same-network/USB instructions above apply to the local Windows AltServer route, not to every possible AltStore configuration. [AltStore 2.3 release notes](https://faq.altstore.io/release-notes/altstore).

A free account remains subject to seven-day profiles, up to three registered devices, three active apps per device, and ten App IDs. AltStore itself occupies an active-app slot; extensions affect App IDs. Account limits are not bypassed by CI or by refreshing. Two phones fit the documented device limit if other registrations leave capacity. [Apple limits](https://developer.apple.com/help/account/basics/about-your-developer-account), [AltStore active apps](https://faq.altstore.io/altstore-classic/activating-apps).

## 8. Update after source changes

Commit and push changes from the same repository:

```powershell
git add .
git commit -m "Update KUSC"
git push
```

Download the new matching artifact and import its IPA through AltStore again using the same Apple Account. Keep the existing bundle prefix and app variant so the install is an update to the same app. CI supplies the run number as the build version for the app and extension together. Do not delete KUSC before an ordinary update; verify that settings remain after the first update.

| Operation | Recompile on GitHub? | Import a new IPA? |
|---|---|---|
| Renew the current seven-day profile | No | No; use AltStore refresh |
| Install a changed source build | Yes | Yes |
| Reinstall an already-downloaded unchanged build | No | Use the saved IPA |
| Recover an expired AltStore | No KUSC rebuild | Reinstall AltStore through AltServer, then refresh KUSC |

## 9. Capability boundary and troubleshooting

**Full custom CarPlay is excluded from the free CI builds.** It requires Apple's managed audio entitlement and a matching provisioning profile. The optional CarPlay source and schemes remain in the project, but are not emitted by this workflow. Ordinary Bluetooth/AirPlay/vehicle audio is separate from that custom CarPlay UI. [Apple CarPlay entitlement process](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements).

| Symptom | Resolution |
|---|---|
| No workflow appears | Put `.github` at the repository root; enable Actions. |
| Jobs are skipped | Check that the repository is public and the branch/trigger matches the workflow. |
| Xcode build or tests fail | Inspect the failing job log; no valid IPA is produced until those errors are fixed. |
| AltStore rejects the file | Extract the Actions ZIP and select its `.ipa`; use the device-specific artifact. |
| Too many App IDs or active apps | Inspect AltStore's App ID/active-app lists; extensions count toward IDs. |
| AltStore cannot find AltServer | Check Wi-Fi sync, private-network firewall access, Windows wake state, or USB. |
| SE reports incompatible AltStore | Use AltServer's latest-compatible-version selection; current Classic 2.3 requires iOS 17.4. |
| KUSC stops opening after a week | Restore AltServer connectivity and refresh; recover expired AltStore first if necessary. |
| Recent iOS 26 app crashes after signing | Update Windows AltServer; 1.7.4 includes the documented iOS 26.4 signing fix. |
| Dynamic Island missing | Verify the 17 IPA, retained extension, Live Activities permission, and foreground playback start. |
| CarPlay entitlement failure | Use one of the two ordinary CI artifacts. |

Complete the first-use and long-duration checks in [manual_test_plan.md](docs/manual_test_plan.md). Direct installation from a Mac remains documented separately in [mac_installation.md](docs/mac_installation.md); it is optional for this Windows workflow.
