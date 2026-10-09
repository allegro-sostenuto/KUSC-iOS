# Home Screen widgets

Six separate gallery entries provide layouts with and without playback controls:

| Entry | Family | Content |
| --- | --- | --- |
| Play / Pause | Small, 2×2 | A single Play/Pause button |
| Album Art | Medium, 4×2 | Album artwork and Play/Pause |
| Now Playing | Medium, 4×2 | Work, movement, composer, performers and Play/Pause |
| The Full Picture | Large, 4×4 | Artwork, music details, programme, host and Play/Pause |
| Album Art Only | Small, 2×2 | Album cover filling the widget; no controls |
| Music Details Only | Medium, 4×2 | Work, movement, composer and performers; no controls |

No Home Screen widget contains Live. The existing Live Activity retains its controls. Dark backgrounds and button fills are black, with outlines for separation. The system can apply its own tinted or clear Home Screen appearance.

The app publishes its heard-item metadata, transport intent and a JPEG thumbnail as one atomic App Group file. This includes delayed playback; the extension does not fetch an independent live title. Content changes reload all six kinds. While playback is requested, a 30-second heartbeat renews the snapshot; a timeline entry expires its playing flag after two minutes without renewal. WidgetKit controls actual delivery, so this is a stale-state mitigation rather than a real-time guarantee. Paused widgets retain the last heard metadata.

On iOS 17 and later, an `AudioPlaybackIntent` invokes the same explicit Play/Pause methods as the player, persists the updated snapshot before returning, and does not open the player interface. Repeated Play and repeated Pause keep their stated meaning even when another widget is stale. Pausing preserves scheduled starts and uses existing interruption recovery policy. On iOS 16, a widget link opens the corresponding app profile to apply that action. A widget Pause received during cold launch suppresses launch autoplay.

Both app profiles embed one extension. The modern extension also hosts the existing Live Activity. Each profile has its own `group.<bundle-prefix>.<profile>.widgets` group. For direct Xcode signing, enable that App Group for the app and matching extension. For AltStore, CI preserves the entitlement using an identity-free ad-hoc signature; AltStore provisions and re-signs both bundles. Runtime lookup honors the matching re-signed group in `ALTAppGroups`. This behavior was checked against AltStore's [provisioning code](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/FetchProvisioningProfilesOperation.swift), [re-signing code](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/ResignAppOperation.swift), and [bundle keys](https://github.com/altstoreio/AltStore/blob/develop/Shared/Extensions/Bundle%2BAltStore.swift). Apple's [interactive widget documentation](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) describes app-process audio intents and the post-action timeline reload.

## Validation

[Build 31](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/37752808811) passed on October 8, 2026, from source `121b800016f8635c55002cf3c4815ed567775d09`, using Xcode 26.6 (17F113) and the iOS 26.5 SDK. Both device packages passed; 120 portable tests, 24 native audio tests, and 187 hosted plus nine UI tests per simulator profile passed. Both simulator profiles produced 41 validated native captures, including ten widget captures apiece. The widget intent metadata is present in both the app and extension binaries. This evidence does not replace the phone checks below.

Verified IPA SHA-256:

| Package | SHA-256 |
| --- | --- |
| KUSC-17 | `d0e4513f81759bee7280ce03e208d12be125945fa37c45e462d570a896235ac2` |
| KUSC-SE | `ddc0ae19810e5f65dbaeb6d06c95bbd02149743fe692c4bbcfc37742bed6b633` |

Artifact ZIP digests and local IPA checksums were verified. Windows checks cover the package structure, matching App Group identifiers, app/extension versions and device Mach-O platform. The full signature and entitlement audit ran on macOS CI; it was not substituted with a Windows signature check.

Automated checks cover snapshot round trips, corrupt-file fallback, bounded content, stale-state expiry, profile isolation, explicit intent behavior, scheduled-start preservation, and native view captures for all layouts in light/dark plus missing art and large text. Captures use the actual shared widget views inside a silent app fixture; they do not prove SpringBoard hosting or signed App Group access. Device builds validate the embedded extension, matching group entitlement, arm64 platform and absence of an owner signing identity.

Phone acceptance:

1. Install keeping the widget extension, open KUSC once, then add all six gallery entries.
2. Confirm Album Art Only is a small square with no controls, Music Details Only is medium with no controls, and the original four layouts retain their controls. No Home Screen widget has Live. Check light/dark and long titles.
3. Play and Pause from each of the four widgets with controls while the app is backgrounded. Repeated Play/Pause should keep the requested state. Test after an audio interruption and after force-quitting the app.
4. Rewind to an earlier work; confirm widget metadata/artwork follow what is heard. Pause and check the last heard item stays displayed. Missing artwork should show a music note.
5. Arm a scheduled start, pause from a widget, then verify the schedule remains and starts with its normal fade. Also pause after the scheduled start has fired.
6. Verify metadata sharing after AltStore refresh/re-signing, and that the existing Live Activity still works. On iOS 16, expect the app to open for transport commands.
