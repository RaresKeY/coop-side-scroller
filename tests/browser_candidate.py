"""Load local candidate bytes into an already navigated disposable test browser.
No hosting change: assets travel through authenticated controller commands. Only
Godot's large engine Wasm is reused from Pages, after checking its exact SHA-256.
The bridge's script-relative core URL is made absolute when inlining its source.
"""
import base64,hashlib,json
from pathlib import Path


def load_candidate(page, directory: Path, origin: str):
 names=['build-info.json','index.html','index.js','index.pck','ember_core_bridge.js','ember_core.wasm',
        'index.audio.worklet.js','index.audio.position.worklet.js']
 hashes={name:hashlib.sha256((directory/name).read_bytes()).hexdigest() for name in names+['index.wasm']}
 page.evaluate('globalThis.candidateAssets={};true')
 for name in names:
  encoded=base64.b64encode((directory/name).read_bytes()).decode()
  page.evaluate('candidateAssets['+json.dumps(name)+']="";true')
  for offset in range(0,len(encoded),90000):
   page.evaluate('candidateAssets['+json.dumps(name)+']+='+json.dumps(encoded[offset:offset+90000])+';true')
 # Hash the actual reused engine bytes, then serve those verified bytes to Godot.
 verified=page.evaluate('''(async()=>{const r=await fetch('''+json.dumps(origin+'index.wasm')+''');
 if(!r.ok)throw Error('Engine fetch failed');globalThis.candidateEngine=await r.arrayBuffer();
 return [...new Uint8Array(await crypto.subtle.digest('SHA-256',candidateEngine))].map(v=>v.toString(16).padStart(2,'0')).join('');})()''')
 assert verified==hashes['index.wasm'],'Hosted engine differs from local candidate'
 page.evaluate('''(()=>{
 const assets=Object.fromEntries(Object.entries(candidateAssets).map(([n,b])=>[n,Uint8Array.from(atob(b),c=>c.charCodeAt(0))]));
 assets['index.wasm']=new Uint8Array(candidateEngine);
 const originalFetch=globalThis.fetch,base='''+json.dumps(origin)+''';
 globalThis.fetch=(input,options)=>{
  const url=new URL(typeof input==='string'?input:input.url||String(input),document.baseURI);
  if(url.href.startsWith(base)){
   const name=url.href.slice(base.length);
   if(assets[name])return Promise.resolve(new Response(assets[name],{headers:{'Content-Type':name.endsWith('.wasm')?'application/wasm':'application/octet-stream'}}));
  }
  return originalFetch(input,options);
 };
 globalThis.EmberDiagnosticTest='runpod';
 const decode=n=>new TextDecoder().decode(assets[n]);
 let html=decode('index.html').replace('<head>','<head><base href="'+base+'">');
 for(const name of ['ember_core_bridge.js','index.js']){
  let source=decode(name);
  if(name==='ember_core_bridge.js')source=source.replace('document.currentScript.src',JSON.stringify(base+name));
  const blob=URL.createObjectURL(new Blob([source],{type:'text/javascript'}));
  html=html.replace('src="'+name+'"','src="'+blob+'"');
 }
 document.open();document.write(html);document.close();return true;
 })()''')
 return hashes
