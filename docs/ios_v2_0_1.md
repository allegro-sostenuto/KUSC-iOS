# Philharmonic iOS 2.0.1

Standard audio quality is the new default, targeting roughly KUSC's 96 kbps.
Six stations change to verified 96–128 kbps sources; KUSC and HR Klasik already
use nearby rates. Radio Chopin (≈320 AAC) and Orpheus Large-Scale/Russian
Classical (192 MP3) retain their only verified/published sources.

Settings → Advanced → Audio quality offers Standard and High. High restores the
original higher-rate sources where available. The screen shows the selected
station's actual configured codec and nominal bitrate. The choice is global,
persists across launches and upgrades old preferences to Standard without
resetting other settings. Unknown future quality values fall back to Standard.

Changing quality rejoins the same live station while preserving Play/Pause
intent, metadata, timers, scheduled station and interruption policy. A station
with the same source in both modes continues uninterrupted. Network buffering,
retry timing, installation identifiers, widget extensions and Android are
unchanged. [Source rates and exceptions](station_sources_v2.md).

Verification and package records will be recorded after the focused CI run.
