# KUSC iOS App — ChatGPT Work Build Specification

## 1. Purpose

Build a private-use iOS app named **KUSC** whose sole purpose is to stream **KUSC FM 91.5 / Classical California** with a minimal, high-quality native iOS experience.

This is not intended for public App Store distribution. It is intended for installation on the owner's own devices.

Produce a complete, buildable Xcode project with source code, assets, entitlements/capabilities configuration, tests for critical state logic, and a concise README explaining build/sign/install steps.

Do not add unrelated features, accounts, analytics, advertising, social features, donations, news, station discovery, or other radio stations.

---

## 2. Targets

Create two app targets sharing as much code as practical.

### Target A — iOS 16
- Minimum OS: **iOS 16.0**
- Primary device/layout target: **iPhone SE / iPhone 8-size screen**
- Optimize the UI for a 4.7-inch, 375 × 667 pt-class layout.
- Must support portrait and landscape.
- No Dynamic Island-specific UI is required on this target.

### Target B — iOS 26
- Minimum OS: **iOS 26.0**
- Primary device/layout target: **iPhone 17**
- Optimize the layout for the actual iPhone 17 size class rather than hard-coding a presumed pixel resolution.
- Must support portrait and landscape.
- Include Dynamic Island integration as specified below.

Prefer:
- one Xcode workspace/project,
- one shared playback/network/metadata core,
- shared SwiftUI views where practical,
- conditional availability / target-specific presentation for iOS 26 features.

Do not fork business logic unnecessarily.

---

## 3. Technology Direction

Preferred stack:
- **Swift**
- **SwiftUI** for app UI
- **AVFoundation / AVPlayer** or another first-party Apple audio stack appropriate for robust HLS/HTTP live streaming
- **AVAudioSession** with background audio capability
- **MediaPlayer / MPNowPlayingInfoCenter / MPRemoteCommandCenter** for Lock Screen, Control Center, headset controls, and external media controls
- **ActivityKit / relevant iOS 26 APIs** for Dynamic Island where platform support permits
- **CarPlay framework / audio-app integration** where entitlement support permits
- Local file-backed segmented rolling buffer for rewind/pause history
- Native local notifications for battery-powered scheduled starts

Use only Apple frameworks unless a third-party dependency is genuinely necessary. If a dependency is introduced, document why.

---

## 4. KUSC Data Sources

All station data must come **directly from KUSC / Classical California infrastructure**.

Required data:
- live high-quality audio stream,
- current work and movement title,
- composer,
- performers,
- album artwork,
- current programme name,
- current host,
- previous playlist items,
- upcoming playlist items,
- start times and any available timing metadata.

Do not use an unrelated third-party metadata proxy.

Before implementing the player:
1. Identify and verify the current KUSC high-quality live-stream endpoint.
2. Identify and verify KUSC/Classical California metadata/playlist endpoints.
3. Document the endpoint formats and refresh behavior in the repository README.
4. Make endpoint URLs configurable in one centralized source file/config object rather than scattering literals through the app.
5. Handle missing, delayed, malformed, or temporarily unavailable metadata gracefully.

Only **high-quality** streaming is required. There is no High/Low/Auto quality selector.

If KUSC exposes multiple stream formats, choose the highest-quality stable format that is compatible with the target OS versions.

---

## 5. Core Playback Behavior

### 5.1 Launch behavior
A user preference controls whether the app begins streaming automatically when launched.

Default:
- **Auto-play on launch: ON**

Settings must allow this to be changed easily.

Explicit scheduled-start actions always override this preference and start playback when invoked.

### 5.2 Background playback
Playback must continue when:
- the screen locks,
- the app is backgrounded,
- another app is in the foreground.

Configure the audio session and background modes appropriately.

### 5.3 Audio interruptions
If playback was active before an interruption such as a phone call:
- resume automatically when the interruption ends.

Do not auto-resume if playback was already paused before the interruption.

### 5.4 Audio route changes
If headphones are unplugged or a Bluetooth output disconnects:
- continue playback,
- route audio to the iPhone speaker,
- do **not** automatically pause.

### 5.5 Network usage
No Wi-Fi-only restriction.
Cellular streaming is permitted.

