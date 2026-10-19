#!/usr/bin/env python3
"""Audit all local Git objects, public source candidates and Web export before publication.
Known Cloudflare secret values are read/compared only in an offline container.
No secret values, source content or private files are printed or copied to source.
"""
import base64,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
AUDITOR=r'''
import sys,json,base64,re,tomllib
from pathlib import Path
secrets=set()
def collect(value):
 if isinstance(value,dict):
  for key,item in value.items():
   if isinstance(item,str) and len(item)>=8 and any(word in key.lower() for word in ['token','secret','credential','password','key','username']) and not key.lower().endswith('_id'): secrets.add(item.encode())
   collect(item)
 elif isinstance(value,list):
  for item in value: collect(item)
for path in Path('/config').glob('*.json'): collect(json.loads(path.read_text()))
if Path('/runpod-config.toml').is_file(): collect(tomllib.loads(Path('/runpod-config.toml').read_text()))
for path in Path('/test-config').glob('*.json'): collect(json.loads(path.read_text()))
for path in Path('/browser-config').glob('*.json'): collect(json.loads(path.read_text()))
secrets.update(base64.b64encode(value) for value in list(secrets))
if not secrets: raise SystemExit('No private comparison values found; refusing an incomplete audit.')
patterns=[rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=\r\n]{64,}-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'github_pat_[A-Za-z0-9_]{40,}',rb'gh[pousr]_[A-Za-z0-9]{30,}',rb'AKIA[A-Z0-9]{16}',rb'AIza[A-Za-z0-9_-]{35}']
findings=set();chunks=0
for line in sys.stdin:
 item=json.loads(line);data=base64.b64decode(item['data'],validate=True);chunks+=1
 if any(secret in data for secret in secrets): findings.add((item['label'],'known private value'))
 if any(re.search(pattern,data) for pattern in patterns): findings.add((item['label'],'credential signature'))
print(json.dumps({'chunks':chunks,'known_values_compared':len(secrets),'findings':[{'location':loc,'kind':kind} for loc,kind in sorted(findings)],'secret_values_printed':False}))
raise SystemExit(1 if findings else 0)
'''
def main():
 config=Path.home()/'.config/cloudflare-api'
 if config.is_symlink() or config.stat().st_mode&0o077: raise SystemExit('Private config permissions invalid.')
 receipt=json.loads((ROOT.parent/'tooling/cloudflare-api/.local/image.json').read_text())
 command=['podman','run','--rm','--pull=never','--network=none','--read-only','--cap-drop=all','--security-opt=no-new-privileges','--pids-limit=32','--memory=128m','--userns=keep-id','--user',f'{os.getuid()}:{os.getgid()}','--label','io.rareskey.project=coop-side-scroller','--label','io.rareskey.purpose=publication-audit','--volume',f'{config}:/config:ro,Z','--interactive','--entrypoint','python',receipt['image_id'],'-c',AUDITOR]
 for source,target in [(Path.home()/'.runpod/config.toml','/runpod-config.toml'),(Path.home()/'.config/ember-coop-testing','/test-config'),(Path.home()/'.config/runpod-browser','/browser-config')]:
  if source.exists():command[command.index('--entrypoint'):command.index('--entrypoint')]=['--volume',f'{source}:{target}:ro,Z']
 process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
 def send(stream,size,label):
  tail=b''
  while size:
   data=stream.read(min(65536,size))
   if not data: raise RuntimeError('Truncated input')
   size-=len(data)
   process.stdin.write(json.dumps({'label':label,'data':base64.b64encode(tail+data).decode()})+'\n');tail=(tail+data)[-8192:]
 try:
  objects=subprocess.check_output(['git','-C',str(ROOT),'cat-file','--batch-all-objects','--batch-check=%(objectname) %(objecttype)']).decode().splitlines()
  blobs=[line.split()[0] for line in objects]
  reader=subprocess.Popen(['git','-C',str(ROOT),'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
  for oid in blobs:
   reader.stdin.write((oid+'\n').encode());reader.stdin.flush()
   header=reader.stdout.readline().split();send(reader.stdout,int(header[2]),'git-object:'+oid)
   if reader.stdout.read(1)!=b'\n': raise RuntimeError('Git framing error')
  reader.stdin.close();reader.wait()
  paths=set(subprocess.check_output(['git','-C',str(ROOT),'ls-files','--cached','--others','--exclude-standard','-z']).decode().split('\0'))-{''}
  for relative in sorted(paths):
   path=ROOT/relative
   if relative.startswith('assets/private/'): raise RuntimeError('Private artwork in source candidates')
   if path.is_file():
    with path.open('rb') as stream: send(stream,path.stat().st_size,'source:'+relative)
  web_paths=sorted((ROOT/'build/web').glob('*'))
  for path in web_paths:
   if path.is_file():
    with path.open('rb') as stream: send(stream,path.stat().st_size,'web:'+path.name)
  process.stdin.close();report=process.stdout.read();status=process.wait()
  print(report.strip());print(json.dumps({'git_objects':len(blobs),'source_files':len(paths),'web_export_checked':bool(web_paths)}))
  return status
 finally:
  if process.poll() is None: process.terminate();process.wait(timeout=5)
if __name__=='__main__':sys.exit(main())
