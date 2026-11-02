# iPhone v2 station sources

Checked 2 November 2026. `Shared/Core/StationCatalog.swift` is the implemented iPhone catalogue; `Tests/Fixtures/station-catalog.json` is the portable parity contract for a later Android update. Android has not been expanded by this work. There are eleven approved entries, including the existing KUSC service. The two France Musique channels and three Orpheus channels have distinct IDs and labels even though each family shares a logo.

The following short network probes used FFmpeg `ffprobe` against broadcaster/CDN URLs. Bitrates are the probe's stream estimates, not listening-quality scores or a long-term measurement. Every successful probe found two audio channels. These Windows network/decoder probes do **not** establish native AVPlayer playback, audible station identity, physical iPhone operation, or delivery reliability in Shanghai. Native/device acceptance is recorded separately.

All eleven configured sources subsequently passed native AVPlayer readiness and
decoder-clock advancement on the disposable iPhone simulator in run 61. See the
[validation record](ios_v2_validation_2026-11-02.md) for exact scope, the observed
single-attempt Orpheus startup failure in an earlier run, and device limitations.

| Entry | Configured source | Probe result | Metadata implemented |
|---|---|---|---|
| KUSC | [Broadcaster AAC HLS redirect](https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCAAC96.m3u8) | AAC, 44.1 kHz, about 98 kbps; existing advertised 96 kbps service | Existing KUSC now/combined feeds, work, performers, artwork and programme data |
| Radio Swiss Classic | [Official 192 kbps AAC service](https://stream.srg-ssr.ch/srgssr/rsc_de/aac/192) | AAC, 48 kHz, about 192.4 kbps | Station/live information only |
| Sveriges Radio P2 | [Broadcaster 320 kbps AAC service](https://live1.sr.se/p2-aac-320) | AAC, 48 kHz, about 319.7 kbps | Official P2 Musik current/previous/next track feed; supplied composer, performer and UTC boundaries |
| France Musique · Classique Easy | [Broadcaster high-quality AAC](https://icecast.radiofrance.fr/francemusiqueeasyclassique-hifi.aac) | AAC, 48 kHz, about 194.4 kbps | Station/live information only |
| France Musique · La Baroque | [Broadcaster high-quality AAC](https://icecast.radiofrance.fr/francemusiquebaroque-hifi.aac) | AAC, 48 kHz, about 196.4 kbps | Station/live information only |
| WDR 3 | [Official 256 kbps MP3](https://wdr-wdr3-live.icecastssl.wdr.de/wdr/wdr3/live/mp3/256/stream.mp3) | MP3, 48 kHz, 256 kbps | Station/live information only |
| Polskie Radio Chopin | [Official player HLS source](https://stream85.polskieradio.pl/live/rytm.sdp/playlist.m3u8) | AAC, 48 kHz, about 322.5 kbps; master advertises roughly 320 kbps including transport overhead | Station/live information only |
| Orpheus · Large-Scale Works | [Official channel 8 MP3](https://radio.orpheus.ru:8000/Chan_8_192.mp3) | MP3, 44.1 kHz, 192 kbps | Station/live information only |
| Orpheus · Russian Classical Music | [Official channel 17 MP3](https://radio.orpheus.ru:8000/Chan_17_192.mp3) | MP3, 44.1 kHz, 192 kbps | Station/live information only |
| Orpheus · Camerata | [Official channel 76 MP3](https://radio.orpheus.ru:8000/Chan_76_256.mp3) | MP3, 44.1 kHz, 256 kbps | Station/live information only |
| HR Klasik | [Official player mount MP3 redirect](https://playerservices.streamtheworld.com/api/livestream-redirect/HR_CLASSICS.mp3) | MP3, 48 kHz, 128 kbps; also advertised by official mount configuration and `icy-br: 128` | Official recent-track feed with work, composer and performers; station-identification records excluded |

P2's [official quality guidance](https://vanliga-fragor-svar.sverigesradio.se/guide/ljudkvalitet-pa-sveriges-radios-digitala-plattformar) publishes AAC 320 kbps and a separate FLAC option. The tested FLAC evidence in the handoff was Ogg; that container has not been established as playable through the app's native iOS path, so this catalogue uses AAC. The API's `channels/163` response currently identifies the music service as channel 2562, **P2 Musik**. The picker/header subtitle names that service explicitly. Its older API `2562-hi.mp3` source also decoded, but was MP3 at approximately 162 kbps, so it is not the configured source. The published direct-link list returned HTTP 403 in this check; the 320 kbps URL itself was validated on the broadcaster's `sr.se` server.

HR Klasik's [official player](https://radio.hrt.hr/stream/25) configures the Triton/StreamTheWorld mount `HR_CLASSICS`. The [public provisioning response](https://playerservices.streamtheworld.com/api/livestream?version=1.8&mount=HR_CLASSICS&lang=en) advertises MP3 128 kbps/48 kHz. The MP3 redirect returned HTTP 200 with `icy-name: HR_CLASSICS`, then a short probe of its resolved HTTPS target confirmed the format. A speculative `.aac` suffix returned 404 and is not used. The app saves the stable broadcaster redirect, not the transient CDN destination.

Radio Chopin's current homepage JavaScript explicitly configures the `rytm.sdp` HLS URL above. That historical pathname is not inferred to be a different station, but the decoded source was not audibly identified during these probes. Orpheus's current player configuration publishes only the selected 192 kbps source for channels 8 and 17, and publishes 64/128/256 kbps MP3 choices for channel 76. The catalogue chooses its verified 256 kbps MP3 source. The main Orpheus FM stream is not added.

Other source attribution: [Swiss official reception options](https://www.radioswissclassic.ch/en/reception/internet), [Radio France's station offering](https://www.radiofrance.com/presentation-de-nos-antennes), [France Musique](https://www.radiofrance.fr/francemusique), [WDR official stream list](https://www1.wdr.de/unternehmen/der-wdr/empfang-technik/webradio-100.html), [Radio Chopin official player](https://chopin.polskieradio.pl/), and official Orpheus player entries [8](https://radio.orpheus.ru/player/8), [17](https://radio.orpheus.ru/player/17), [76](https://radio.orpheus.ru/player/76).

## Metadata boundaries

KUSC remains behind its existing station-specific adapter. Its Los Angeles day queries never use the phone's timezone. The other descriptors retain their own IANA timezone, including daylight-saving rules. SR's track feed publishes explicit UTC timestamps. HRT's feed uses seconds in the enclosing `timestamp` and milliseconds in `cue_time_start`; its inspected `track_album_name` contains composer text, while `track_artist_name` contains performers. `HRVATSKI RADIO` / `HR KLASIK` station-identification entries are not treated as musical works. Neither feed implies a full programme schedule or album artwork capability.

Real reduced/current responses are saved in `Tests/Fixtures/sr-p2-now.json` and `Tests/Fixtures/hr-klasik-now.xml`. Sources are [SR current playlist](https://api.sr.se/api/v2/playlists/rightnow?channelid=2562&format=json) and [HRT recent tracks](https://np.tritondigital.com/public/nowplaying?mountName=HR_CLASSICS&numberToFetch=10&eventType=track). Fixtures are test data, never a fallback playlist. The other stations use an honest channel/live fallback. Unusable Orpheus status titles and opaque catalogue identifiers are not presented as works. Metadata failure must leave healthy audio running.

## Bundled logos

Official broadcaster assets are bundled in `Assets.xcassets/station-*.imageset`, so station browsing never depends on a logo network request. Ratios are preserved by the picker. Three monochrome broadcaster marks use the asset's template rendering intent for contrast in light and pure-black appearance; their paths/shapes remain the official marks. Text remains readable if an asset cannot load. Family channels intentionally share their broadcaster mark and retain separate channel labels.

| Asset | Official origin |
|---|---|
| `station-kusc` | [Classical California mark](https://images.ctfassets.net/8usdt07j8s00/7zczuCfhgulOxuS27VX7B/1e93a65d3185225f39932056512acd41/CC_Logo_Mark_1024.webp), referenced by the [official homepage](https://www.classicalcalifornia.org); converted losslessly from WebP to PNG |
| `station-swiss` | [Radio Swiss Classic logo](https://www.radioswissclassic.ch/_nuxt/img/rsc-logo-50-x2.63a9918.png), referenced by its reception page |
| `station-p2` | [P2 image](https://static-cdn.sr.se/images/2562/19ccfced-f682-4cd4-a94f-60400ac8891e.jpg?preset=api-default-square), returned by the broadcaster channel API |
| `station-france-musique` | [France Musique square logo](https://www.radiofrance.fr/_app/immutable/assets/francemusique-seosquare.2aIK1Bsn.png), referenced by the official homepage |
| `station-wdr3` | [WDR 3 square logo](https://www1.wdr.de/radio/wdr3/wdr3logo100~_v-square-m.jpg), referenced by the official homepage |
| `station-chopin` | [Radio Chopin footer SVG](https://chopin.polskieradio.pl/footer/PRChopin.svg), referenced by the official homepage |
| `station-orpheus` | Inline broadcaster logo SVG from the [official player](https://radio.orpheus.ru/player/76); its CSS `currentColor` resolves through template rendering |
| `station-hr-klasik` | [Hrvatski radio broadcaster mark](https://radio.hrt.hr/static/logos/logo.png), used by the official HR Klasik player |

## Selection and migration

The separate `stations.v2` preference stores selected ID, ordered IDs and grid/list mode. Upgrading an older install defaults to KUSC without touching appearance, autoplay, timer settings or scheduled-start storage. Normalization drops obsolete IDs and duplicates, preserves known user order, then appends new catalogue entries. A malformed field falls back independently; malformed selection falls back to KUSC.

Next and Previous wrap cyclically through that saved order. Accessible Move Earlier/Move Later stop at the ends. Reordering never changes selection or playback intent. The station-order tests cover persistence, migration, cyclic transport behavior, parity and timezone/DST boundaries. All streams use the native live transport; no server, recorder, rewind history or delayed-session control is introduced.