### 5.6 Reconnection
If the stream connection drops while playback should be active:
- enter a visible **Reconnecting** state,
- retry automatically for up to **1 minute**,
- display retry/reconnecting status visibly, including elapsed retry time or equivalent clear progress,
- if reconnection succeeds, resume playback automatically,
- if reconnection still fails after 1 minute, stop playback and return to the normal idle Play state.

After the retry window expires:
- do not show a special Retry button,
- revert to the ordinary **Play** button.

---

## 6. Rolling Audio Buffer

### 6.1 Purpose
Allow the user to pause or seek backward while the live stream continues to be ingested.

### 6.2 Retention setting
Settings must contain a rolling-buffer retention picker:

- range: **0–15 minutes**
- increment: **1 minute**
- UI: Apple-style **vertical wheel picker**, visually similar to the native Timer picker
- default: **0 minutes**

At 0:
- no deliberate rewind history is retained beyond what the underlying streaming stack minimally requires.

At N minutes:
- retain only the most recent N minutes before live time.

### 6.3 Storage
Local temporary storage is allowed.

Use a bounded, segmented rolling buffer:
- immediately make audio older than `liveTime - retentionDuration` ineligible for playback,
- delete expired segments as soon as the app has execution time to do so,
- never allow the buffer to grow unbounded,
- exclude temporary rolling-buffer data from backup,
- clean stale temporary files on next launch after crashes/termination.

The implementation should keep storage usage as low as practical.

### 6.4 Pause behavior
A user preference controls what happens when resuming after a manual pause.

Options:
- **Resume Live**
- **Resume Where Paused**

Default:
- **Resume Live**

If **Resume Where Paused** is selected:
- continue ingesting the stream while paused when background execution permits,
- on resume, return to the paused position if it is still retained,
- if that position has aged out of the rolling buffer, resume from the **oldest retained audio**, not from live.

A visible **Live** button always jumps directly to the live edge.

### 6.5 Progress / seek bar
Show a seek/progress slider when the rolling buffer is enabled.

Semantics:
- left edge = **oldest retained audio**
- right edge = **live edge**
- thumb = current listening position

The user may seek anywhere inside the retained range.

When retention is 0, the UI should collapse into an appropriate non-seekable/live representation rather than showing a misleading rewind range.

### 6.6 Metadata synchronization
All displayed metadata must follow the **audio currently being heard**, not merely the station's current live metadata.

This applies to:
- album artwork,
- work/movement,
- composer,
- performers,
- programme context,
- previous/upcoming playlist relationship.

If listening 7 minutes behind live, display the metadata corresponding to the audio 7 minutes behind live.

Maintain a timestamped metadata timeline alongside buffered audio segments.

---

## 7. Main Player UI

### 7.1 Standard portrait layout
Top-to-bottom structure:

1. navigation/header area
   - app identity as appropriate
   - **gear icon at top right** for Settings
2. album artwork
3. work and movement title
4. composer
5. performers
6. buffer/progress slider
7. primary playback controls

Primary playback controls visible on the main screen:
- **Play / Pause**
- **Live**
- progress/buffer slider

Do **not** show:
- previous track,
- next track,
- skip forward,
- skip backward,
- an on-screen volume slider.

System volume buttons control volume.

### 7.2 Overflow menu
A **···** menu provides:
- **Sleep Timer**
- **Scheduled Start**
- **Audio Output**

These remain separate menu items.

Settings are **not** in this menu; Settings use the top-right gear icon.

### 7.3 Audio output
The Audio Output item should expose Apple's standard route picker when possible, allowing the user to select among available:
- iPhone speaker,
- connected Bluetooth audio devices,
- AirPlay destinations,
- other system-supported routes.

Keep this control available in minimalist mode.

---

## 8. Programme View

In standard mode, programme/host information is hidden by default.

Gesture:
- swipe **right** from the normal now-playing content to reveal the programme view.
- the programme view **replaces** the album-artwork + work/composer/performer information region.
- it must not squeeze a second panel beside the normal content on the narrow portrait layout.
- provide the natural inverse gesture/navigation to return to the normal player view.

