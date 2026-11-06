const source=await Deno.readTextFile(new URL('../adapters/web/ember_core_bridge.js',import.meta.url));
const check=(ok,message)=>{if(!ok)throw new Error(message);};
Deno.test('Social observation is bounded, immutable and has no input controls',()=>{
 const scope={};new Function('globalThis',source.slice(source.indexOf('// Read-only client-side observations')))(scope);
 const api=scope.EmberSocialObserver;
 check(Object.isFrozen(api)&&Object.keys(api).sort().join(',')==='publish,snapshot','observer exposed controls');
 const value={localSlot:2,names:['Terra','Rae'],messages:[{id:1,slot:2,name:'Rae',text:'<b>literal</b>'}],composing:false,available:true};
 api.publish(JSON.stringify(value));const before=api.snapshot();
 check(Object.isFrozen(before)&&Object.isFrozen(before.names)&&Object.isFrozen(before.messages)&&Object.isFrozen(before.messages[0]),'mutable observations');
 for(const bad of ['{',JSON.stringify({...value,messages:new Array(101).fill(value.messages[0])}),JSON.stringify({...value,names:['x']}),JSON.stringify({...value,messages:[{id:1,slot:3,name:'x',text:'bad'}]})])api.publish(bad);
 check(api.snapshot()===before,'invalid state replaced valid observation');
 check(api.snapshot().messages[0].text==='<b>literal</b>','observer interpreted text');
});
