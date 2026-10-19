#!/usr/bin/env python3
"""Attach the tested Wasm loader to a fresh Godot 4.7 static export; fail closed on template drift."""
from pathlib import Path
import shutil
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
