#!/usr/bin/env python3
"""Attach the tested Wasm loader to a fresh Godot 4.7 static export; fail closed on template drift."""
from pathlib import Path
import shutil
import hashlib
import json
import subprocess
from datetime import datetime, timezone
ROOT=Path(__file__).resolve().parents[1]
site=ROOT/'build/web'
html=(site/'index.html').read_text()
replacements=[('<script src="index.js"></script>','<script src="ember_core_bridge.js"></script>\n\t\t<script src="index.js"></script>'),('engine.startGame({','globalThis.EmberCoreWebReady.then(() => engine.startGame({'),("\t\t}).then(() => {\n\t\t\tsetStatusMode('hidden');","\t\t})).then(() => {\n\t\t\tsetStatusMode('hidden');")]
for old,new in replacements:
 if html.count(old)!=1: raise SystemExit('Unexpected Godot export shell; review the Wasm boot attachment')
 html=html.replace(old,new,1)
(site/'index.html').write_text(html)
shutil.copyfile(ROOT/'adapters/web/ember_core_bridge.js',site/'ember_core_bridge.js')
shutil.copyfile(ROOT/'build/wasm/ember_core.wasm',site/'ember_core.wasm')
print('Web export awaits portable core Wasm before engine startup.')

# Identify the bytes players actually receive, even for a dirty local candidate.
files={name:hashlib.sha256((site/name).read_bytes()).hexdigest() for name in
       ['index.pck','index.js','index.wasm','ember_core_bridge.js','ember_core.wasm',
        'index.audio.worklet.js','index.audio.position.worklet.js']}
metadata={"commit":subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
          "dirty":bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=normal'],cwd=ROOT,text=True).strip()),
          "built":datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
          "payload":hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()}
(site/'build-info.json').write_text(json.dumps({**metadata,"files":files},indent=2)+'\n')
html=(site/'index.html').read_text()
html=html.replace('<script src="ember_core_bridge.js"></script>',
                  '<script>globalThis.EmberBuildInfo=Object.freeze('+json.dumps(metadata)+');</script>\n\t\t<script src="ember_core_bridge.js"></script>',1)
(site/'index.html').write_text(html)
