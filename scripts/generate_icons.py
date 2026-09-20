#!/usr/bin/env python3
"""Only needed to edit the icon. Runtime/build has no Python dependencies."""
from pathlib import Path
import json
import cairosvg
root=Path(__file__).resolve().parents[1]
folder=root/'Assets.xcassets/AppIcon.appiconset'
svg=(folder/'treble-clef.svg').read_bytes()
images=[]
for points in [20,29,40,60]:
    for scale in [2,3]:
        filename=f'icon-{points}@{scale}x.png'
        cairosvg.svg2png(bytestring=svg,write_to=str(folder/filename),output_width=points*scale,output_height=points*scale)
        images.append({'size':f'{points}x{points}','idiom':'iphone','filename':filename,'scale':f'{scale}x'})
cairosvg.svg2png(bytestring=svg,write_to=str(folder/'icon-1024.png'),output_width=1024,output_height=1024)
images.append({'size':'1024x1024','idiom':'ios-marketing','filename':'icon-1024.png','scale':'1x'})
(folder/'Contents.json').write_text(json.dumps({'images':images,'info':{'version':1,'author':'xcode'}},indent=2)+'\n')
(root/'Assets.xcassets/Contents.json').write_text(json.dumps({'info':{'version':1,'author':'xcode'}})+'\n')
print('Generated opaque red-clef icons.')
