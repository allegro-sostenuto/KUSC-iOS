# Preserve HLS time across a sliding playlist refresh

## Confirmed failure

The owner's build 8 report from iPhone 17 / iOS 26.7, five-minute retention and Bluetooth A2DP identifies `hls.segmentClock seq=4` / `HLS lacks PROGRAM-DATE-TIME`. Before failure, playback is advancing and the player item is ready. The manifest repeatedly contains sequences 1–3 with resolved dates and no discontinuities. The failing refresh contains sequences 2–4 with all three dates missing, no discontinuities, and HTTP 200. The previously downloaded segment 3 ends at Unix time `1789924577.9537401`; incoming segment 4 lasts `9.98458` seconds but has no resolved start. The app rejects it before downloading its audio.

The parser previously started with an empty date anchor on every playlist reload. When segment 1 and its program-date tag slid out of the playlist, it discarded the already-known mapping for the overlapping segments 2 and 3. This explains the repeated reconnect/reset near the initial history limit and why the same acquisition failure can occur while paused. It is not a configured 14-second retention limit. The captured run actually reaches approximately 15.94 seconds before failure; that does not change the identified trigger.

## Correction and limits

Reload parsing retains only the preceding resolved playlist from the same ingestor connection. Dates can be recovered from verified overlap: the same media sequence, resolved segment URL, duration and compatible discontinuity state. Known dates extend through contiguous segments within a continuous region. Explicit fresh program dates remain authoritative. Missing overlap, changed segment identity, sequence reset/gap and unknown discontinuities do not authorize guessing a time. No receipt-time or wall-clock fallback is added, and a new connection starts with no inherited mapping.

The parser also preserves a program-date tag explicitly attached to the next segment when a discontinuity tag follows it before that segment URI. An inherited timestamp from a previous segment is still cleared at an unanchored discontinuity.

RFC 8216 describes checking that overlapping media sequences retain their URIs on reload ([§6.3.4](https://www.rfc-editor.org/rfc/rfc8216.html#section-6.3.4)) and extrapolating dates from program-date anchors and segment durations ([§6.3.3](https://www.rfc-editor.org/rfc/rfc8216.html#section-6.3.3)). This compatibility correction preserves an established mapping across the observed station refresh. Apple's [HLS authoring specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices/) requires program-date tags in live media playlists; the observed missing-tag refresh does not meet that authoring requirement.

## Verification and device retest

Regression fixtures cover the reported fractional durations and repeated rolling windows, date-tag/discontinuity ordering, and refusal to invent a clock for unproven continuity. CI and the rebuilt device IPA remain pending for this correction.

After installing the corrected build, repeat the diagnostic procedure from [the diagnostic build note](diagnostics_2026-09-21.md). First play at the live edge for at least two minutes with five-minute retention and confirm history grows past 14 seconds and one minute without reconnecting. Save the report, then start another capture, pause after audible playback has begun, and keep the app open/unlocked for at least one minute. Confirm history continues growing while paused. Resume, rewind and return to Live; report any audible interruptions separately. Copy each report before replacing it or force-quitting.

The identified timestamp failure can be corrected in code and covered with deterministic tests. Physical confirmation of uninterrupted output, Bluetooth behavior, background retention and longer playback still depends on the owner test; this change does not establish sample-accurate AAC joins.
