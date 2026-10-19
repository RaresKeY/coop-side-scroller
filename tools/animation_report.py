#!/usr/bin/env python3
"""Contact sheets of actual game captures, never transforms licensed source art."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw
parser = argparse.ArgumentParser()
parser.add_argument('directory',type=Path)
args = parser.parse_args()
for clip in ['Idle','Walk','Run','Jump','Attack_1','Hurt','Dead']:
 for face in ['R','L']:
  paths = sorted(args.directory.glob(f'{clip}-{face}-*.png'))
  if not paths: continue
  crop = (540,270,800,480)
  width,height = 260,210
  columns = min(len(paths),4)
  contact = Image.new('RGB',(columns*width,((len(paths)+columns-1)//columns)*(height+22)),(20,30,42))
  draw = ImageDraw.Draw(contact)
  for index,path in enumerate(paths):
   x,y=index%columns*width,index//columns*(height+22)
   with Image.open(path) as scene: contact.paste(scene.crop(crop),(x,y+22))
   draw.text((x+5,y+4),path.stem,fill='white')
  contact.save(args.directory/f'review-{clip}-{face}.png')
print('Wrote scene-context contact sheets; all original full-scene captures retained.')
# Every tick from the real core-driven jump/attack replay, in scene context.
import json
trace_path = args.directory/'playback.json'
if trace_path.exists():
 trace = json.loads(trace_path.read_text())
 for action in ['jump','attack']:
  frames = [entry for entry in trace if entry['action']==action]
  contact=Image.new('RGB',(7*220,((len(frames)+6)//7)*222),(20,30,42))
  draw=ImageDraw.Draw(contact)
  for i,entry in enumerate(frames):
   x,y=i%7*220,i//7*222
   with Image.open(args.directory/f'live-{action}-{entry["tick"]:02}.png') as scene:
    contact.paste(scene.crop((560,280,780,480)),(x,y+22))
   draw.text((x+3,y+4),f't{entry["tick"]:02} {entry["clip"]} f{entry["frame"]} y{entry["y"]:.1f}',fill='white')
  contact.save(args.directory/f'review-live-{action}.png')
