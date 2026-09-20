#!/usr/bin/env python3
"""Preserve native XCTest PNGs and validate logical UI orientation from metadata."""
from pathlib import Path
import hashlib
import html
import json
import re
import shutil
import struct
import sys

CAPTURES = {
    "live", "dark", "programme", "settings", "sleep", "schedule", "schedule-output",
    "minimal", "reconnecting", "output", "paused", "no-artwork", "unavailable-programme",
    "partial-buffer", "paused-buffer", "scheduled-silent", "scheduled-fade", "unavailable-output",
    "landscape", "minimal-landscape", "large-text", "programme-large-text", "schedule-large-text", "sleep-large-text",
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


def capture_name(values, metadata=False):
    for value in values:
        if not metadata and "more-native-menu" in value:
            return "more"
        for name in sorted(CAPTURES, key=len, reverse=True):
            prefix = "capture-metadata-" if metadata else "capture-"
            if re.search(prefix + re.escape(name) + r"(?:[^a-zA-Z0-9-]|$)", value):
                return name
    return None


def png_dimensions(path):
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not an unmodified PNG screenshot: {path}")
    return struct.unpack(">II", header[16:24])


def png_exif_orientation(path):
    # XCTest PNGs can carry an EXIF orientation different from their IHDR
    # dimensions. Browsers and UIImage honor it; no pixels are rewritten here.
    data = path.read_bytes()
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        end = offset + 8 + length
        if end + 4 > len(data):
            break
        if data[offset + 4:offset + 8] == b"eXIf":
            tiff = data[offset + 8:end]
            byte_order = {b"MM": ">", b"II": "<"}.get(tiff[:2])
            if not byte_order or len(tiff) < 8:
                break
            directory = struct.unpack_from(byte_order + "I", tiff, 4)[0]
            if directory + 2 > len(tiff):
                break
            count = struct.unpack_from(byte_order + "H", tiff, directory)[0]
            for index in range(count):
                entry = directory + 2 + index * 12
                if entry + 12 > len(tiff):
                    break
                tag, kind, quantity = struct.unpack_from(byte_order + "HHI", tiff, entry)
                if tag == 0x0112 and kind == 3 and quantity == 1:
                    value = struct.unpack_from(byte_order + "H", tiff, entry + 8)[0]
                    return value if 1 <= value <= 8 else 1
            break
        offset = end + 4
    return 1


def write_viewer(destination, captures):
    """CSS affects display only; linked source PNGs remain byte-for-byte native."""
    cards = []
    for capture in captures:
        name = html.escape(capture["capture"])
        raw_width = capture["rawPNGDimensions"]["width"]
        raw_height = capture["rawPNGDimensions"]["height"]
        width = capture["displayDimensions"]["width"]
        height = capture["displayDimensions"]["height"]
        rotated = capture["logicalOrientation"] == "landscape" and width < height
        angle = -90 if rotated else 0
        display_width, display_height = (height, width) if rotated else (width, height)
        image_width = width / display_width * 100
        cards.append(f'''<section>
<h2>{name}</h2><p>Logical: {capture["logicalOrientation"]}; raw PNG: {raw_width} × {raw_height}; EXIF orientation: {capture["exifOrientation"]}.
<a href="{name}.png">Original PNG</a> · <a href="{name}.metadata.json">Native metadata</a></p>
<div class="viewport" style="aspect-ratio:{display_width}/{display_height}">
<img src="{name}.png" alt="Native {name} capture" style="width:{image_width}%;transform:translate(-50%,-50%) rotate({angle}deg)">
</div></section>''')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Native UI captures</title>
<style>body{margin:24px;background:#f7f7f7;color:#222;font:16px system-ui,sans-serif}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,360px),1fr));gap:24px}section{min-width:0}h2{font-size:20px}.viewport{position:relative;width:100%;max-height:none;background:#ddd;overflow:hidden}.viewport img{position:absolute;top:50%;left:50%;height:auto;max-width:none;image-orientation:from-image}p{line-height:1.5}a{color:#174c9a}</style>
<h1>Native simulator captures</h1>
<p>These are DEBUG layout fixtures with audio and network disabled. Landscape orientation was checked against the app's logical frame in XCTest. Native screenshot dimensions and EXIF orientation can differ from that logical frame; this viewer uses CSS when needed to display landscape captures horizontally. The original PNG files and their pixels are unchanged. Dimensions, EXIF and logical orientation, and SHA-256 hashes are recorded in <a href="capture-manifest.json">the capture manifest</a>.</p><main>
''' + "\n".join(cards) + "</main></html>\n"
    (destination / "index.html").write_text(page, encoding="utf-8")


def collect(exported, destination):
    exported = exported.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    found = {}
    metadata = {}
    # xcresulttool records human-readable attachment names separately from its
    # generated filenames. Walk records without depending on test-group nesting.
    for manifest in sorted(exported.rglob("*.json")):
        try:
            records = json.loads(manifest.read_text())
        except (ValueError, UnicodeError):
            continue
        for record in dictionaries(records):
            values = [value for value in record.values() if isinstance(value, str)]
            metadata_name = capture_name(values, metadata=True)
            name = metadata_name or capture_name(values)
            if not name:
                continue
            for value in values:
                for base in (manifest.parent, exported):
                    try:
                        candidate = (base / value).resolve()
                        candidate.relative_to(exported)
                        if candidate.is_file():
                            if metadata_name:
                                evidence = json.loads(candidate.read_text())
                                if isinstance(evidence, dict) and evidence.get("capture") == name:
                                    metadata[name] = (candidate, evidence)
                            else:
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
    captures = []
    for name, source in sorted(found.items()):
        width, height = png_dimensions(source)
        exif_orientation = png_exif_orientation(source)
        display_width, display_height = (height, width) if exif_orientation in {5, 6, 7, 8} else (width, height)
        target = destination / (name + ".png")
        shutil.copyfile(source, target)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        logical_orientation = "unrecorded"
        evidence = None
        if name not in metadata:
            failures.append(f"Missing native logical orientation metadata: {name}")
        else:
            metadata_source, evidence = metadata[name]
            shutil.copyfile(metadata_source, destination / (name + ".metadata.json"))
            frame = evidence.get("logicalFrame", {})
            logical_width, logical_height = frame.get("width", 0), frame.get("height", 0)
            if (not isinstance(logical_width, (int, float)) or
                    not isinstance(logical_height, (int, float)) or
                    logical_width <= 0 or logical_height <= 0 or logical_width == logical_height):
                failures.append(f"Invalid native logical frame: {name}: {frame}")
            else:
                logical_orientation = "landscape" if logical_width > logical_height else "portrait"
                expected = "landscape" if name in {"landscape", "minimal-landscape"} else "portrait"
                if (logical_orientation != expected or evidence.get("requestedOrientation") != expected):
                    failures.append(f"Wrong logical UI orientation for {name}: {frame}")
        captures.append({"capture": name, "file": target.name, "sha256": digest,
                         "rawPNGDimensions": {"width": width, "height": height},
                         "exifOrientation": exif_orientation,
                         "displayDimensions": {"width": display_width, "height": display_height},
                         "logicalOrientation": logical_orientation, "nativeMetadata": evidence})
        print(f"Native XCTest capture: {name}.png raw={width}x{height} EXIF={exif_orientation} logical={logical_orientation} SHA256={digest}")
    missing = CAPTURES - set(found)
    if missing:
        failures.append("Missing native captures: " + ", ".join(sorted(missing)))
    (destination / "capture-manifest.json").write_text(
        json.dumps({"captures": captures, "validationFailures": failures}, indent=2) + "\n", encoding="utf-8")
    write_viewer(destination, captures)
    if failures:
        raise RuntimeError("\n".join(failures))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: collect_ui_attachments.py <xcresult-export-directory> <capture-directory>")
    try:
        collect(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit(str(error))
