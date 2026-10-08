# Home Screen widgets

Four separate gallery entries allow both medium layouts to coexist:

| Entry | Family | Content |
| --- | --- | --- |
| Play / Pause | Small, 2×2 | A single Play/Pause button |
| Album Art | Medium, 4×2 | Album artwork and Play/Pause |
| Now Playing | Medium, 4×2 | Work, movement, composer, performers and Play/Pause |
| The Full Picture | Large, 4×4 | Artwork, music details, programme, host and Play/Pause |

No Home Screen widget contains Live. The existing Live Activity retains its controls. Dark backgrounds and button fills are black, with outlines for separation. The system can apply its own tinted or clear Home Screen appearance.

The app publishes its heard-item metadata, transport intent and a JPEG thumbnail as one atomic App Group file. This includes delayed playback; the extension does not fetch an independent live title. Content changes reload all four kinds. While playback is requested, a 30-second heartbeat renews the snapshot; a timeline entry expires its playing flag after two minutes without renewal. WidgetKit controls actual delivery, so this is a stale-state mitigation rather than a real-time guarantee. Paused widgets retain the last heard metadata.

On iOS 17 and later, an `AudioPlaybackIntent` invokes the same explicit Play/Pause methods as the player, persists the updated snapshot before returning, and does not open the player interface. Repeated Play and repeated Pause keep their stated meaning even when another widget is stale. Pausing preserves scheduled starts and uses existing interruption recovery policy. On iOS 16, a widget link opens the corresponding app profile to apply that action. A widget Pause received during cold launch suppresses launch autoplay.

Both app profiles embed one extension. The modern extension also hosts the existing Live Activity. Each profile has its own `group.<bundle-prefix>.<profile>.widgets` group. For direct Xcode signing, enable that App Group for the app and matching extension. For AltStore, CI preserves the entitlement using an identity-free ad-hoc signature; AltStore provisions and re-signs both bundles. Runtime lookup honors the matching re-signed group in `ALTAppGroups`. This behavior was checked against AltStore's [provisioning code](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/FetchProvisioningProfilesOperation.swift), [re-signing code](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/ResignAppOperation.swift), and [bundle keys](https://github.com/altstoreio/AltStore/blob/develop/Shared/Extensions/Bundle%2BAltStore.swift). Apple's [interactive widget documentation](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) describes app-process audio intents and the post-action timeline reload.

## Validation

Automated checks cover snapshot round trips, corrupt-file fallback, bounded content, stale-state expiry, profile isolation, explicit intent behavior, scheduled-start preservation, and native view captures for all layouts in light/dark plus missing art and large text. Captures use the actual shared widget views inside a silent app fixture; they do not prove SpringBoard hosting or signed App Group access. Device builds validate the embedded extension, matching group entitlement, arm64 platform and absence of an owner signing identity.

Phone acceptance:

1. Install keeping the widget extension, open KUSC once, then add all four gallery entries.
2. Confirm small has only the button, the two medium choices differ, and large has all available metadata with no Live button. Check light/dark and long titles.
3. Play and Pause from each widget with the app backgrounded. Repeated Play/Pause should keep the requested state. Test after an audio interruption and after force-quitting the app.
4. Rewind to an earlier work; confirm widget metadata/artwork follow what is heard. Pause and check the last heard item stays displayed. Missing artwork should show a music note.
5. Arm a scheduled start, pause from a widget, then verify the schedule remains and starts with its normal fade. Also pause after the scheduled start has fired.
6. Verify metadata sharing after AltStore refresh/re-signing, and that the existing Live Activity still works. On iOS 16, expect the app to open for transport commands.
