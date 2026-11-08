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

Pending focused GitHub Actions compilation, policy/boundary tests and native UI
captures. Portable source validation parsed 86 Swift files without syntax
errors; this is a structural check, not a Swift type-check.

## Recognition follow-up

The user's recognition request is explicitly sequenced after this release and
the completed evaluation in chat `misc`. That evaluation finds no ready-made
free/open classical recogniser with a broad public excerpt catalogue. Its first
recommendation is an audfprint feasibility experiment against a labelled local
reference collection, including unknown recordings and other performances as
negative cases. Do not present an unbuilt catalogue or engine as a working
app identification service. No recognition implementation is included here.
