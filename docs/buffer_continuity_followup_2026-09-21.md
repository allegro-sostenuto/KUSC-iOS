# Buffered audio continuity and history display follow-up

## Device evidence

The owner tested build 9 on their iPhone 17 after the playlist-clock correction. Buffered audio now keeps playing, but a brief volume dip repeats approximately every 15 seconds. The dip occurs both at Live and after rewinding into downloaded audio. Zero-minute retention remains unaffected. The owner also reports that the left history label stops updating after scrubbing before the five-minute buffer has accumulated.

These observations narrow the investigation to the buffered transport and its scrub UI. They do not establish that the audible interval exactly matches each HLS segment or measure the dip's duration. The preceding captured stream used approximately 9.98458-second segments. The normal playback code has no periodic gain envelope; scheduled-start and sleep fades are separate operations.

## Changes under validation

The buffered path now uses one `AVSampleBufferAudioRenderer` and render synchronizer instead of separate local AAC `AVPlayerItem` handoffs. `AudioFileReadPacketData` reads compressed packets off the main queue. The source constructs Core Media buffers with explicit packet sizes and the original format and magic cookie, without per-file trim/reset attachments. Encoded durations place successive packets on one continuous timeline; a segment mapping retains the corresponding station time. The downloaded files remain the retention store. Explicit seek, true discontinuity and output recovery remain reset points. Zero-minute retention keeps its direct HLS player.

The UI fix separates an interaction's frozen coordinate range from the current history window. Only an active touch drag should own a preview. The native slider's tracking, end and cancellation events own that lifecycle; non-tracking value changes commit immediately. Non-touch adjustments and a final value delivered after editing ends must not leave a permanently frozen range or label.

