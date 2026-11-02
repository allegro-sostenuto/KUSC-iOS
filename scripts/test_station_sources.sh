#!/bin/bash
# Real native AVPlayer readiness/decoder-clock checks on a fresh simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
export PHILHARMONIC_STATION_SOURCES_ONLY=1
bash scripts/test_native_audio.sh "${1:-artifacts/native-station-sources}"
