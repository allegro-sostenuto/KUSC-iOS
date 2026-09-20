#!/usr/bin/env python3
"""Copy named native XCTest PNGs without changing pixels; reject wrong orientation."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import struct
import sys

CAPTURES = {
    "live", "dark", "programme", "settings", "sleep", "schedule", "schedule-output",
    "minimal", "reconnecting", "output", "paused", "no-artwork", "unavailable-programme",
    "partial-buffer", "paused-buffer", "scheduled-silent", "scheduled-fade", "unavailable-output",
    "landscape", "minimal-landscape", "large-text", "programme-large-text", "schedule-large-text",
    "settings-dark", "sleep-dark", "schedule-output-dark", "more",
}


def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)


def capture_name(values):
    for value in values:
        if "more-native-menu" in value:
            return "more"
        for name in sorted(CAPTURES, key=len, reverse=True):
            if re.search(r"capture-" + re.escape(name) + r"(?:[^a-zA-Z0-9-]|$)", value):
                return name
    return None


def png_dimensions(path):
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not an unmodified PNG screenshot: {path}")
    return struct.unpack(">II", header[16:24])


def collect(exported, destination):
    exported = exported.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    found = {}
    # xcresulttool records human-readable attachment names separately from its
    # generated filenames. Walk records without depending on test-group nesting.
    for manifest in sorted(exported.rglob("*.json")):
        try:
            records = json.loads(manifest.read_text())
        except (ValueError, UnicodeError):
            continue
        for record in dictionaries(records):
            values = [value for value in record.values() if isinstance(value, str)]
            name = capture_name(values)
            if not name:
                continue
            for value in values:
                for base in (manifest.parent, exported):
                    try:
                        candidate = (base / value).resolve()
                        candidate.relative_to(exported)
                        if candidate.is_file():
                            png_dimensions(candidate)
                            found[name] = candidate
                    except (OSError, ValueError):
                        continue
    # Some xcresulttool versions include the attachment name in the filename.
    for candidate in sorted(exported.rglob("*.png")):
        name = capture_name([candidate.name])
        if name:
            found.setdefault(name, candidate)

    failures = []
    for name, source in sorted(found.items()):
        width, height = png_dimensions(source)
        is_landscape = name in {"landscape", "minimal-landscape"}
        if (width > height) != is_landscape:
            failures.append(f"Wrong native orientation for {name}: {width}x{height}")
            continue
        target = destination / (name + ".png")
        shutil.copyfile(source, target)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        print(f"Native XCTest capture: {name}.png {width}x{height} SHA256={digest}")
    missing = CAPTURES - set(found)
    if missing:
        failures.append("Missing native captures: " + ", ".join(sorted(missing)))
    if failures:
        raise RuntimeError("\n".join(failures))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: collect_ui_attachments.py <xcresult-export-directory> <capture-directory>")
    try:
        collect(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit(str(error))