Programme view contents:

At top:
- programme name
- host name

Below:
- scrollable list of **5 previous pieces**
- scrollable/current-context list containing **10 upcoming pieces**
- each item shows:
  - piece/work name
  - composer name

The list must be relative to the **audio being heard**, not necessarily live time.

### 8.1 Long-press seek
On the iPhone programme list:
- a piece whose start timestamp lies inside the currently retained buffer may be used as a seek target.
- use **tap-and-hold / long press**, not a normal tap.
- provide progressively stronger system haptic feedback during recognition, approximating native Haptic Touch / legacy 3D Touch feel.
- use the system-standard long-press timing rather than inventing a custom duration.
- when the long press completes, jump playback to that piece's beginning.

Pieces whose beginnings are outside the retained window or in the true future are informational only.

Normal single taps should not accidentally seek.

---

## 9. Minimalist Mode

Settings include:
- **Minimalist UI: ON/OFF**

Default:
- standard/full UI

When Minimalist UI is enabled:
- hide album artwork,
- hide work/movement title,
- hide composer,
- hide performers,
- disable/hide the programme swipe view,
- retain only necessary playback/navigation controls.

Minimalist main UI should retain:
- Play/Pause
- Live
- progress/buffer bar
- top-right Settings gear
- ··· overflow menu
- audio output access through ···
- timers through ···

Minimalist mode affects only the in-app screen.

It must **not** suppress metadata/artwork on:
- Lock Screen,
- Control Center Now Playing,
- Dynamic Island,
- CarPlay.

---

## 10. Landscape Layout

Landscape is supported on both targets.

For the normal now-playing view:
- use a two-column layout,
- **album artwork on the left**,
- metadata and playback controls on the right.

Do not merely preserve the portrait vertical stack.

The layout must remain usable with Dynamic Type enabled and on the iPhone SE-class width/height constraints.

Programme view in landscape should remain scrollable and should preserve easy access to playback controls without compressing text into unusable widths.

---

## 11. Appearance and Accessibility

### 11.1 Appearance
Settings:
- System
- Light
- Dark

Default:
- **System**

### 11.2 Dynamic Type
Support **Dynamic Type**.

Text must follow the user's system text-size preference and reflow sensibly.

Requirements:
- long classical work names may wrap,
- composer/performer labels must not clip unnecessarily,
- programme list rows may grow vertically,
- controls remain usable at larger text sizes.

VoiceOver-specific optimization is **not required**.

Do not deliberately break standard accessibility behavior, but no special VoiceOver work is necessary.

---

## 12. Visual Identity

App name:
- **KUSC**

Home Screen icon:
- white background
- red treble clef
- **no text**

The in-app visual style should be restrained and native.
Avoid clutter and decorative elements that do not support playback.

Use KUSC-inspired red sparingly for identity/accent where appropriate while retaining native iOS readability in Light and Dark appearance.

---

## 13. Lock Screen / Control Center Now Playing

Provide a full Now Playing integration.

Display, to the extent supported by the system:
- album artwork,
- work and movement title,
- composer,
- performers.

Remote controls:
- **Play/Pause**
- **Live**

Disable:
- previous,
- next,
- skip forward,
- skip backward,
- seeking/scrubbing from system remote interfaces.

There should be **no seeking from Lock Screen**.

The app's own in-app buffer slider remains the place for manual seeking.

Headphone/Bluetooth media control commands:
- support **Play/Pause**
- disable/ignore Previous and Next commands.

---

## 14. iOS 26 Dynamic Island

iOS 26 target only.

### Compact presentation
Show:
- **album artwork only**

### Expanded presentation
Show:
- album artwork
- work/movement title
- composer
- Play/Pause
- Live

When playback is paused:
- keep the Dynamic Island presentation visible,
- retain current artwork and controls.

Metadata should represent the audio being heard, including delayed buffered playback.

Implementation note:
- first verify the exact iOS 26 media/Dynamic Island APIs and limitations.
- if iOS does not permit custom album artwork or persistent custom media UI in the exact requested Dynamic Island state, implement the closest system-supported behavior and document the limitation precisely.
- do not fake unsupported system UI.
- do not remove the requirement without first testing the relevant APIs on the target device.

