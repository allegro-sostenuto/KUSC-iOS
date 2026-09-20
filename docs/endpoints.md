# KUSC station interfaces

Verified by public HTTP requests on **19 September 2026**, approximately 16:59–17:05 UTC. These are live interfaces, not versioned promises from the station. All configurable URLs are in `Shared/StationConfiguration.swift`.

## Provenance and selected audio

The station's official [listening instructions](https://www.classicalcalifornia.org/articles/how-to-listen-to-classical-california) link the [KUSCAAC96 PLS playlist](https://playerservices.streamtheworld.com/pls/KUSCAAC96.pls). That playlist returned HTTP 200 and three `*.live.streamtheworld.com` HTTPS stream servers. StreamTheWorld/Triton is the station's designated audio infrastructure; it is not an unrelated radio directory or metadata proxy. The app uses no analytics or tracking SDK from the website.

| Purpose | URL / observed result |
| --- | --- |
| Selected high-quality audio | `https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.m3u8` |
| HLS master | HTTP 200, `application/vnd.apple.mpegurl`, `BANDWIDTH=96000`, `CODECS="mp4a.40.5"` (96 kb/s HE-AAC) |
| HLS media | `.aac` segments of approximately 4–10 seconds; `#EXT-X-PROGRAM-DATE-TIME`, `#EXT-X-MEDIA-SEQUENCE`, `#EXTINF`; target duration 10 seconds |
| Continuous alternative | `https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.aac`: HTTP 200, `audio/aacp`, `icy-br: 96`, ADTS framing |
| Station's published server list | `https://playerservices.streamtheworld.com/pls/KUSCAAC96.pls` |

96 kb/s AAC is the highest AAC option in the station's published direct-listening links. Bitrates across different codecs are not a direct measure of fidelity. The selected HLS stream is the same high-quality AAC programme as the continuous endpoint; no quality selector is provided. A future station change may require updating configuration. No fixed CDN hostname or session identifier is embedded in the app; the redirect creates the current HLS session.

The observed HLS media playlist included:

```m3u8
#EXT-X-TARGETDURATION:10
#EXT-X-PROGRAM-DATE-TIME:2026-09-19T16:59:18.000Z
#EXTINF:9.98458,Claude Debussy - Prelude to the Afternoon of a Faun L.86
1.aac
```

HLS titles can instead contain station automation labels such as `VT Classical California`. They are not used to fabricate a composer, movement, performer or programme. Program date time maps the audio segments to the independent station metadata timeline. Sample framing and network success were verified; audible quality, interruption recovery, drift and multi-hour playback still require an actual iPhone test.

## Metadata and programme feeds

