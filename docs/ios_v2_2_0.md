# Philharmonic iOS 2.2.0

Station names now include a small national flag image throughout the iPhone
interface: player header and metadata fallback, station grid/list, Settings →
Quality, scheduled-start selection and saved schedule, home-screen widgets,
and Live Activity / expanded Dynamic Island labels. The compatibility CarPlay
station rows use the same artwork in their supported image slot.

All seventeen station IDs map to their broadcaster's country. The thirteen
images use the standard national designs and their original proportions,
including Switzerland's square flag. The images are bundled, full-colour PNGs
from [Flagpedia's Wikimedia-based flag collection](https://flagpedia.net/download/api),
downloaded unchanged from `https://flagcdn.com/h40/{country-code}.png` on
7 November 2026. Countries: US, CH, SE, FR, DE, PL, RU, HR, FI, IT, RO, PT, NL.
The source images total 2,870 bytes. Asset scale is 3×, giving a nominal height
of 13⅓ points. They are image attachments within the station text, not emoji;
line wrapping and the existing text styles continue to apply.

The flag mapping is derived from stable IDs. Stored station names, catalogue
JSON, widget snapshots, activity attributes, identifiers and user preferences
retain their existing formats. Unknown future IDs use plain text. Flags are
decorative for accessibility; existing station/button labels remain readable.

iOS system-controlled Now Playing and notification text cannot embed a custom
inline image. Those text fields retain the station name; the app's own widget
and Live Activity views render the image flag. Programme and work titles are
not country labels and only receive a flag when they display a station fallback.

## Checks and packages

Portable structural validation parsed 77 Swift files with no syntax errors.
All seventeen station IDs have a mapping and all thirteen referenced images
are bundled. The flag contact sheet was visually inspected. These checks do
not constitute Swift type-checking or a native UI/device run.

Both Release device builds passed in
[run 72](https://github.com/allegro-sostenuto/philharmonic/actions/runs/42357082308),
source `3fe65606b0e77ff0fcf3784aba8b6d50b3592eeb`. Both app and embedded extension
report 2.2.0 (build 72). ZIP integrity, CI SHA-256 records, source revision,
bundle identifiers, App Groups and the expected widget extension were checked.
All thirteen flag names are present in both app and widget compiled asset
catalogues. CI also validated device code, deployment targets and signing material.

No playback, migration, simulator UI or physical-device suite was rerun for
this small presentation update. The ordinary iPhone Release schemes exclude
CarPlay; its compatible list-row source changes were syntax checked only.
AltStore must sign these unsigned packages before installation.

| Package | SHA-256 |
|---|---|
| Philharmonic-17 | `25428530c66c87ae489af86cb9604fc443dcb1bff81b8821afe51d2b9c4e38bc` |
| Philharmonic-SE | `86974126adeda5c06068ced0a91bfaf8ba5395dffdae9a90f7078913ac23a505` |

The IPAs and `verified-builds.json` are stored locally under
`artifacts/ci-42357082308/`.