---

## 15. CarPlay

Provide **full CarPlay support** where Apple's entitlement/provisioning allows it.

CarPlay should expose:
- current album artwork,
- work/movement title,
- composer,
- performers,
- Play/Pause,
- Live,
- programme/host information,
- playlist context:
  - 5 previous pieces
  - 10 upcoming pieces

The programme list in CarPlay is **informational only**.

Do not allow playlist-item seeking from CarPlay.

Do not expose Sleep Timer controls in CarPlay.

CarPlay playback state and metadata must stay synchronized with the phone and the delayed/live position.

Implementation note:
- verify whether the signing account/provisioning profile can obtain the required CarPlay audio entitlement.
- if entitlement provisioning blocks deployment, keep the CarPlay implementation isolated and documented rather than breaking the rest of the project.

---

## 16. Sleep Timer

Accessible from:
- **··· → Sleep Timer**

### 16.1 Picker
Use an Apple-style vertical wheel picker.

Range:
- 0 to **12 hours**

The picker should represent hours/minutes naturally.
A duration of 0 means off/no timer.

Initial first-use value:
- **0**

After use:
- remember the last selected duration.

### 16.2 Manual pause while sleep timer is active
If the user presses Pause inside the app while a sleep timer is active, show a popup/action sheet with:
- **Keep counting**
- **Pause timer**
- **Cancel timer**

If playback is paused from:
- Lock Screen,
- headphones,
- Bluetooth controls,
- other remote media controls,

then:
- **keep the sleep timer counting**
- do not require a popup outside the app.

### 16.3 Expiry behavior
The timer does not normally cut audio immediately.

At timer expiry:

#### Case A — reliable current-movement end time is known
- If the current movement will end within **10 minutes**, continue playback through the end of the current movement, then stop.
- If more than 10 minutes remain, begin a **1-minute linear fade to zero immediately**, then stop playback.

#### Case B — movement-end time is not directly available
Use the next programme/track start time as the fallback endpoint.

- Retry/fetch metadata as needed.
- If the next start time is known and is within 10 minutes:
  - continue,
  - begin a linear fade **1 minute before the next start time**,
  - reach zero at the transition,
  - stop.
- If the fallback endpoint is more than 10 minutes away:
  - begin the 1-minute linear fade immediately,
  - stop when fade reaches zero.
- If the next start time is still unavailable after **1 minute of metadata retries**:
  - begin the 1-minute linear fade immediately,
  - stop when it reaches zero.

If an endpoint is less than 60 seconds away when the fade should begin, compress the linear ramp so that playback reaches zero no later than the intended endpoint.

When sleep-timer stopping completes:
- stop playback,
- stop stream ingestion,
- stop rolling-buffer writes,
- cancel playback-related reconnect attempts.

Do not leave the network stream silently consuming data after the timer has finished.

---

## 17. One-Time Scheduled Start

Accessible from:
- **··· → Scheduled Start**

This is distinct from Sleep Timer.

### 17.1 Scope
- one-time schedules only
- no repeating schedule
- scheduled time must be within the **next 24 hours**
- allow arbitrary date/time within that 24-hour window

If the stream is already playing when the scheduled time arrives:
- do nothing,
- leave playback unchanged.

### 17.2 If phone is plugged into power
Preferred behavior:
- keep the app alive using a silent-audio standby mechanism until the scheduled start,
- at scheduled time, transition to KUSC playback automatically,
- no unlock or user interaction should be required if the standby mechanism is still valid.

This is a private-use requirement.

However:
- treat silent-audio background residency as **best-effort and device-tested**, not as a guaranteed iOS scheduling API.
- always schedule a fallback local notification so failure of the standby strategy does not silently lose the alarm.

### 17.3 Temporary unplug behavior
If the device is unplugged before scheduled start:

If:
- battery remains **>= 30%**, and
- the phone is plugged back in within **10 minutes**,

then:
- keep silent-audio standby running during that 10-minute grace period,
- continue with automatic scheduled playback when appropriate.

Switch to notification-based behavior if either:
- the device is not plugged back in within 10 minutes, or
- battery drops below **30%** while unplugged.

