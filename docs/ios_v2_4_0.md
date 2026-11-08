# Philharmonic iOS 2.4.0

## Changes

- Stations has a native segmented Grid / List / Map control. MapKit presents a
  satellite globe and named Globe / Continent / Country zoom levels. Pan and
  rotate to explore; the three controls set the zoom. No location permission is
  requested. The continent/country context follows deliberate map movement;
  changing zoom alone retains the station's geographic context.
- Seventeen stations share fourteen base-city pins. Tapping a single-station
  city selects it and returns to the player. Paris (two) and Moscow (three) open
  native station-choice sheets, in saved station order. Selection preserves
  playing/paused intent. A Cities menu provides the same choices accessibly,
  including when pins overlap. Clusters move to the next named zoom level.
- Settings → Quality has one-click Lowest, Balanced and Highest buttons for all
  stations. Balanced selects the offered bitrate closest to KUSC's 96 kbps,
  preferring the lower rate in a tie and the existing default format for equal
  bitrates. Per-station menus continue to show the actual kbps/format choices.
  A batch saves once and reconnects at most the active station, only if its
  source changes. Pause, interruption and scheduled-start gain policy remain.
- Existing station grid/list controls use a native segmented picker, consistent
  16-point page insets and continuous card corners. List names use native body
  typography. Settings About shows Version and Build on separate native rows.
  Accessibility text sizes stack preset buttons instead of compressing labels.
  Preset titles fit on one line, with black dark-mode surfaces and a border
  marking the selected preset. Native region fitting keeps country views useful
  in both orientations, including both US city pins.

Owned dark surfaces remain black with borders. Main player layout, transport
and header animations, app identifiers, preferences, App Groups, scheduled
starts, widgets and Live Activities are preserved. Flags remain app-only.
Android is deferred. Map tiles are supplied by native MapKit; city assignments
are bundled and do not require geocoding or GPS.

## Base-city provenance

Coordinates approximate city centres. These are broadcaster/station base cities,
not transmitter locations or a claim that every programme is produced there.

| City | Station(s) | Official source |
|---|---|---|
| Los Angeles | KUSC | [Local public file](https://www.classicalcalifornia.org/kusc-local-public-file) |
| Basel | Radio Swiss Classic | [Contact](https://www.radioswissclassic.ch/de/kontakt) |
| Stockholm | Sveriges Radio P2 | [Sveriges Radio address](https://vanliga-fragor-svar.sverigesradio.se/guide/adress-till-sveriges-radio) |
| Paris | France Musique Classique Easy; La Baroque | [Radio France address](https://www.radiofrance.com/faq/comment-venir-la-maison-de-la-radio-et-de-la-musique) |
| Cologne | WDR 3 | [WDR 3 contact](https://www1.wdr.de/radio/wdr3/kontakt/index.html) |
| Warsaw | Polskie Radio Chopin | [Contact](https://chopin.polskieradio.pl/kontakt) |
| Moscow | Orpheus Large-Scale Works; Russian Classical Music; Camerata | [Contact](https://radio.orpheus.ru/contacts) |
| Zagreb | HR Klasik | [HRT contacts](https://o-nama.hrt.hr/hrt/kontakti-hrt-a-7672) |
| Helsinki | Yle Klassinen | [Klassinen editorial office](https://yle.fi/aihe/a/20-130103) |
| Prato | Rete Toscana Classica | [Legal address](https://www.retetoscanaclassica.it/note-legali/) |
| Chicago | WFMT | [Contact](https://www.wfmt.com/support-wfmt/contact-us/) |
| Bucharest | Radio România Muzical | [Radio România contacts](https://www.radioromania.ro/contact.html) |
| Lisbon | RTP Ópera / Antena 2 | [Antena 2 contact](https://antena2.rtp.pt/contactos/) |
| Utrecht | Concertzender Oude Muziek | [Address](https://www.concertzender.nl/general-information/address/) |

## Verification

Both Release device builds passed in [run 78](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42460731144),
source `587792a9935fe6a03d95dd6b93a954d546746419`, using Xcode 26.6 and SDK 26.5.
App and embedded widget extension both report 2.4.0 (build 78). ZIP integrity,
CI checksums, source record, versions, bundle IDs and App Groups were verified.
Flags remain app-only; widget/Live Activity sources still match `11997c8`.

All 14 hosted station-switching and live-only settings boundary tests passed in
[run 76](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42458322481),
including the new global-preset single-reconnect/paused-intent case. These use
an isolated engine fixture and do not stream or emit audio. The coordinator
code is unchanged in subsequent runs.

[Run 77](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42459837621)
passed all 17 portable catalogue, geography and quality-preset policy tests and
both native map UI cases. These exercise three zoom levels, a real city-pin
tap, direct selection/dismissal, Paris and Moscow station lists, cancellation,
saved map mode, grid/list controls, reordering and landscape.

The capture review corrected wrapped preset labels and country framing that
cropped a US city. The final app uses native region fitting. Both Quality UI
cases passed in run 78: light/dark channel menus and aligned kbps controls, plus
global presets at regular/accessibility text sizes and paused intent. Only test
scrolling/value-wait helpers and CI scope changed between runs 77 and 78; app
sources are identical. All four focused UI cases passed across runs 77 and 78.

Portable source validation parsed 86 Swift files without syntax errors; this
is a structural check, not a Swift type-check. Both changed test scripts passed
`bash -n`. Native captures use an iPhone 17 / iOS 26.5 simulator with Debug
fixtures (local build 1), and were visually inspected. Gallery:
`artifacts/ios-2.4.0/ui-preview.html`. iOS 16 has compilation coverage only.
The historical screenshot sweep, stream probes and physical-device checks were
not run. No physical installation or audio-output claim is made.

## Verified packages

The IPAs preserve the existing app IDs, App Groups and embedded widget extension.
AltStore must sign them before installation.

| Package | SHA-256 |
|---|---|
| `artifacts/ci-42460731144/Philharmonic-17/Philharmonic-17-unsigned.ipa` | `2bf12b35ba0cfc5c4ebab60fe35c1fcabe1db2c948c8f0f7f131ed620dd35ed1` |
| `artifacts/ci-42460731144/Philharmonic-SE/Philharmonic-SE-unsigned.ipa` | `7871a3e11b20a7dbe0fbfd7b13141d820ac2c702df3f6c86b5df7dc7fd53cebd` |

## Recognition follow-up

The user's November 8 instruction holds ShazamIO/recognition integration until
explicitly resumed. A future recognition catalogue may be closed-source if
free to use. This release contains UI work only; Android remains deferred.
