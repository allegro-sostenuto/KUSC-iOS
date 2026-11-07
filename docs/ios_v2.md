# Philharmonic iOS 2.0.0

The [2.3.0 UI update](ios_v2_3_0.md) completes the saved Settings, artwork,
control-shape and header-animation backlog, easiest items first.

The [2.2.1 correction](ios_v2_2_1.md) restores widgets and Live Activities to
their pre-flag presentation while keeping flags beside station names in the app.

The [2.2.0 update](ios_v2_2_0.md) adds small national flag images beside station
names across the app-controlled interface, widgets and Live Activities.

The [2.1.0 addition](ios_v2_1_0.md) appends six channels recommended by “misc”,
bringing the catalogue to seventeen while preserving saved choices and order.

The [2.0.1 patch](ios_v2_0_1.md) adds per-channel bitrate dropdowns under Settings → Quality
and defaults to roughly KUSC's bitrate where a suitable source exists.

The iPhone player offers eleven approved live channels. Android's multi-station
update remains deferred. Installation identifiers, App Groups, widget kinds,
legacy widget links, appearance preferences and existing timer storage remain
compatible with 1.1.2.

Tap the selected channel at the top left to open Stations, then use Back to
player to return. Grid displays two channels per row; List displays one. Portrait
scrolls vertically, and landscape scrolls horizontally through rows in either
mode. Both presentations use the same persisted order and selected channel.
Drag a card to reorder it, or choose Reorder for visible Earlier/Later buttons.
VoiceOver also exposes Move earlier and Move later actions. Reordering never
changes the selected channel or starts playback.

Previous station and Next station follow the saved order and wrap cyclically at
its ends. Supported system track controls use the same operations. Seeking,
scrubbing and delayed listening remain unavailable. Pause silences playback;
Play recreates the native live item. Switching station preserves requested
playback: a paused player stays paused and a playing player joins the new stream.

The player retains Program's portrait-only panel reveal and smooth rolling
heading. Landscape retains large artwork on the left, with details, listening
status and transport together on the right. The separate station picker supports
both orientations. Dark backgrounds, cards and controls remain pure black, with
borders separating them.

## Catalogue and metadata

See [source verification](station_sources_v2.md) for each official stream, codec,
measured versus advertised quality and logo provenance. The platform parity
fixture is `Tests/Fixtures/station-catalog.json`; it does not authorize or
implement Android changes.

KUSC retains its station-specific current-work, artwork, playlist and programme
adapter. P2 Musik uses Sveriges Radio's channel 2562 current/previous/next feed,
with explicit UTC boundaries. HR Klasik uses its official Triton recent-track
feed; station-identification entries do not appear as musical works. The
remaining channels initially display station information and an honest absence
of work/programme information. They have no invented artwork, composer,
programme, duration or future pieces. Metadata failures leave healthy audio
running. Programme labels use the selected station's time zone; KUSC broadcast
day requests continue to use Los Angeles, including DST and adjacent days.

Each selection invalidates connection, metadata, manual-refresh, artwork and
retry work, stops the old player synchronously, and begins an independent
station session. Late work cannot publish into the replacement session.
Continuous AAC/MP3 and other stations' HLS use native AVPlayer directly. KUSC
alone retains the existing marked startup-promo preparation. No relay, recorder,
proxy or server is introduced.

## Migration and scheduled starts

New station preferences use stable IDs, independent of playback intent. An
upgrade defaults to KUSC. Saved order deduplicates known IDs, drops unknown IDs,
and appends newly introduced channels. Invalid selection falls back to KUSC;
unrelated appearance, autoplay and timer settings are preserved.

A scheduled start captures the selected station when saved. Browsing later
does not retarget it, including during silent preparation; the saved station is
selected at takeover. Once scheduled playback has begun, explicit station
switches remain user intent. Legacy requests missing a station ID migrate to
KUSC. The full one-minute audible fade, expiry, Delete, Pause, output/power
rules and battery protection remain in effect. The scheduling sheet names the
saved station.

Now Playing, widgets and Live Activities publish the selected station identity.
Legacy snapshots decode as KUSC. A stale station-specific widget/activity
command is ignored and refreshes the displayed state; existing links without a
station parameter continue to act on the current selection.

## Verification

The completed build, test results, native evidence and IPA checksums are in the
[2 November validation record](ios_v2_validation_2026-11-02.md).

Portable source checks are distinct from Xcode compilation. GitHub Actions
builds the iOS 16 and iOS 26 device targets with their widget extensions, runs
core and hosted audio/schedule/switch tests, and captures native portrait and
landscape grid/list/reordering interactions. Build numbers come from CI's run
number; a local build still requires an explicit `PHILHARMONIC_BUILD_NUMBER`.

Physical iPhone installation, Shanghai network acceptance, background audio,
Bluetooth/AirPlay and unattended scheduled starts require device checks. No
physical installation is implied by a successful build or simulator result.
