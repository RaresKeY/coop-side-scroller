#!/usr/bin/env python3
"""Copy a small licensed selection locally; never commit these files."""
import argparse, hashlib, json, shutil, fcntl
from pathlib import Path
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
selection += [(pack/'Licens.txt','character/Licens.txt')]
# Validate complete selection before copying any data.
for source, _ in selection:
 if not source.is_file(): raise SystemExit(f'Missing licensed input: {source}')
manifest = {'source':'CraftPix', 'license':'https://craftpix.net/file-licenses/', 'character_product':'https://craftpix.net/product/prototype-saber-fighter-pixel-sprite-sheet/', 'character_archive_sha256':hash_file(archive), 'ui_archive_sha256':hash_file(lib/'packs/rpg-game-ui/archives/craftpix-896711-rpg-game-ui.zip'), 'operations':'Unchanged PNG copies; runtime AtlasTexture regions; no exported artwork tools.', 'files':[]}
for source, target in selection:
 dest = ROOT/'assets/private'/target
 dest.parent.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(source,dest)
 manifest['files'].append({'source':str(source.relative_to(lib)), 'target':str(dest.relative_to(ROOT)), 'sha256':hash_file(source)})
 if dest.suffix == '.png':
  # Godot will populate remap/deps during import.
  dest.with_suffix('.png.import').write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n[params]\nmipmaps/generate=true\n')
(ROOT/'assets/craftpix-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Record actual adoption under the library's mutation lock.
with (lib/'.library.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 record = lib/'records/coop-side-scroller-usage.json'
 temp = record.with_suffix('.json.tmp')
 temp.write_text(json.dumps({'consumer':'../coop-side-scroller','usage':'Character animation gameplay integration and button styles','manifest':'../coop-side-scroller/assets/craftpix-manifest.json','character_archive_sha256':manifest['character_archive_sha256'],'files':manifest['files']},indent=2)+'\n')
 temp.replace(record)
print(f'Imported {len(selection)} licensed files into ignored assets/private/')