Apple documents the renderer/synchronizer approach for [flexible audio buffering and AirPlay](https://developer.apple.com/documentation/avfoundation/implementing-flexible-enhanced-buffering-for-your-content). Output changes can automatically flush enqueued audio; the transport must observe that event and refill from the interrupted media position, preserving playback intent and gain. A normal segment arrival must not act as a flush, seek or gain reset.

The integration also invalidates obsolete media objects after an iOS media-services reset, including while paused. It reconnects immediately only when playback is requested and no interruption is active. Otherwise, manual Play or an allowed interruption resume creates a fresh transport. Scheduled-start recovery keeps its composed gain muted until readiness is established again.

Native regression tests generate a continuous AAC-LC stream, split its existing packets into files, and compare packet payloads, durations and timing with the whole file. Renderer tests exercise actual compressed playback across file boundaries, paused seeks, output recovery, discontinuities and obsolete reads. These fixtures are not a HE-AAC Bluetooth recording. Seven pure Swift scrub regressions and a growing-history native UI interaction cover the display fix. A focused hosted-audio CI job runs independently of the longer screenshot jobs so native media failures produce actionable logs sooner.

Build 11 compiled both unsigned device apps and passed the 103 portable tests, but native testing rejected the candidate: the AAC source raised a generic format error before enqueuing media, and a normalized slider adjustment retained its preview. Ordinary touch scrubs and subsequent history growth passed. Build 12's focused native test identified an empty control buffer after the valid AAC packets; the reader incorrectly rejected its zero sample count. The independent compressed-packet retiming test passed. Device-build success alone is not acceptance; final native and artifact verification remains pending.

Build 13 passed all six iPhone 17 native UI tests, including the growing-history adjustment, and ordinary compressed playback crossed three files with one decoder reset. The remaining native media failures exposed deep paused-seek backpressure and an unresolved whole-versus-split byte comparison. Seek preparation now limits decoder preroll to one second of complete packets, and payload validation compares packet-description byte ranges with the original ADTS payloads. The refill fixture explicitly activates its output session, as AppModel does in production, and the pause/resume fixture leaves sufficient retained audio after both starts. These corrections require another native run before delivery.

Build 14 identified why packet extraction and bounded seeks could not work with the passthrough buffers: they lacked usable sample-size metadata (`CMSampleBufferCopySampleBufferForRange` returned `-12735`, and packet-description extraction also failed). The longer pause/resume fixture still stalled with audio remaining. The source now reads explicit packets using Audio File Services and constructs fully described compressed buffers; strict original-packet equality and native resume validation remain required.

Build 15 passed all six compressed-source tests and all seven renderer tests, including exact equality between original ADTS payloads and whole/split file reads, continuous boundary playback, paused seeks and resume. The focused run's remaining failure occurred when the cached-refill integration fixture sought the final third of a four-second clip. Build 16 separated clip length from refill by using station-sized ten-second segments and adding a short-tail arrival regression.

## Exact-boundary seek diagnosis

Source `8b7732f3a01d293d75fd1643b88ee39342ee5dad` ran in [Actions run 35582385059](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/35582385059). Both Release device builds and all 105 portable tests passed under Xcode 26.6 (17F113), iPhoneOS SDK 26.5. The larger refill fixture passed, but the new short-tail renderer regression failed. Build 16 is not an accepted installation candidate.

The trace identified a real exact-boundary seek issue: the paused renderer reported sufficient decoded media while its last enqueued timestamp equalled the seek target and the successor's two batches remained pending. Preroll before the target filled the output queue. Clip length alone was not the cause. The follow-up marks seek-only preroll with Apple's [TrimDurationAtStart attachment](https://developer.apple.com/documentation/coremedia/kcmsamplebufferattachmentkey_trimdurationatstart), which permits decoding packets for context while discarding their output. Full buffers before the target produce no output; a buffer spanning the target discards only its earlier portion. Ordinary playback gets no trim. The original short engine fixture is restored, alongside the short-tail arrival regression. Native verification of this correction is pending.

Build 17 caught a compile-only API constant error: the legacy `CMAttachmentMode` is a C integer alias, so the attachment uses `kCMAttachmentMode_ShouldPropagate`. No native tests ran for that revision.

## Build 18 verification

Source `c914ecc9b9d41f849b6ad7fdfc32942eeb382a16` ran in [Actions run 35584810875](https://github.com/allegro-sostenuto/KUSC-iOS/actions/runs/35584810875). Both Release device builds and all 105 portable tests passed under Xcode 26.6 (17F113), iPhoneOS SDK 26.5. All seven source tests passed, including the trim semantics, but both exact-boundary paused-seek cases remained blocked with the same trace. Build 18 is not an accepted installation candidate.

Trim metadata alone did not make the paused native renderer accept the next buffer. The follow-up holds the bounded preroll until the first batch extending past the target is available, then concatenates those exact compressed packets into one initial sample buffer before applying the seek trim. All later ordinary arrivals retain their normal packaging. Source tests compare every packet and timing entry after concatenation, including shared-backing suffix buffers. The renderer test requires a confirmed paused cursor, then arrival and playback across the successor without a reset; it no longer expects all future media to enter a backpressured paused queue. Native verification of this correction is pending.

The downloaded artifact ZIPs match GitHub's SHA-256 digests. Both extracted IPAs independently pass device-binary validation; their embedded build number is 18, source records match the commit above, and the iPhone 17 app and Live Activity extension have matching versions. Local evidence is under `artifacts/ci-35584810875`.

| Package | IPA SHA-256 |
|---|---|
| KUSC-17-unsigned.ipa | `b68410abe2ab8f44c161c5b57f3c6290c5207679f9ed5b63132c81a83f5d4c91` |
| KUSC-SE-unsigned.ipa | `6284cf183bdf49041202b334c5879e0fad8cca481cc5f0a2e46792e3cba0c508` |

## Physical acceptance procedure

1. Set retention to five minutes, start a diagnostic capture and listen at Live for at least two minutes. Count any brief dips and save the report.
2. Rewind 30–60 seconds and listen for at least two more minutes. Ordinary file boundaries should not produce regular volume dips. Record any residual dip separately from a deliberate seek.
3. During the first five minutes of a fresh connection, scrub repeatedly to different positions, including Live. After every release, the left history label should keep growing as audio arrives. Repeat with an accessibility adjustment if used.
4. Pause with KUSC open for one minute. History should continue growing while the heard position stays paused. Resume, rewind and return to Live.
5. Repeat the listening check through the usual Bluetooth output. Confirm background/Lock Screen playback and the existing remote controls before treating the new transport as accepted.

Copy each diagnostic report before replacing the capture. A successful capture stays Recording until Stop Capture is tapped. Simulator tests establish implementation behavior and UI interaction; they do not establish audible Bluetooth continuity on the owner's phone.
