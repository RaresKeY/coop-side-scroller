#!/usr/bin/env python3
"""Copy a small licensed selection locally; never commit these files."""
import argparse, hashlib, json, shutil, fcntl
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--library', type=Path, default=ROOT.parent/'CraftPix')
a = parser.parse_args()
lib = a.library.resolve()
collection = lib/'collections/Prototype Characters'
pack = collection/'assets/craftpix-net-949015-prototype-saber-fighter-pixel-sprite-sheet'
archive = collection/'archives/craftpix-net-949015-prototype-saber-fighter-pixel-sprite-sheet.zip'
ui = lib/'packs/rpg-game-ui/source/Sliced Images/Part_1/Top Game Bar'
hash_file = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
selection = [(pack/'Animations'/f'{name}.png', f'character/{name}.png') for name in ['Idle','Walk','Run','Jump','Attack 1','Hurt','Dead']]
selection += [(ui/f'tgb_menu_button{suffix}.png', f'ui/button{suffix}.png') for suffix in ['', '-HOVER', '-PUSHED']]
tiles = collection/'assets/craftpix-net-141897-free-prototype-2d-platformer-32x32-pixel-tileset'
selection += [(tiles/'1 Tiles'/f'Tile_{n:02}.png', f'tiles/Tile_{n:02}.png') for n in [2]]
selection += [(tiles/'Licens.txt','tiles/Licens.txt')]
selection += [(pack/'Licens.txt','character/Licens.txt')]
# Validate complete selection before copying any data.
for source, _ in selection:
 if not source.is_file(): raise SystemExit(f'Missing licensed input: {source}')
manifest = {'source':'CraftPix', 'license':'https://craftpix.net/file-licenses/', 'character_product':'https://craftpix.net/product/prototype-saber-fighter-pixel-sprite-sheet/', 'character_archive_sha256':hash_file(archive), 'tiles_archive_sha256':hash_file(collection/'archives/craftpix-net-141897-free-prototype-2d-platformer-32x32-pixel-tileset.zip'), 'tiles_product':'https://craftpix.net/freebies/free-prototype-2d-platformer-32x32-pixel-tileset/', 'ui_archive_sha256':hash_file(lib/'packs/rpg-game-ui/archives/craftpix-896711-rpg-game-ui.zip'), 'operations':'Unchanged PNG copies; runtime AtlasTexture regions; no exported artwork tools.', 'files':[]}
clips = {}
for source, target in selection:
 dest = ROOT/'assets/private'/target
 dest.parent.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(source,dest)
 manifest['files'].append({'source':str(source.relative_to(lib)), 'target':str(dest.relative_to(ROOT)), 'sha256':hash_file(source)})
 if target.startswith('character/') and dest.suffix == '.png':
  with Image.open(source).convert('RGBA') as image:
   frames = [i for i in range(image.width//128) if sum(v>0 for v in image.getchannel('A').crop((i*128,0,(i+1)*128,128)).tobytes()) >= 200]
   clips[source.stem] = frames
 if dest.suffix == '.png':
  # Godot will populate remap/deps during import.
  dest.with_suffix('.png.import').write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n[params]\nmipmaps/generate=true\n')
(ROOT/'assets/craftpix-clips.json').write_text(json.dumps(clips,indent=2)+'\n')
(ROOT/'assets/craftpix-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Record actual adoption under the library's mutation lock.
with (lib/'.library.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 record = lib/'records/coop-side-scroller-usage.json'
 temp = record.with_suffix('.json.tmp')
 temp.write_text(json.dumps({'consumer':'../coop-side-scroller','usage':'Character animation gameplay integration and button styles','manifest':'../coop-side-scroller/assets/craftpix-manifest.json','character_archive_sha256':manifest['character_archive_sha256'],'files':manifest['files']},indent=2)+'\n')
 temp.replace(record)
print(f'Imported {len(selection)} licensed files into ignored assets/private/')
