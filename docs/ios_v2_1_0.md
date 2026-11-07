# Philharmonic iOS 2.1.0

The completed “misc” recommendation on 7 November 2026 names six additions,
in this order: Yle Klassinen, Rete Toscana Classica, WFMT, Radio România Muzical,
RTP Ópera and Concertzender Oude Muziek. All six are appended to the existing
eleven-channel catalogue. Reserve candidates are not included.

Saved selection, custom order, display mode and per-channel quality choices
remain intact. The existing normalization appends newly recognized IDs. The
default remains KUSC. New entries use native live playback, station-specific
time zones and bundled official broadcaster marks. Android is deferred.

| Addition | Default | Other choices | Source evidence |
|---|---|---|---|
| Yle Klassinen | AAC 128 kbps HLS | AAC 64 / 256 | [Current Yle CDN master](https://yleradiolive5.akamaized.net/hls/live/20000872/yleklassinen/master.m3u8); [Yle station identity](https://yle.fi/aihe/a/20-34814) |
| Rete Toscana Classica | MP3 192 kbps | One verified source | [Broadcaster site and embedded Newradio player](https://www.retetoscanaclassica.it/) |
| WFMT | AAC 128 kbps | MP3 128 | [Official streaming formats and links](https://www.wfmt.com/how-to-listen/streaming-help/) |
| Radio România Muzical | AAC 96 kbps | One configured HTTPS source | [Current broadcaster player](https://www.romania-muzical.ro/browser-player.htm) |
| RTP Ópera | AAC about 160 kbps HLS | One verified source | [Official player](https://www.rtp.pt/play/direto/antena2opera) |
| Concertzender Oude Muziek | MP3 160 kbps | One verified source | [Official theme-channel stream list](https://www.concertzender.nl/ontvangst/list-of-streams/) |

Short ffprobe checks on 7 November decoded all nine added source choices.
Yle measured approximately 64.6/129.2/257.5 kbps, stereo AAC-LC at 48 kHz.
Its retired `2027676/in-YleKlassinen` address returned HTTP 400; the catalogue
uses a specific current rendition rather than letting the master select 256.
RTC decoded 192 kbps stereo MP3 at 44.1 kHz. WFMT's published 128 kbps AAC
service measured about 130.4 including encoded framing; its MP3 was 128 at
48 kHz. The published `stream.wfmt.com` MP3 alias failed Apple's TLS hostname
validation, so its MP3 choice uses the matching `wfmt.streamguys1.com` service
hostname. Verified TLS and decoding passed for that address locally.
România Muzical's current HTTPS browser feed decoded about 96 kbps
stereo AAC-LC at 44.1 kHz. Historical HTTP MP3/AAC links are not configured,
and no transport-security exceptions are introduced for optional higher rates.

RTP's only master rendition advertises about 169 kbps transport bandwidth and
decoded approximately 163–165 kbps AAC-LC at 44.1 kHz. Its displayed 160 kbps
is an approximate encoding tier inferred from those measurements, not the
`80a` filename. The app uses the live playlist without the player's DVR query.
Concertzender's official theme-channel tier is 160 kbps MP3; the decoded sample
was about 159.6 at 44.1 kHz despite a stale `icy-br: 128` header. The main
Concertzender and its Barok channel are not substituted for Oude Muziek.

These are source encoding rates, not real-time network-throughput measurements
or subjective sound-quality scores. Defaults remain near KUSC's rate where
verified alternatives allow it. RTC, RTP and Oude Muziek retain their higher
available rates rather than introducing a relay or local transcoding.

The six new entries initially provide station/live information. No new work,
artwork or programme-feed adapter is claimed; their Program navigation follows
the existing metadata-capability rule. A broadcaster website publishing a
schedule does not mean that schedule has been integrated into this app.

## Bundled marks

Yle uses the [official broadcaster mark](https://img.img-cdn.yle.fi/w_180,h_180/f_png/yle-logo-c-svg/1513081794)
referenced by its Klassinen article. RTC uses its official square site icon;
WFMT uses its official white PNG wordmark with template rendering for light and
dark backgrounds. România Muzical uses the broadcaster's station icon. RTP
uses its player-provided Ópera image. Oude Muziek uses its own official theme
symbol. The two SVG marks were rasterized, and only the transparent outer
canvas of the Oude Muziek symbol was trimmed. Shapes and proportions are kept.
Exact origin URLs and processing are in `artifacts/ios-2.1.0/logo-provenance.json`.

## Validation

Portable structural validation parsed 76 Swift files with no syntax errors;
it does not replace Xcode compilation. Both Release device builds passed in
[run 70](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42351048477),
source `35795645bfc4735f6f5c0ea60d8f3e8d24c78124`, with Xcode 26.6 / iOS SDK 26.5.
The 24 focused native checks passed except the MP3 alias's TLS failure above;
all other 30 source choices advanced, and migration and switching checks passed.
Both focused quality/picker UI cases passed. A corrected build and native source
recheck are pending. The historical
swipe/layout suites were deliberately skipped. Simulator checks use iPhone 17 /
iOS 26.5; iOS 16 is a compilation target without an iOS 16 runtime check.
No physical installation or sustained Shanghai-network reliability is implied.

## Verified packages

The superseded IPAs are 2.1.0 (build 70). ZIP integrity, CI checksum, source record, app
and extension versions, bundle identifiers, matching App Groups and expected
widget extensions were checked locally. CI also validated arm64 device code,
deployment targets and ad-hoc widget capabilities. AltStore must sign the IPAs.

| Package | SHA-256 |
|---|---|
| Philharmonic-17 | `e6a92e8c9323d91874171c57ddf1a0ceec79acff07c8b606cc2b07acbd076330` |
| Philharmonic-SE | `6220843169473ae00ce711b3dda74e694b967237a52e4d0fe58abb60939fef49` |

Local packages and `verified-builds.json` are in `artifacts/ci-42351048477/`.
