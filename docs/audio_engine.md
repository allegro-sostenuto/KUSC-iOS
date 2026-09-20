# Audio acquisition, buffering and clock mapping

The selected source is KUSC's 96 kbit/s HE-AAC HLS stream, discovered through its official web player. Both modes receive the same configured `.m3u8` endpoint. The live media playlist observed on 19 September 2026 contained unencrypted `.aac` segments, `EXT-X-MEDIA-SEQUENCE`, `EXT-X-TARGETDURATION:10` and `EXT-X-PROGRAM-DATE-TIME`. Observed segments lasted roughly 4–10 seconds.

## Zero-minute retention

`AVPlayer` loads the remote HLS stream directly. The app creates no audio-buffer directory or capture files in this mode. Apple's player can maintain its own minimal streaming cache. Pausing sets `canUseNetworkResourcesForLiveStreamingWhilePaused = false`; resuming replaces the item to join live instead of deliberately exposing old playback history. `AVPlayerItem.currentDate()` supplies the timestamp currently being heard when the HLS clock is available.

## One to fifteen minutes

`HLSIngestor` resolves the highest-bandwidth variant, retains the resolved media-session URL, polls at half the target duration (capped at five seconds), and downloads each new media sequence once. These downloaded AAC files serve both playback and history. There is no second remote player receiving another copy of the audio. Startup fetches only the newest two segments; history accumulates while the app runs.

Each segment is checked for complete ADTS frames. The HLS program date plus preceding `EXTINF` durations determines its absolute start. Playback uses a four-item `AVQueuePlayer` queue of local AAC files; the current item's media time plus its segment start determines the heard timestamp. That timestamp drives the separate metadata timeline. HTTP errors, malformed/unsupported manifests, non-AAC segments, backward clock resets and missing program dates fail visibly through the coordinator's reconnect policy. The app does not substitute a guessed receipt timestamp for a missing HLS clock in buffered mode.

The Live action starts the newest complete segment. Its endpoint may be about 4–10 seconds later, so a live listener can legitimately be several seconds behind the right edge. This avoids seeking into an incomplete download. HLS is not zero-latency broadcasting. Station-supplied program dates synchronize the transport; any discrepancy between the station's playlist metadata and its actual broadcast remains upstream timing uncertainty.

## Retention and resource limits

- The valid cursor begins at the later of the first available segment and `newest acquired audio end - selected minutes`.
- A segment crossing that cutoff remains on disk until its remaining suffix expires, but seeking to its expired prefix is forbidden.
- If playing audio ages out, playback jumps to the oldest valid cursor before continuing. Paused playback cannot resume expired audio: resume clamps to the oldest retained point.
- Whole expired files are deleted on each segment arrival or retention change. The store also has hard limits of 512 segments and 64 MiB. At the observed rate, fifteen minutes is approximately 10.8 MB of compressed audio, plus at most one straddling segment and ordinary player/network buffers.
- Responses have hard in-memory limits: 1 MiB for a playlist and 2 MiB for an AAC segment. File protection permits reads after first unlock while the screen is locked. Files are excluded from backup.
- Pausing with retention enabled leaves the single ingestor running while iOS permits execution. This does not create a background-execution guarantee for a paused app. A suspended connection is revalidated/reconnected on resume.
- Stop cancels ingestion, invalidates stale callbacks, releases player items and deletes the run directory. Initialization removes crash leftovers. No delayed cursor survives process termination.
- Switching between zero and positive retention closes the old acquisition path and joins live through the new path. Changing between positive durations preserves the connection and trims immediately.

## Validation status

Parser tests cover split AAC headers/frames, HE-AAC core-rate duration, ICY framing, HLS master selection, propagated program dates, malformed playlists and unsupported formats. Retention, gap-aware seeking and pause policies have separate pure Swift tests. Official endpoint responses and their HLS structure were inspected during implementation.

A fresh real-stream segment fetched at 2026-09-19 17:11 UTC contained 122,831 bytes: 1,357 bytes of ID3/header material followed by 215 complete ADTS frames, with no trailing partial frame. ADTS duration was 9.984580498866 seconds; HLS `EXTINF` was 9.98458 seconds, a difference below one microsecond. The 22,050 Hz core rate and decoded 44,100 Hz stereo HE-AAC reported by `ffprobe` confirm correct SBR duration handling. A separate fresh-request timing measurement observed 15.68 seconds to the HLS master through redirects and 7.55 seconds to its media playlist. These are environment/network observations, not a station latency guarantee. The engine permits 45 seconds for initial playback and 12 seconds for a stall after playback has begun; the coordinator applies its separate one-minute reconnect deadline.

An iOS SDK and physical audio outputs were not available in the build environment. Continuous transitions between queued ADTS segments, AirPlay behavior, exact seek precision and multi-hour playback therefore require the device tests in `manual_test_plan.md`. Apple documents item queues but does not promise sample-accurate gapless joins for arbitrary standalone ADTS assets. The source implements real downloads and playback; seamless segment transitions are not claimed as hardware-verified. The implementation intentionally rejects encryption, byte-range segments and fragmented MP4 if the station changes its current format.

## Apple references

- [AVQueuePlayer](https://developer.apple.com/documentation/avfoundation/avqueueplayer)
- [AVPlayerItem.currentDate](https://developer.apple.com/documentation/avfoundation/avplayeritem/currentdate())
- [Network loading while a live item is paused](https://developer.apple.com/documentation/avfoundation/avplayeritem/canusenetworkresourcesforlivestreamingwhilepaused)
- [HLS authoring specification for Apple devices](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)
