// No packages, imports, Node, network access or WASI required.
const root = new URL('../', import.meta.url);
const bytes = await Deno.readFile(new URL('build/wasm/ember_core.wasm', root));
const { module, instance } = await WebAssembly.instantiate(bytes, {});
const check = (condition, message) => { if (!condition) throw new Error(message); };
check(WebAssembly.Module.imports(module).length === 0, 'Wasm must have no imports');
const api = instance.exports;
check(api.ec_v1_abi_version() === 0x10000 && api.ec_v1_protocol_version() === 1, 'version mismatch');
check(api.ec_v1_create(0,1,1) === 0, 'incompatible ABI accepted');
const host = api.ec_v1_create(0x10000,1,1), guest = api.ec_v1_create(0x10000,2,2);
check(host && guest, 'handle allocation');
const cmd = (h, op, a=0, b=0) => api.ec_v1_command(h,op,a,b);
let hash = 2166136261;
const trace = [];
function transfer(source,target,sender) {
 let size;
 while ((size=cmd(source,7))>0) {
  check(cmd(target,4,sender,size)===0,'receive begin');
  for (let i=0;i<size;i++) {
   const value=cmd(source,8,i);trace.push(value);hash=Math.imul(hash^value,16777619)>>>0;
   check(cmd(target,5,i,value)===0,'receive byte');
  }
  check(cmd(target,6)===0,'receive message');check(cmd(source,9)===0,'consume message');
 }
 while(cmd(source,12)>0)cmd(source,13);
}
cmd(host,3,2,1);
for(let tick=0;tick<600;tick++) {
 cmd(guest,1,tick<144?1000:0,2);cmd(guest,2);transfer(guest,host,2);
 cmd(host,1,0,0);cmd(host,2);transfer(host,guest,1);
}
const result={hash,tick:cmd(host,10,0),hp:cmd(guest,10,1),guest_x:cmd(guest,10,3,2)};
const expectedBytes=await Deno.readFile(new URL('build/core-trace.bin',root));
check(expectedBytes.length===trace.length && trace.every((byte,index)=>byte===expectedBytes[index]),'native/Wasm message bytes differ');
const expected=JSON.parse(await Deno.readTextFile(new URL('build/core-trace.json',root)));
check(JSON.stringify(result)===JSON.stringify(expected),`native/Wasm trace differs: ${JSON.stringify(result)}`);
// Typed C view uses a caller-owned area beyond the exported static data/stack.
const scratch=Number(api.__heap_base.value);
check(scratch+116<=api.memory.buffer.byteLength,'caller buffer capacity');
check(api.ec_v1_read_view(guest,scratch,1)===-6,'small buffer accepted');
check(api.ec_v1_read_view(guest,scratch,116)===0,'typed C view copy');
const view=new DataView(api.memory.buffer,scratch,116);
check(view.getUint32(0,true)===116 && view.getUint32(8,true)===0,'view layout');
// Missing bytes cannot be supplied by an earlier stage, even on Wasm.
cmd(host,0,1,1);cmd(host,3,2,1);cmd(guest,0,2,2);cmd(guest,2);
const input=Array.from({length:cmd(guest,7)},(_,i)=>cmd(guest,8,i));
check(cmd(host,4,2,input.length)===0,'stage begin');
for(let i=0;i<input.length;i++) check(cmd(host,5,i,input[i])===0,'stage write');
check(cmd(host,6)===0,'complete stage');
input[8]++;
check(cmd(host,4,2,input.length)===0,'second stage begin');
for(let i=0;i<input.length-1;i++) { cmd(host,5,i,input[i]);cmd(host,5,i,input[i]); }
check(cmd(host,6)===-4,'incomplete stage accepted');
check(cmd(host,6)===-4,'stage replay accepted');
// Replica attack cues must not compare IDs across an observed actor leave.
cmd(host,0,1,1);cmd(guest,0,2,2);
const snapshot=()=>{for(let i=0;i<3;i++)cmd(host,2);transfer(host,guest,1);};
const events=(join,leave,attack)=>{
 const counts=[0,0,0];
 while(cmd(guest,12)>0){const type=cmd(guest,12,0),slot=cmd(guest,12,1);if(slot===2&&type<=3)counts[type-1]++;cmd(guest,13);}
 check(JSON.stringify(counts)===JSON.stringify([join,leave,attack]),'Wasm rejoin event mismatch');
};
const attack=()=>{cmd(guest,1,0,2);cmd(guest,2);transfer(guest,host,2);};
cmd(host,3,2,1);snapshot();events(1,0,0);
attack();snapshot();events(0,0,1);
cmd(host,3,2,0);snapshot();events(0,1,0);
cmd(host,3,2,1);snapshot();events(1,0,0);
attack();snapshot();events(0,0,1);
cmd(guest,0,2,2);snapshot();events(1,0,1);
api.ec_v1_destroy(guest);api.ec_v1_destroy(host);
console.log('Wasm ABI + native parity PASS', result);
