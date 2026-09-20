#!/usr/bin/env python3
"""Validate this project's unsigned device IPA before handing it to AltStore.

No third-party packages are required. The app and extension use thin arm64;
embedded vendor libraries may be universal if they contain usable arm64 device
code. An arm64 simulator is rejected by its LC_BUILD_VERSION platform.
Apple's Mach-O definitions: apple-oss-distributions/xnu/EXTERNAL_HEADERS/mach-o/loader.h.
The app and extension must have no signing identity. Embedded vendor libraries
may retain verified Apple signatures. Signed binaries require macOS codesign.
"""

import argparse
import os
from pathlib import Path, PurePosixPath
import plistlib
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(value):
    parts = tuple(int(x) for x in str(value).split('.'))
    require(1 <= len(parts) <= 3, f'Invalid OS version: {value}')
    return parts + (0,) * (3 - len(parts))


def packed_version(value):
    return (value >> 16, (value >> 8) & 255, value & 255)


def macho_header(data, name):
    formats = {b'\xcf\xfa\xed\xfe': ('<', 32), b'\xfe\xed\xfa\xcf': ('>', 32),
               b'\xce\xfa\xed\xfe': ('<', 28), b'\xfe\xed\xfa\xce': ('>', 28)}
    require(data[:4] in formats, f'{name}: expected thin Mach-O binary')
    endian, size = formats[data[:4]]
    require(len(data) >= size, f'{name}: truncated Mach-O header')
    return endian, size, struct.unpack_from(endian + '7I', data)


def inspect_macho(data, name, allow_legacy_ios=False, library=False):
    """Return the deployment target and whether a code-signature command exists."""
    endian, header_size, header = macho_header(data, name)
    _, cpu, subtype, filetype, count, commands_size, _ = header
    if library:
        require(cpu in (12, 0x0100000C), f'{name}: embedded library has a non-iPhone CPU slice')
    else:
        require(header_size == 32 and cpu == 0x0100000C and (subtype & 0x00FFFFFF) == 0,
                f'{name}: expected plain arm64 compatible with both supported phone families')
    require(filetype in (2, 6), f'{name}: expected executable or dynamic library')
    end = header_size + commands_size
    require(end <= len(data), f'{name}: truncated Mach-O load commands')
    offset, minimum, signed = header_size, None, False
    for _ in range(count):
        require(offset + 8 <= end, f'{name}: missing load command')
        command, size = struct.unpack_from(endian + '2I', data, offset)
        require(size >= 8 and offset + size <= end, f'{name}: invalid load command length')
        if command == 0x32:  # LC_BUILD_VERSION
            require(size >= 24, f'{name}: truncated LC_BUILD_VERSION')
            platform, min_os = struct.unpack_from(endian + '2I', data, offset + 8)
            require(platform == 2, f'{name}: platform {platform}; expected iOS device (2), not simulator (7)')
            require(minimum is None, f'{name}: duplicate platform command')
            minimum = packed_version(min_os)
        elif command == 0x25 and allow_legacy_ios:  # LC_VERSION_MIN_IPHONEOS
            # Older device Swift runtime dylibs can carry this command instead.
            # The arm64 iOS simulator arrived after LC_BUILD_VERSION; these
            # legacy arm64 iPhoneOS libraries are device code. Current app and
            # extension executables still require explicit LC_BUILD_VERSION.
            require(size >= 16, f'{name}: truncated LC_VERSION_MIN_IPHONEOS')
            require(minimum is None, f'{name}: duplicate platform command')
            minimum = packed_version(struct.unpack_from(endian + 'I', data, offset + 8)[0])
        elif command == 0x1D:  # LC_CODE_SIGNATURE
            require(size >= 16, f'{name}: truncated LC_CODE_SIGNATURE')
            start, length = struct.unpack_from(endian + '2I', data, offset + 8)
            require(start + length <= len(data), f'{name}: truncated code-signature data')
            signed = length > 0
        offset += size
    require(offset == end, f'{name}: inconsistent Mach-O command count')
    require(minimum is not None, f'{name}: missing LC_BUILD_VERSION device platform')
    return minimum, signed


