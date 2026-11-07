# Philharmonic iOS 2.2.1

Reverts the 2.2.0 flag changes in home-screen widgets and Live Activities,
including expanded Dynamic Island labels. Their views return to the pre-flag
implementation, and widget targets no longer compile the flag-label helper,
station catalogue or flag asset catalogue. App station labels retain their flags.

This is the requested scope correction to the small flag update. Checks are
limited to source validation, the two Release builds and package verification;
extended playback and UI suites are not rerun. Build evidence and checksums
will be recorded after packaging.
