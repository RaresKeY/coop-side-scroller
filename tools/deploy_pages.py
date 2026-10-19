#!/usr/bin/env python3
"""Explicit deployment of the already reviewed current web candidate."""
import os, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT/'build/web'
DESTINATION = 'https://github.com/RaresKeY/coop-side-scroller.git'
def git(*args, **kwargs):
 return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,**kwargs).strip()
if git('remote','get-url','--push','origin') != DESTINATION:
 raise SystemExit('Origin does not match the configured GitHub project; inspect before deployment.')
for name in ['index.html','index.js','index.pck','index.wasm','.nojekyll','THIRD_PARTY_NOTICES.txt']:
 if not (SITE/name).is_file(): raise SystemExit(f'Missing candidate {name}; run tools/build_web.sh')
allowed = {'.html','.js','.pck','.wasm','.png','.txt'}
if any(p.is_dir() or (p.name!='.nojekyll' and p.suffix not in allowed) for p in SITE.iterdir()):
 raise SystemExit('Unexpected candidate content')
with tempfile.TemporaryDirectory(prefix='ember-pages-index-') as tmp:
 env = dict(os.environ,GIT_INDEX_FILE=str(Path(tmp)/'index'))
 prefix = ['git','--git-dir',str(ROOT/'.git'),'--work-tree',str(SITE)]
 subprocess.run([*prefix,'read-tree','--empty'],env=env,check=True)
 subprocess.run([*prefix,'add','--all','.'],cwd=SITE,env=env,check=True)
 tree = subprocess.check_output([*prefix,'write-tree'],env=env,text=True).strip()
 parent = subprocess.run(['git','-C',str(ROOT),'rev-parse','--verify','refs/heads/gh-pages'],capture_output=True,text=True)
 args=['commit-tree',tree]
 if parent.returncode==0: args += ['-p',parent.stdout.strip()]
 commit=git(*args,input='Deploy current Godot Web prototype\n')
 git('update-ref','refs/heads/gh-pages',commit)
 subprocess.run(['git','-C',str(ROOT),'push','origin','refs/heads/gh-pages:refs/heads/gh-pages'],check=True)
print('Pushed playable candidate; verify GitHub Pages build and runtime before removing local build/web.')