def library_slices(data, name):
    """Read fat32/fat64, including swapped byte order, without trusting offsets."""
    formats = {b'\xca\xfe\xba\xbe': ('>', '5I'), b'\xbe\xba\xfe\xca': ('<', '5I'),
               b'\xca\xfe\xba\xbf': ('>', '2I2Q2I'), b'\xbf\xba\xfe\xca': ('<', '2I2Q2I')}
    if data[:4] not in formats:
        return [(name, data)]
    endian, layout = formats[data[:4]]
    require(len(data) >= 8, f'{name}: truncated universal header')
    count = struct.unpack_from(endian + 'I', data, 4)[0]
    stride = struct.calcsize(endian + layout)
    table_end = 8 + count * stride
    require(count > 0 and table_end <= len(data), f'{name}: invalid universal slice table')
    slices, regions = [], []
    for index in range(count):
        cpu, subtype, start, size, alignment, *_ = struct.unpack_from(endian + layout, data, 8 + index * stride)
        require(start >= table_end and size > 0 and start + size <= len(data),
                f'{name}: universal slice outside binary')
        require(alignment < 64 and start % (1 << alignment) == 0, f'{name}: misaligned universal slice')
        require(not any(start < end and begin < start + size for begin, end in regions),
                f'{name}: overlapping universal slices')
        regions.append((start, start + size))
        chunk = data[start:start + size]
        label = f'{name}[slice {index}]'
        _, _, header = macho_header(chunk, label)
        require(header[1:3] == (cpu, subtype), f'{label}: architecture differs from universal table')
        slices.append((label, chunk))
    return slices


def inspect_library(data, name, minimum):
    signed_slices, usable_arm64 = [], False
    for label, chunk in library_slices(data, name):
        min_os, signed = inspect_macho(chunk, label, allow_legacy_ios=True, library=True)
        _, _, header = macho_header(chunk, label)
        if header[1] == 0x0100000C and (header[2] & 0x00FFFFFF) == 0 and min_os <= minimum:
            usable_arm64 = True
        if signed:
            signed_slices.append((label, chunk))
    require(usable_arm64, f'{name}: library lacks a usable plain arm64 iOS device slice')
    return signed_slices


def check_signature(data, name, allow_apple_vendor=False):
    """Permit ad-hoc signatures, or Apple-anchored signatures on vendor libraries."""
    require(sys.platform == 'darwin', f'{name}: signature present; macOS codesign is required to audit it')
    with tempfile.TemporaryDirectory(prefix='kusc-signature-') as temp:
        path = Path(temp) / 'executable'
        path.write_bytes(data)
        result = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(path)],
                                capture_output=True, text=True, env={**os.environ, 'LC_ALL': 'C'})
        details = result.stdout + result.stderr
        if allow_apple_vendor and result.returncode == 0 and 'Signature=adhoc' not in details:
            verified = subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R', 'anchor apple', str(path)],
                                      capture_output=True, text=True, env={**os.environ, 'LC_ALL': 'C'})
            require(verified.returncode == 0, f'{name}: vendor library signature is not verified against Apple')
            return
        require(result.returncode == 0 and 'Signature=adhoc' in details,
                f'{name}: expected unsigned or ad-hoc binary, found identity/unknown signing')
        require('Authority=' not in details, f'{name}: contains a signing authority')
        for line in details.splitlines():
            if line.startswith('TeamIdentifier='):
                require(line == 'TeamIdentifier=not set', f'{name}: contains an Apple Team identifier')


