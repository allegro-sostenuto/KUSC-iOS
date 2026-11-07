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

Only the two Release package builds are requested for this small UI update;
playback, migration and historical UI suites are not rerun. Build evidence,
source revision and IPA checksums will be recorded when packaging completes.
