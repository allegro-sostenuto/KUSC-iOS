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
48 kHz. România Muzical's current HTTPS browser feed decoded about 96 kbps
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
it does not replace Xcode compilation. Native playback, migration, picker and
package evidence will be recorded after the focused CI run. No physical phone
installation or sustained Shanghai-network reliability is implied.
