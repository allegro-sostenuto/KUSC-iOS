# Philharmonic iOS 2.0.1

Settings has a **Quality** section: channel names on the left, selected kbps on
the right. Tap a bitrate to open that channel's available codec/bitrate menu.
Each channel's choice persists independently. Defaults target roughly KUSC's
96 kbps; eight channels default to 96–128. Radio Chopin (≈320 AAC) and Orpheus
Large-Scale/Russian Classical (192 MP3) retain their only verified/published
sources. [Full choices, sources and exceptions](station_sources_v2.md).

There are 22 verified source choices across eleven channels. Changing the active
channel's quality rejoins live while preserving Play/Pause intent, metadata,
timers, scheduled station and interruption policy. Changing another channel's
saved quality leaves current playback running. Old settings acquire the defaults
without resetting other preferences; an obsolete saved source falls back only
for its own channel. Network buffering, retry timing, installation identifiers,
widget extensions and Android are unchanged.

Verification and package records will be recorded after the focused CI run.
