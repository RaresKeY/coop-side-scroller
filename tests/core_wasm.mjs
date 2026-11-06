// No packages, imports, Node, network access or WASI required.
const root = new URL('../', import.meta.url);
const bytes = await Deno.readFile(new URL('build/wasm/ember_core.wasm', root));
const { module, instance } = await WebAssembly.instantiate(bytes, {});
const check = (condition, message) => { if (!condition) throw new Error(message); };
check(WebAssembly.Module.imports(module).length === 0, 'Wasm must have no imports');
const api = instance.exports;
check(api.ec_v1_abi_version() === 0x10000 && api.ec_v1_protocol_version() === 3, 'version mismatch');
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
// Local movement and logical animation advance without waiting for a snapshot.
cmd(host,0,1,1);cmd(host,3,2,1);cmd(guest,0,2,2);snapshot();
for (let i=0;i<60;i++) {
 const x=cmd(guest,10,3,2), oldHost=cmd(host,10,3,2);
 cmd(guest,1,1000,i<45?1:0);cmd(guest,2);
 check(cmd(guest,10,3,2)===Math.min(936000,x+2833),'immediate Wasm local prediction');
 check(cmd(host,10,3,2)===oldHost,'prediction mutated host authority');
 if(i===0)check(cmd(guest,10,9,2)===2,'jump animation waited for authority');
 transfer(guest,host,2);cmd(host,2);transfer(host,guest,1);
 check(cmd(guest,10,3,2)===cmd(host,10,3,2),'Wasm reconciliation position');
 check(cmd(guest,10,4,2)===cmd(host,10,4,2),'Wasm reconciliation jump memory');
}
// Reproduce batched arrival and short loss bursts in the real Wasm instance.
for(const batch of [1,3,6,9])for(const loss of [false,true]){
 cmd(host,0,1,1);cmd(host,3,2,1);cmd(guest,0,2,2);
 let wire=[];
 const emit=(source,sender,tick)=>{
  let n;
  while((n=cmd(source,7))>0){
   const data=Array.from({length:n},(_,i)=>cmd(source,8,i));cmd(source,9);
   if(!loss||tick%37<12||tick%37>13)wire.push({due:Math.ceil((tick+5)/batch)*batch,sender,data});
  }
  while(cmd(source,12)>0)cmd(source,13);
 };
 for(let tick=0;tick<360;tick++){
  const due=wire.filter(p=>p.due<=tick);wire=wire.filter(p=>p.due>tick);
  for(const p of due){
   const before=[cmd(guest,10,3,2),cmd(guest,10,4,2),cmd(guest,10,9,2)];
   const target=p.sender===1?guest:host;
   check(cmd(target,4,p.sender,p.data.length)===0,'batched stage');
   for(let i=0;i<p.data.length;i++)cmd(target,5,i,p.data[i]);
   check(cmd(target,6)===0,'batched receive');
   if(p.sender===1&&tick>30)check(before.every((value,i)=>value===cmd(guest,10,[3,4,9][i],2)),'batched/lost snapshot corrected local trajectory');
  }
  cmd(guest,1,tick>=30&&tick<120?1000:tick>=160&&tick<220?-1000:0,(tick%53>=13&&tick%53<30?1:0)|(tick%101>=20&&tick%101<70?2:0));
  cmd(guest,2);emit(guest,2,tick);cmd(host,2);emit(host,1,tick);
 }
}
api.ec_v1_destroy(guest);api.ec_v1_destroy(host);
console.log('Wasm ABI + native parity PASS', result);