Endpoint formulas were read from the JavaScript served by the official website, specifically the public [player bundle](https://www.classicalcalifornia.org/_next/static/chunks/5019-4aed77a18202bbff.js). This bundle's filename can change on deployment. The [official playlist](https://www.classicalcalifornia.org/playlist) uses these station-hosted JSON services:

| Interface | Verified URL | Observed format |
| --- | --- | --- |
| Current item with artwork | `https://schedule.kusc.org/v3/songs/KUSC/now?includeImage=true` | One object; `start.dateTime`, `end.dateTime`, `extraInfo` |
| Programme schedule | `https://schedule.kusc.org/v3/programs/KUSC/day?env=master` | Array with programme `start`, `end`, `show`, `host` |
| Programme + piece history | `https://schedule.kusc.org/v3/combined/KUSC?combinedFormat=true&reversed=true&env=master` | Programme blocks, each with a `songs` array |
| A specific station day | `https://schedule.kusc.org/v3/combined/KUSC?date=2026-09-18&combinedFormat=true&reversed=true&env=master` | Same structure; date is `yyyy-MM-dd` in America/Los_Angeles |

All four calls returned HTTP 200 and decodable JSON. The current day sample contained 6 programme blocks and 63 past/current songs; the previous day contained 7 blocks and 139 songs. The timestamp strings contain UTC offsets and are parsed as instants. Calendar dates use the named Pacific time zone, including daylight saving, rather than a hard-coded UTC offset.

`extraInfo` supplied the following fields:

- `title`: broadcast work title; preserves any movement text already included by the station.
- `Composer`, with `artist` fallback: composer.
- `Soloist`, `Performer`, `Orchestra`, `Conductor`: available performers, joined without duplicate values.
- `AirStarttime`, `AirStoptime`: explicit broadcast-item timestamps, consistent with the enclosing `start` and `end` in the observed responses.
- `MMID` / `MM_ID`, `UniversalIdentifier`: recording identity. A start timestamp is added to distinguish repeat broadcasts.
- `ALBUM`, `Record_Company`, `Spine_Number`: recording details, presently not shown as additional UI.
- `image`: artwork, present in the current-item response when requested.

The combined feed's enclosing block supplies programme/host identity. During gaps between pieces, the separate programme intervals remain available through `MetadataService.programme(at:)`. `nextProgrammeStart(after:)` provides the programme-transition fallback for sleep decisions.

## Actual information limits

**Future pieces were not published in the verified response.** All later programme blocks had empty `songs` arrays. The app can display up to 10 later pieces relative to delayed audio when those pieces are present in the feed; it cannot promise 10 unbroadcast pieces at live time. Empty future lists mean the station has not supplied that information. Neither dummy rows nor a forecast playlist are generated.

**A separate movement field or independently validated movement-boundary feed was not observed.** The adapter retains the station's exact piece title and treats a valid, explicit `AirStoptime`/`end` as the reliable endpoint of that broadcast item. This permits the sleep timer to finish that item. It does not establish that every multi-movement work is split into separate movements. No endpoint is inferred from a title, album duration or the following track. Invalid, reversed or implausibly long endpoints are discarded.

**Artwork arrives inline.** The verified `image` value declared `data:image/png;base64,` but its decoded signature was JPEG. The adapter checks the byte signature, writes the correct extension into the app's cache, and keeps at most 16 files, each at most 1 MiB, with a 24-hour maximum age. The directory is excluded from backup. HTTPS image URLs explicitly supplied by the station are also supported. The history sample did not include artwork, so art is available for current pieces observed during this process and retained pieces with cached artwork; missing art uses the app's neutral station image.

## Refresh and failure behavior

- Current-item metadata is requested at the application's 30-second playback polling cadence.
- Today's combined feed is refreshed no more often than once a minute. Adjacent station days are cached for 15 minutes, including data needed across midnight.
- Polling is owned by playback and stops with the owner; the adapter creates no perpetual background timer.
- Requests time out after 15 seconds. Individual malformed song rows are skipped. Entire malformed payloads and HTTP failures become recoverable metadata errors.
- A partial failure preserves available cached history and programme data. Metadata failure never controls or stops the audio connection.
- Exposed items are bounded to 224 past/current and 32 future entries; the core timeline has its own 256-item limit. Artwork is cached separately and modestly.
- There is no claim that the station publishes updates every 30 seconds. That is the app's chosen request cadence; server event latency is variable and was not statistically measured.

Reduced official response fixtures are in `docs/fixtures/`. They are test evidence, not a fallback playlist and are never loaded by the application. The large inline artwork field was removed from the fixture. Public metadata HTTP verification is distinct from device acceptance testing.

## Recheck independently

```sh
curl -L --fail 'https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.m3u8'
curl -L --fail 'https://schedule.kusc.org/v3/songs/KUSC/now?includeImage=true'
curl -L --fail 'https://schedule.kusc.org/v3/combined/KUSC?combinedFormat=true&reversed=true&env=master'
```

Follow the HTTPS variant URL returned in the HLS master to inspect the media playlist. Do not save that short-lived session URL as the configured endpoint.
