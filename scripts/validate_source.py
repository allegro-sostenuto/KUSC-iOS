#!/usr/bin/env python3
"""Portable structural checks. These do not replace Swift compilation or device tests.
Optional Python packages: tree-sitter, tree-sitter-swift, Pillow.
"""
from pathlib import Path
import json, plistlib, re, sys, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
errors=[]
for p in (ROOT/'Configuration').iterdir():
    if p.suffix in {'.plist','.entitlements','.xcprivacy'}:
        try: plistlib.loads(p.read_bytes())
        except Exception as e: errors.append(f'{p}: {e}')
for p in (ROOT/'KUSC.xcodeproj').rglob('*'):
    if p.suffix=='.xcscheme' or p.name=='contents.xcworkspacedata':
        try: ET.parse(p)
        except Exception as e: errors.append(f'{p}: {e}')
project=(ROOT/'KUSC.xcodeproj/project.pbxproj').read_text()
for path in re.findall(r'"path" = "([^"]+)";',project):
    if path.endswith(('.app','.appex','.xctest')): continue
    if not (ROOT/path).exists(): errors.append(f'Missing project file {path}')
for p in ROOT.rglob('*.json'):
    try: json.loads(p.read_text())
    except Exception as e: errors.append(f'{p}: {e}')
try:
    from tree_sitter import Language, Parser
    import tree_sitter_swift
    parser=Parser(Language(tree_sitter_swift.language()))
    files=list(ROOT.rglob('*.swift'))
    for p in files:
        data=p.read_bytes();tree=parser.parse(data)
        pending=[tree.root_node]
        while pending:
            n=pending.pop()
            if n.type=='ERROR' or n.is_missing: errors.append(f'{p.relative_to(ROOT)}:{n.start_point}: syntax {n.type}')
            pending.extend(n.children)
    print(f'Swift syntax parsed: {len(files)} files (not type-checked).')
except ImportError:
    print('Swift syntax parser not installed; skipped. Run Xcode/Swift for authoritative validation.')
try:
    from PIL import Image
    folder=ROOT/'Assets.xcassets/AppIcon.appiconset'
    for row in json.loads((folder/'Contents.json').read_text())['images']:
        image=Image.open(folder/row['filename'])
        pixels=int(row['size'].split('x')[0])*int(row['scale'][0])
        if image.size!=(pixels,pixels): errors.append(f'Wrong icon dimensions {row["filename"]}')
        if 'A' in image.getbands() and image.getextrema()[-1]!=(255,255): errors.append('Icon contains transparency')
    print('App icon dimensions and opacity checked.')
except ImportError: print('Pillow not installed; icon check skipped.')
methods=sum(len(re.findall(r'func test\w+\(',p.read_text())) for p in (ROOT/'Tests').glob('*.swift'))
print(f'XCTest methods present: {methods} (not executed by this script).')
for e in errors: print(e,file=sys.stderr)
print(f'Structural errors: {len(errors)}')
sys.exit(bool(errors))
