# Platform limits and verification status

Source review: 19 September 2026. This document distinguishes public API limits from behavior that still requires a signed build and physical device. No iPhone, Xcode runtime, CarPlay head unit, signing account, or provisioning profile was available in the development environment.

## System media controls

`MPRemoteCommandCenter` exposes a fixed set of public media commands. Its documented API has no arbitrary custom command or dedicated jump-to-live command. Consequently, a custom **Live** button cannot be promised inside Apple's native Now Playing control cluster. The app disables previous/next, skip, and position-changing commands, and publishes live-stream metadata. `MPNowPlayingInfoPropertyIsLiveStream` marks the media as a stream; it does not create an actionable Live command. A system-drawn LIVE label is not evidence of a working jump action. [Apple: remote command center](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter), [live-stream metadata](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfopropertyislivestream).

**Affected specification:** sections 13 and acceptance item 20. Play/Pause uses system media controls. Live is provided in the app and, for the iPhone 17 target, the separate interactive Live Activity. The entitled CarPlay interface can provide its own Live control. iOS determines the appearance and field selection of the native Lock Screen and Control Center panels; disabling a command does not guarantee that every OS version hides every disabled glyph.

## Dynamic Island and Live Activity

The iPhone 17 build uses ActivityKit/WidgetKit for an additional custom presentation. This is separate from iOS's native media presentation, whose layout belongs to the system. Compact content requests artwork alone; expanded content includes metadata and playback controls. The app retains its activity when paused rather than ending it immediately.

Apple controls which activities are visible and their placement. An activity can be active for at most eight hours; iOS then removes it from Dynamic Island. Its ended Lock Screen presentation may remain for up to four additional hours. A person may dismiss it earlier. Therefore indefinite paused visibility and exclusive control over Dynamic Island are unavailable. Live Activities cannot fetch network content themselves, and their combined static/dynamic payload is limited to 4 KB. Artwork must arrive through a small, bounded local representation. [Apple: Live Activity constraints](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

Expanded and Lock Screen buttons use App Intents. Playback operations belong in an `AudioPlaybackIntent` and execute in the containing app process; `LiveActivityIntent` also executes there. Locked-device actions remain subject to system authentication policy. A Live Activity is not a grant of unlimited execution time. [Apple: interactive widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [AudioPlaybackIntent](https://developer.apple.com/documentation/appintents/audioplaybackintent).

**Affected specification:** section 14 and acceptance item 22. Actual compact/expanded artwork sizing, competition with the system media activity, pause visibility, locked actions, and eight-hour expiry are physical-device checks. No claim of a successful iPhone 17 test is made.

## CarPlay provisioning

Apple must approve the audio-app managed capability. A development profile for the app's exact bundle identifier must contain `com.apple.developer.carplay-audio`. Merely adding that key to an entitlements file does not authorize deployment. Apple reviews requests; neither personal use nor paid membership guarantees approval. [Apple: requesting CarPlay entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements).

The ordinary `KUSC-SE` and `KUSC-17` schemes avoid this restricted entitlement. The optional `KUSC-SE-CarPlay` and `KUSC-17-CarPlay` schemes isolate the full CarPlay interface. CarPlay provisioning has not been inspected for the owner's account. Until Apple grants the capability, use an ordinary scheme. Generic vehicle audio output or the system's Now Playing screen does not establish that the custom programme-list app is provisioned.

**Affected specification:** section 15 and acceptance item 23. CarPlay lists remain informational and have no seek handlers; sleep-timer controls do not belong in the CarPlay interface.

## Background playback, paused capture, and scheduled starts

Active audio uses the playback audio-session category and background audio mode. A paused app has no unconditional entitlement to continue downloading and writing audio. iOS may suspend execution; background-task extensions provide limited completion time rather than a precise wake-up clock. [Apple: background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time).

The requested silent standby is a best-effort implementation for charging, plus the specified unplug grace policy. It cannot guarantee a scheduled start after suspension, force-quit, process termination, or reboot. It must not be described as an alarm-clock guarantee. The fallback is a local notification with an action that opens the app and starts live playback. Apple schedules local notifications independently of the process, but Focus, notification permission, device power state, and system delivery policy can affect presentation. [Apple: local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

**Affected specification:** sections 6.4 and 17. Buffered resume can use only bytes actually retained; suspended capture can leave gaps. Reopening the app after process death starts at live. A reboot destroys silent standby. A pending notification does not itself grant permission to start radio audio in a terminated process.

## Audio interruptions and output changes

Playback resumes after an interruption only when it was active beforehand, the user has not paused it in the meantime, and the OS permits session reactivation. Apple's `.shouldResume` interruption option indicates when automatic resumption is appropriate. [Apple: handling interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions).

AVPlayer normally pauses when headphones disconnect. The app deliberately resumes after `oldDeviceUnavailable` when playback is still requested, matching the owner's requested speaker-continuation policy. iOS selects the available route. `overrideOutputAudioPort(.speaker)` is a `playAndRecord` facility and is not used to force a playback-only session. [Apple: route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes), [output override](https://developer.apple.com/documentation/avfaudio/avaudiosession/overrideoutputaudioport(_:)).

**Affected specification:** sections 5.3–5.4. Bluetooth, wired headphones, AirPlay transitions, and call recovery require hardware testing, including a manual pause during an interruption.

## Required device evidence

Every entry below is **not run** in this environment. Record device model, OS version, app build, observed result, and logs when executing the checks in `manual_test_plan.md`.

| Scenario | Expected behavior to verify |
|---|---|
| Screen locked during audible playback | Audio and delayed metadata continue. |
| App backgrounded during audible playback | Playback continues without a new independent stream. |
| Paused longer than retention | Resume Where Paused clamps to oldest available audio. |
| Call interrupts active playback | Resume only when appropriate; a user pause remains respected. |
| Bluetooth/headphone disconnect | Active playback resumes on the remaining route, ordinarily speaker. |
| Standby while charging, then locked | Scheduled stream starts if standby remains executing; fallback notification exists. |
| Unplug for less than 10 minutes with battery at least 30% | Standby grace remains eligible. |
| Unplug for 10 minutes or battery below 30% | Standby ends; fallback notification remains. |
| Force-quit / system termination | Automatic standby start is not guaranteed; later app launch starts live. |
| Reboot | Standby is lost; inspect notification delivery after restart. |
| Live Activity paused, dismissed, or eight hours old | System lifetime rules are respected; playback controls remain available in app. |
| CarPlay head unit | Current metadata, Live, and informational programme list match phone state. |

No source review or unit-test result substitutes for these device checks.

## Free Windows/AltStore installation

The ordinary app schemes contain no restricted entitlements. The public-repository GitHub workflow builds those two schemes unsigned, for subsequent AltStore signing; it excludes the optional CarPlay targets. The local Live Activity remains included and adds one extension App ID to the modern build. No App Groups or remote push capability is requested.

Seven-day renewal remains mandatory, with best-effort background refresh. Current AltStore Classic's minimum OS is separate from KUSC-SE's iOS 16 deployment target. See [the installation guide](../installation_guides.md) and [the current viability audit](windows_workflow_review.md) for the compatibility and signing details.
