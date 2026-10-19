// Execute the production bridge's Wasm boot against the actual prepared module.
const source=await Deno.readTextFile(new URL('../adapters/web/ember_core_bridge.js',import.meta.url));
const bytes=await Deno.readFile(new URL('../build/wasm/ember_core.wasm',import.meta.url));
const boot=source.slice(source.indexOf('  const wasmURL'),source.indexOf('\n})();'));
const check=(x,m)=>{if(!x)throw Error(m);};
Deno.test('Destroy rejects coercible handles and preserves exact live ownership',async()=>{
 const scope={};
 new Function('globalThis','document','fetch',boot)(scope,{currentScript:{src:'https://example.invalid/bridge.js'}},()=>Promise.resolve(new Response(bytes)));
 const api=await scope.EmberCoreWebReady,h=api.create(),other=api.create();
 for(const invalid of [h+2**32,h-2**32,h+.5,String(h),NaN,Infinity,-Infinity,null,undefined,{},0]){
  api.destroy(invalid);
  check(api.command(h,14)===65536,'Invalid destroy released a live Wasm instance');
  check(api.command(other,14)===65536&&api.diagnostics().live===2,'Ownership registry corrupted');
 }
 api.destroy(h);api.destroy(h);
 check(api.command(h,14)===-1&&api.command(other,14)===65536&&api.diagnostics().live===1,'Exact/duplicate destroy corrupted ownership');
 api.destroy(other);check(api.diagnostics().live===0,'Live handle leaked');
});