def validate(path, scheme, prefix):
    minimum = (16, 0, 0) if scheme == 'KUSC-SE' else (26, 0, 0)
    bundle_id = prefix + ('.classic' if scheme == 'KUSC-SE' else '.modern')
    root = f'Payload/{scheme}.app'
    expected_extensions = [] if scheme == 'KUSC-SE' else [f'{root}/PlugIns/KUSCLiveActivity.appex']
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)), 'IPA contains duplicate archive paths')
        require(archive.testzip() is None, 'IPA ZIP integrity check failed')
        vendor_signatures = []
        for entry in entries:
            parts = PurePosixPath(entry.filename).parts
            require(not entry.filename.startswith('/') and '..' not in parts and '\\' not in entry.filename,
                    f'Unsafe archive path: {entry.filename}')
            require(entry.filename == 'Payload/' or entry.filename.startswith(root + '/'),
                    f'Unexpected archive content: {entry.filename}')
            require(not stat.S_ISLNK(entry.external_attr >> 16), f'Unexpected symlink: {entry.filename}')
            require(not entry.filename.endswith(('.mobileprovision', '.p12', '.p8')),
                    f'Unexpected provisioning or signing material: {entry.filename}')

        extensions = sorted({str(PurePosixPath(name).parent) for name in names
                             if name.endswith('.appex/Info.plist')})
        require(extensions == expected_extensions, f'Unexpected embedded extensions: {extensions}')
        binaries = {}
        root_versions = None
        for bundle in [root] + extensions:
            info_path = bundle + '/Info.plist'
            require(info_path in names, f'Missing {info_path}')
            info = plistlib.loads(archive.read(info_path))
            expected_id = bundle_id if bundle == root else bundle_id + '.activity'
            require(info.get('CFBundleIdentifier') == expected_id,
                    f'{bundle}: expected bundle identifier {expected_id}')
            require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'],
                    f'{bundle}: CFBundleSupportedPlatforms must be iPhoneOS')
            require(version(info.get('MinimumOSVersion', '0')) == minimum,
                    f'{bundle}: unexpected MinimumOSVersion {info.get("MinimumOSVersion")}')
            require(info.get('UIDeviceFamily') == [1], f'{bundle}: expected iPhone-only device family')
            for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
                value = info.get(key)
                require(isinstance(value, str) and value and '$(' not in value, f'{bundle}: unresolved {key}')
            bundle_versions = (info['CFBundleShortVersionString'], info['CFBundleVersion'])
            if bundle == root:
                root_versions = bundle_versions
                require(info.get('CFBundlePackageType') == 'APPL', f'{bundle}: incorrect app package type')
                scenes = info.get('UIApplicationSceneManifest', {}).get('UISceneConfigurations', {})
                require(not any('CPTemplateApplication' in role for role in scenes),
                        f'{bundle}: CarPlay scene found in personal build')
            else:
                require(bundle_versions == root_versions, f'{bundle}: extension versions must match the app')
                require(info.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension',
                        f'{bundle}: expected WidgetKit Live Activity extension')
            executable = info.get('CFBundleExecutable', '')
            require(executable and '/' not in executable and '$(' not in executable,
                    f'{bundle}: invalid CFBundleExecutable')
            binary = bundle + '/' + executable
            require(binary in names, f'Missing executable: {binary}')
            require(archive.getinfo(binary).external_attr >> 16 & 0o111,
                    f'{binary}: archive lost executable permission')
            data = archive.read(binary)
            min_os, signed = inspect_macho(data, binary)
            require(min_os == minimum, f'{binary}: executable deployment target differs from Info.plist')
            binaries[binary] = (data, signed)

        # Also inspect any embedded dylibs/framework binaries; none may be simulator code.
        for entry in entries:
            if entry.is_dir() or entry.filename in binaries:
                continue
            with archive.open(entry) as handle:
                magic = handle.read(4)
            if entry.filename.endswith('.dylib') or magic in (
                    b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce',
                    b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'):
                data = archive.read(entry)
                vendor_signatures.extend(inspect_library(data, entry.filename, minimum))
        for binary, (data, signed) in binaries.items():
            if signed:
                check_signature(data, binary)
        for binary, data in vendor_signatures:
            check_signature(data, binary, allow_apple_vendor=True)
    print(f'PASS: {scheme}: arm64 iOS device IPA, minimum iOS {minimum[0]}.0, '
          f'{len(extensions)} extension(s), no app/extension signing identity or provisioning.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--scheme', required=True, choices=['KUSC-SE', 'KUSC-17'])
    parser.add_argument('--bundle-prefix', default='org.personal.kusc')
    args = parser.parse_args()
    try:
        validate(args.ipa, args.scheme, args.bundle_prefix)
    except (ValueError, OSError, KeyError, struct.error, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f'IPA validation failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