Cancel silent standby when switching to notification mode.

### 17.4 If phone is on battery / notification mode
Use a native local notification at the scheduled time.

The notification should clearly indicate that KUSC is scheduled to start.

Tapping the notification:
- opens/activates the app,
- starts playback **immediately**,
- ignores the ordinary Auto-play on launch preference for this action.

A notification by itself does not need to start live audio without user interaction when the app is not already executing.

No Shortcuts integration is required.

### 17.5 Failure / termination
A force-quit or system termination may defeat the silent-audio standby path.

The fallback notification should remain scheduled when technically possible.

Document actual tested behavior for:
- screen locked,
- backgrounded,
- force-quit,
- system-terminated,
- rebooted,
- unplugged/replugged,
- battery crossing 30%.

---

## 18. App Lifecycle and Restore Rules

### Backgrounded
If the app is merely backgrounded:
- playback should continue,
- delayed playback position should continue normally,
- buffer state should continue as allowed by the running audio session.

### Force-quit
If the user force-quits the app and later relaunches:
- start/resume from **live**, not an old delayed position.

### System termination
If iOS terminates the app and it is later relaunched:
- start/resume from **live**.

Do not attempt to restore stale delayed playback after process death.

Persistent preferences may be restored, including:
- Auto-play on launch
- Resume Live vs Resume Where Paused
- buffer retention duration
- Minimalist UI
- appearance mode
- last Sleep Timer duration

Do not persist an obsolete buffer playback cursor across termination.

---

## 19. Settings

Settings are accessed from a **gear icon in the top-right corner**.

Include at minimum:

### Playback
- Auto-play on launch
  - default: ON
- Resume after manual pause
  - Resume Live
  - Resume Where Paused
  - default: Resume Live
- Rolling buffer duration
  - 0–15 minutes
  - step 1 minute
  - wheel picker
  - default 0

### Interface
- Minimalist UI
  - default OFF
- Appearance
  - System / Light / Dark
  - default System

Do not include a stream-quality selector.
The app always uses the chosen high-quality KUSC stream.

---

## 20. Programme Metadata and Timing Model

Create a timestamped metadata model sufficient to associate buffered audio with programme information.

Recommended conceptual structure:

- `PlaybackTimeline`
- `AudioSegment`
  - local URL
  - stream start timestamp
  - stream end timestamp
- `ProgrammeItem`
  - start timestamp
  - end timestamp if known
  - work title
  - movement title
  - composer
  - performers
  - artwork URL
  - programme name
  - host
- live-edge clock mapping

Requirements:
- metadata updates must not abruptly replace delayed playback metadata,
- delayed playback should resolve metadata from the timestamp being heard,
- when seeking, metadata updates immediately to the seek destination,
- programme-list context should re-anchor around the newly heard piece,
- artwork should be cached modestly to avoid unnecessary repeat downloads,
- metadata cache must remain bounded.

---

## 21. Network and Error Handling

Handle at minimum:
- no network at launch,
- stream endpoint unavailable,
- metadata endpoint unavailable while stream still works,
- artwork unavailable,
- malformed metadata,
- metadata lagging behind audio,
- Wi-Fi ↔ cellular transition,
- Bluetooth route changes,
- AirPlay route changes,
- call/Siri/audio-session interruptions,
- stream stall,
- timeout,
- app background/foreground transitions.

Playback should remain usable if metadata is unavailable.

Never stop audio merely because artwork or playlist metadata failed.

If metadata disappears:
- retain the last known metadata when appropriate,
- mark timing as uncertain internally,
- continue retrying at a reasonable cadence,
- avoid visually flashing empty states.

---

## 22. Battery and Resource Discipline

The app is intentionally simple and should not poll unnecessarily.

Requirements:
- use event-driven/system APIs where possible,
- avoid frequent timers when a single scheduled timer/deadline works,
- avoid duplicated network downloads,
- use the same incoming audio stream for playback and rolling-buffer capture,
- when rolling buffer = 0, avoid unnecessary file writes,
- when playback stops, close network activity promptly,
- when sleep timer completes, stop network/buffer work,
- bound artwork and metadata caches,
- clean temporary files.

