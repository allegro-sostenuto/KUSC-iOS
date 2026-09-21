# Buffered audio continuity and history display follow-up

## Device evidence

The owner tested build 9 on their iPhone 17 after the playlist-clock correction. Buffered audio now keeps playing, but a brief volume dip repeats approximately every 15 seconds. The dip occurs both at Live and after rewinding into downloaded audio. Zero-minute retention remains unaffected. The owner also reports that the left history label stops updating after scrubbing before the five-minute buffer has accumulated.

These observations narrow the investigation to the buffered transport and its scrub UI. They do not establish that the audible interval exactly matches each HLS segment or measure the dip's duration. The preceding captured stream used approximately 9.98458-second segments. The normal playback code has no periodic gain envelope; scheduled-start and sleep fades are separate operations.

## Changes under validation

The buffered path now uses one `AVSampleBufferAudioRenderer` and render synchronizer instead of separate local AAC `AVPlayerItem` handoffs. `AVAssetReader` reads compressed packets off the main queue, preserving format and packet data while removing per-file trim/reset attachments. Encoded durations place successive packets on one continuous timeline; a segment mapping retains the corresponding station time. The downloaded files remain the retention store. Explicit seek, true discontinuity and output recovery remain reset points. Zero-minute retention keeps its direct HLS player.

The UI fix separates an interaction's frozen coordinate range from the current history window. Only an active touch drag should own a preview. Non-touch adjustments and a final value delivered after editing ends must not leave a permanently frozen range or label.

Apple documents the renderer/synchronizer approach for [flexible audio buffering and AirPlay](https://developer.apple.com/documentation/avfoundation/implementing-flexible-enhanced-buffering-for-your-content). Output changes can automatically flush enqueued audio; the transport must observe that event and refill from the interrupted media position, preserving playback intent and gain. A normal segment arrival must not act as a flush, seek or gain reset.

The integration also invalidates obsolete media objects after an iOS media-services reset, including while paused. It reconnects immediately only when playback is requested and no interruption is active. Otherwise, manual Play or an allowed interruption resume creates a fresh transport. Scheduled-start recovery keeps its composed gain muted until readiness is established again.

Native regression tests generate a continuous AAC-LC stream, split its existing packets into files, and compare packet payloads, durations and timing with the whole file. Renderer tests exercise actual compressed playback across file boundaries, paused seeks, output recovery, discontinuities and obsolete reads. These fixtures are not a HE-AAC Bluetooth recording. Five pure Swift scrub regressions and a growing-history native UI interaction cover the display fix. Xcode execution results will be recorded after CI completes.

## Physical acceptance procedure

1. Set retention to five minutes, start a diagnostic capture and listen at Live for at least two minutes. Count any brief dips and save the report.
2. Rewind 30–60 seconds and listen for at least two more minutes. Ordinary file boundaries should not produce regular volume dips. Record any residual dip separately from a deliberate seek.
3. During the first five minutes of a fresh connection, scrub repeatedly to different positions, including Live. After every release, the left history label should keep growing as audio arrives. Repeat with an accessibility adjustment if used.
4. Pause with KUSC open for one minute. History should continue growing while the heard position stays paused. Resume, rewind and return to Live.
5. Repeat the listening check through the usual Bluetooth output. Confirm background/Lock Screen playback and the existing remote controls before treating the new transport as accepted.

Copy each diagnostic report before replacing the capture. A successful capture stays Recording until Stop Capture is tapped. Simulator tests establish implementation behavior and UI interaction; they do not establish audible Bluetooth continuity on the owner's phone.
