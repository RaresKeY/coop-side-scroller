#!/usr/bin/env python3
"""Explicit dependency-free build; --check validates freshness without compilation."""
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
OUT=ROOT/'build/native';WASM=ROOT/'build/wasm'
receipt=ROOT/'build/core-build.json'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
source_paths=sorted([*ROOT.glob('core/include/*.h'),*ROOT.glob('core/src/*.cpp'),ROOT/'adapters/godot/native_extension.cpp',ROOT/'examples/standalone.cpp',ROOT/'tools/build_core.py',ROOT/'vendored/dependencies.json',ROOT/'vendored/godot/gdextension_interface.h'])
def source_state():return {str(p.relative_to(ROOT)):digest(p) for p in source_paths}
def compiler_state():
 result={}
 for name in ['g++','clang++','wasm-ld']:
  binary=shutil.which(name)
  if not binary:raise SystemExit(f'Missing build tool: {name}')
  path=Path(binary).resolve();stat=path.stat()
  result[name]={'path':str(path),'size':stat.st_size,'mtime_ns':stat.st_mtime_ns}
 return result
outputs=['build/native/libember_core.so','build/native/libember_godot.so','build/native/ember.gdextension','build/native/standalone','build/wasm/ember_core.wasm']
if args.check:
 try:
  data=json.loads(receipt.read_text())
  current=(data['sources']==source_state() and data['compilers']==compiler_state() and all((ROOT/p).is_file() and digest(ROOT/p)==data['outputs'][p] for p in outputs))
 except (OSError,KeyError,ValueError):current=False
 if not current:raise SystemExit('Portable core missing or stale. Run: python3 tools/build_core.py')
 raise SystemExit(0)
OUT.mkdir(parents=True,exist_ok=True);WASM.mkdir(exist_ok=True);(ROOT/'build/.gdignore').touch()
header=ROOT/'vendored/godot/gdextension_interface.h'
lock=json.loads((ROOT/'vendored/dependencies.json').read_text())
if digest(header)!=lock['godot_interface']['sha256']:raise SystemExit('Pinned Godot interface header hash mismatch')
flags=['-std=c++17','-O2','-fno-exceptions','-fno-rtti','-fvisibility=hidden','-Wall','-Wextra','-Werror','-I',str(ROOT/'core/include')]
def run(command):subprocess.run(command,cwd=ROOT,check=True)
sources_before=source_state();compilers=compiler_state()
with tempfile.TemporaryDirectory(prefix='.core-build-',dir=ROOT/'build') as temporary:
 stage=Path(temporary)
 run(['g++',*flags,'-Wl,--as-needed','-fPIC','-shared','-DEMBER_BUILD','core/src/ember_core.cpp','-o',str(stage/'libember_core.so')])
 run(['g++',*flags,'-Wl,--as-needed','-fPIC','-shared','-I',str(header.parent),'adapters/godot/native_extension.cpp','-L',str(stage),'-lember_core','-Wl,-rpath,$ORIGIN','-o',str(stage/'libember_godot.so')])
 (stage/'ember.gdextension').write_text('[configuration]\nentry_symbol="ember_core_extension_init"\ncompatibility_minimum="4.4"\nreloadable=false\n[libraries]\nlinux.x86_64="res://build/native/libember_godot.so"\n')
 run(['g++',*flags,'-Wl,--as-needed','examples/standalone.cpp','-L',str(stage),'-lember_core','-Wl,-rpath,$ORIGIN','-o',str(stage/'standalone')])
 exports=re.findall(r'EC_API\s+[^;]+?\b(ec_v1_\w+)\s*\(', (ROOT/'core/include/ember_core.h').read_text())
 run(['clang++','--target=wasm32',*flags,'-ffreestanding','-nostdlib','-fno-builtin','core/src/ember_core.cpp','core/src/wasm_memory.cpp','-Wl,--no-entry','-Wl,--export-memory','-Wl,--export=__heap_base','-Wl,--initial-memory=1048576','-Wl,--max-memory=1048576',*[f'-Wl,--export={name}' for name in exports],'-o',str(stage/'ember_core.wasm')])
 if source_state()!=sources_before:raise SystemExit('Sources changed during compilation; retry build')
 for path in outputs:os.replace(stage/Path(path).name,ROOT/path)
versions={name:subprocess.check_output([name,'--version'],text=True).splitlines()[0] for name in compilers}
data={'schema':1,'sources':sources_before,'compilers':compilers,'versions':versions,'outputs':{path:digest(ROOT/path) for path in outputs}}
receipt.write_text(json.dumps(data,indent=2)+'\n')
print('Built native C ABI, Godot bridge, standalone and import-free wasm32 boundary.')