The scheduled-start silent-audio strategy is the one intentional exception and should only be used under the explicit plugged-in policy above.

---

## 23. State Machine Expectations

Implement playback as an explicit state machine rather than scattered booleans.

Suggested states:
- idle
- connecting
- playingLive
- playingDelayed
- pausedLive
- pausedDelayed
- reconnecting
- fadingOut
- scheduledStandby
- stoppedBySleepTimer
- errorRecoverable

State transitions must account for:
- live jump,
- seeking,
- pause/resume preference,
- network loss,
- interruption begin/end,
- route changes,
- sleep timer,
- scheduled start,
- app lifecycle events.

Avoid multiple audio players fighting for the same stream.

---

## 24. UI Details and Native Feel

Use standard Apple interaction conventions.

### Controls
- target sizes appropriate for touch
- no tiny custom glyph buttons
- prefer SF Symbols where appropriate
- use native context/action sheets
- use native wheel pickers
- use native route picker
- use native haptic APIs

### Programme long press
Haptics should feel like system long-press/Haptic Touch:
- subtle onset,
- progressively stronger confirmation,
- strong completion at seek activation.

Do not build a distracting custom vibration pattern.

### Reconnecting state
Make it obvious without dominating the screen:
- show “Reconnecting…”
- show elapsed retry time or an equivalent one-minute progress indicator
- keep current/last metadata visible if available.

---

## 25. Non-Goals

Do not add:
- account/login
- social sharing
- favorites/library
- multiple radio stations
- podcasts/on-demand browsing
- donation prompts
- analytics/tracking SDKs
- location collection
- ads
- ratings prompts
- voice assistant features
- Shortcuts integration
- in-app volume slider
- track skip controls
- stream quality selector
- CarPlay sleep-timer controls
- VoiceOver-specific custom work
- public App Store onboarding/marketing flows

---

## 26. Entitlements / Capabilities to Configure

As applicable:
- Background Modes → Audio
- Audio session playback category
- Now Playing / remote command integration
- Notifications
- AirPlay route support
- ActivityKit / Live Activities for iOS 26 Dynamic Island if required
- CarPlay audio entitlement/capability if available to the signing account

The project must build even if CarPlay entitlement is unavailable:
- isolate CarPlay-specific code/configuration cleanly,
- document exactly what needs to be enabled in provisioning.

---

## 27. Persistence

Use a lightweight native persistence mechanism such as `UserDefaults` / `@AppStorage` for preferences.

Persist:
- auto-play preference
- resume behavior
- buffer duration
- minimalist mode
- appearance
- last-used sleep timer duration

Do not persist:
- stale active audio-buffer segments as durable user data
- delayed playback cursor across process termination
- active sleep timer across termination unless there is a deliberate, tested reason and behavior is clearly defined
- unnecessary listening history

Temporary buffer files should be recoverably disposable.

---

## 28. Testing Requirements

### Unit tests
At minimum:
- rolling-buffer retention trimming
- mapping playback timestamp → metadata item
- seek boundary clamping
- pause/resume policy
- 1-minute reconnect timeout
- sleep-timer decision logic
- next-start fallback logic
- 10-minute unplug grace logic
- 30% battery threshold transition
- scheduled-start no-op when already playing

### Manual device tests
Run on the actual target devices where possible.

#### iOS 16 / iPhone SE-class
- portrait
- landscape
- Dynamic Type sizes
- lock screen playback
- incoming call interruption
- Bluetooth disconnect → speaker
- AirPlay
- cellular-only playback
- 15-minute buffer
- seek to oldest retained point
- metadata follows delayed audio
- force quit / relaunch → live

#### iOS 26 / iPhone 17
All of the above plus:
- Dynamic Island compact
- Dynamic Island expanded
- Dynamic Island while paused
- Live button from Dynamic Island
- scheduled standby while charging
- unplug grace behavior
- notification fallback
- CarPlay if entitlement/device available

### Long-duration tests
At least:
- multi-hour continuous stream
- repeated network drops
- pause longer than retention window
- repeated seeks
- buffer file cleanup
- sleep timer through metadata failure
- Wi-Fi/cellular transitions

---

## 29. Acceptance Criteria

The build is not complete until all of the following are true:

1. Launches and streams KUSC high-quality audio.
2. Background/lock-screen audio works.
3. Calls/interruption recovery works.
4. Bluetooth/headphone disconnect routes to speaker.
5. One-minute reconnect policy works.
6. Rolling buffer works at every setting 0–15 minutes.
7. Old audio is trimmed and temporary storage remains bounded.
8. Resume Live / Resume Where Paused preference works.
9. Live button reliably returns to live edge.
10. Slider seeks only inside retained audio.
11. Metadata follows the audio actually being heard.
12. Full portrait UI matches the specified information hierarchy.
13. Swipe-right programme view replaces the main metadata/artwork area.
14. Programme view shows 5 previous + 10 upcoming pieces.
15. Long-press seek works only when target audio exists in buffer.
16. Minimalist mode removes informational clutter but keeps essential controls.
17. Landscape uses artwork-left / content-right layout.
18. Appearance setting supports System/Light/Dark.
19. Dynamic Type reflows correctly.
20. Lock Screen shows artwork and metadata with only Play/Pause + Live commands.
21. Headset previous/next commands are disabled.
22. iOS 26 Dynamic Island behavior matches the spec as far as the OS permits.
23. CarPlay exposes current item + programme list, with list informational only.
24. Sleep Timer picker works to 12 hours and remembers last value.
25. In-app pause while sleep timer runs prompts Keep/Pause/Cancel.
26. Sleep timer completes current movement only when <=10 minutes remain; otherwise fades.
27. Fade is linear and nominally 1 minute.
28. Missing movement timing falls back to next-start metadata, then to retry/fade logic.
29. Scheduled Start supports one time within next 24 hours.
30. Plugged-in standby and unplug grace logic follow the spec.
31. Battery-powered scheduled start uses notification; tapping starts playback immediately.
32. If already playing when schedule fires, nothing changes.
33. Force quit/system termination relaunches to live, not stale delayed playback.
34. Settings are at top-right gear.
35. Sleep Timer, Scheduled Start, Audio Output are separate items in ···.
36. App icon is red treble clef on white with no text.
37. No stream quality selector exists.
38. No unrelated radio-app features were added.

---

## 30. Work Execution Instructions

ChatGPT Work should perform the implementation in this order:

### Phase 1 — Verify external interfaces
- identify KUSC live high-quality stream URL,
- identify current KUSC metadata/playlist endpoints,
- inspect their fields, timestamps, update cadence, artwork URLs, programme/host information,
- verify whether movement-level end timing exists,
- verify iOS 26 Dynamic Island constraints,
- verify CarPlay entitlement requirements for the available signing setup.

Document findings before coupling code tightly to any endpoint.

### Phase 2 — Build playback core
- live playback
- background audio
- interruptions
- route changes
- reconnection state machine
- Now Playing/remote controls

### Phase 3 — Build rolling buffer
- segmented local capture
- strict retention
- seek mapping
- metadata timeline
- live-edge jump

### Phase 4 — Build standard/minimal UI
- portrait
- landscape
- programme swipe
- long-press seek
- settings
- ··· menu
- Dynamic Type
- appearance

### Phase 5 — Timers
- Sleep Timer
- Scheduled Start
- notification fallback
- silent-standby logic and power-state transitions

### Phase 6 — System surfaces
- Lock Screen
- Control Center
- Dynamic Island
- CarPlay

### Phase 7 — Test and harden
- actual-device testing
- temporary-file cleanup
- long-run streaming
- metadata failure
- lifecycle/termination
- battery/network transitions

Do not leave placeholder buttons, TODO-only screens, fake metadata, hard-coded demo playlist items, or mocked endpoints in the final build.

If a requested behavior is impossible because of a documented iOS platform restriction:
1. verify the restriction against current Apple documentation and actual target-device behavior,
2. implement the closest technically valid behavior,
3. document the exact limitation and affected requirement in the README,
4. do not silently remove the feature.

The final deliverable should be a complete Xcode project that can be opened, signed, built, and installed on the owner's devices.
