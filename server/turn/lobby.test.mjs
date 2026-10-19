import {handle,PrivateLobbies} from './worker.mjs';
const check=(value,message='assertion failed')=>{if(!value)throw new Error(message);};
function fixture() {
 const store=new Map();let alarm=null,queue=Promise.resolve();
 const state={storage:{get:async k=>structuredClone(store.get(k)),list:async({prefix,limit})=>new Map([...store].filter(([k])=>k.startsWith(prefix)).slice(0,limit).map(([k,v])=>[k,structuredClone(v)])),put:async(k,v)=>{const entries=typeof k==='string'?{[k]:v}:k;for(const [key,value] of Object.entries(entries)){check(new TextEncoder().encode(JSON.stringify(value)).length<2000000,'SQLite value limit exceeded');store.set(key,structuredClone(value));}},delete:async k=>store.delete(k),setAlarm:async t=>{alarm=t;},deleteAlarm:async()=>{alarm=null;}},blockConcurrencyWhile:fn=>{const next=queue.then(fn);queue=next.catch(()=>{});return next;}};
 const object=new PrivateLobbies(state);
 const env={TURN_KEY_ID:'key',TURN_KEY_TOKEN:'master',PLAYTEST_TOKEN:'test-private',INVITE_EXPIRES_AT:String(Date.now()/1000+600|0),ISSUE_LIMIT:{limit:()=>({success:true})},TOTAL_LIMIT:{limit:()=>({success:true})},LOBBY_LIMIT:{limit:()=>({success:true})},LOBBY_TOTAL:{limit:()=>({success:true})},LOBBIES:{idFromName:x=>x,get:()=>object}};
 const call=async(data,extra={})=>{const r=await handle(new Request('https://issuer.example/v1/lobby',{method:'POST',headers:{Origin:'https://rareskey.github.io',Authorization:'Bearer test-private',...extra},body:JSON.stringify({version:1,...data})}),env);return [r.status,await r.json()];};
 return {call,object,store,env,alarm:()=>alarm};
}
const host='1'.repeat(32),guest='2'.repeat(32),third='3'.repeat(32);
const signal=(type,session='a'.repeat(32))=>btoa(JSON.stringify({game:'ember-coop',version:1,protocol:1,session,type,sdp:'v=0\r\n',ice:[['0',0,'candidate:fixture']]}));
Deno.test('Every lobby action requires a valid key/origin/expiry and limiter, never mints TURN',async()=>{
 const f=fixture();
 for(const action of ['list','create','join','sync','leave']) {
  check((await f.call({action},{Authorization:'Bearer wrong'}))[0]===401);
  check((await f.call({action},{Origin:'https://evil.example'}))[0]===403);
 }
 f.env.INVITE_EXPIRES_AT='0';check((await f.call({action:'list'}))[0]===403);
 f.env.INVITE_EXPIRES_AT=String(Date.now()/1000+600|0);
 f.env.LOBBY_LIMIT.limit=()=>({success:false});check((await f.call({action:'list'}))[0]===429);
});
Deno.test('Atomic two-player join, idempotent creation, safe listing and seat ownership',async()=>{
 const f=fixture();const [status,room]=await f.call({action:'create',seat:host,name:'Friends'});check(status===200);
 check((await f.call({action:'create',seat:host,name:'Retry'}))[1].id===room.id);
 const list=(await f.call({action:'list'}))[1];check(list.rooms.length===1);check(!JSON.stringify(list).includes(host));
 const joins=await Promise.all([guest,third].map(seat=>f.call({action:'join',id:room.id,seat})));
 check(joins.filter(r=>r[0]===200).length===1&&joins.filter(r=>r[0]===409).length===1);
 const rejectedSeat=joins[0][0]===409?guest:third;
 check((await f.call({action:'list'}))[1].rooms.length===0);
 check((await f.call({action:'sync',id:room.id,seat:rejectedSeat}))[0]===403);
 check((await f.call({action:'leave',id:room.id,seat:rejectedSeat}))[0]===403);
});
Deno.test('Offer/answer automatic exchange validates role/session and purges after both ready',async()=>{
 const f=fixture();const room=(await f.call({action:'create',seat:host,name:'Friends'}))[1];
 await f.call({action:'join',id:room.id,seat:guest});
 const sync=(seat,extra={})=>f.call({action:'sync',id:room.id,seat,...extra});
 check((await sync(host,{signal:signal('answer')}))[0]===400);
 check((await sync(host,{signal:signal('offer')}))[0]===200);
 check((await sync(guest))[1].signal===signal('offer'));
 check((await sync(guest,{signal:signal('answer','b'.repeat(32))}))[0]===409);
 check((await sync(guest,{signal:signal('answer')}))[0]===200);
 check((await sync(host))[1].signal===signal('answer'));
 check((await sync(host,{signal:signal('offer','c'.repeat(32))}))[0]===409);
 check((await sync(host,{ready:true}))[1].complete===false);
 check((await sync(guest,{ready:true}))[1].complete===true);
 check((await sync(host))[0]===404);check([...f.store.keys()].filter(k=>k.startsWith('room:')).length===0);check(f.alarm()!==null);
});
Deno.test('Malformed/oversized signals, capacity, lease expiry, alarm cleanup and explicit leave',async()=>{
 const f=fixture();let room;
 for(let i=1;i<=32;i++)room=(await f.call({action:'create',seat:i.toString(16).padStart(32,'0'),name:'Room'}))[1];
 check((await f.call({action:'create',seat:'f'.repeat(32),name:'Full'}))[0]===429);
 check((await f.call({action:'sync',id:room.id,seat:(32).toString(16).padStart(32,'0'),signal:'x'.repeat(70000)}))[0]===400);
 for(const r of f.store.values())r.hostSeen=0;
 await f.object.alarm();check([...f.store.keys()].filter(k=>k.startsWith('room:')).length===0);check(f.alarm()!==null);
 room=(await f.call({action:'create',seat:host,name:'Leave'}))[1];
 check((await f.call({action:'leave',id:room.id,seat:host}))[0]===200);
 check((await f.call({action:'list'}))[1].rooms.length===0);
});

Deno.test('Guest lease and absolute setup lifetime expire even while host renews',async()=>{
 const f=fixture();
 for(const kind of ['guest','absolute']) {
  const room=(await f.call({action:'create',seat:host,name:'Lease'}))[1];
  await f.call({action:'join',id:room.id,seat:guest});
  const stored=f.store.get('room:'+room.id);
  if(kind==='guest')stored.guestSeen=0;else stored.expires=0;
  check((await f.call({action:'sync',id:room.id,seat:host}))[0]===404);
  check([...f.store.keys()].filter(k=>k.startsWith('room:')).length===0);
 }
});
Deno.test('Lobby preflight, shared limit and unavailable directory are bounded and redacted',async()=>{
 const f=fixture();
 const preflight=await handle(new Request('https://issuer.example/v1/lobby',{method:'OPTIONS',headers:{Origin:'https://rareskey.github.io','Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization,content-type'}}),f.env);
 check(preflight.status===204);
 f.env.LOBBY_TOTAL.limit=()=>({success:false});check((await f.call({action:'list'}))[0]===429);
 f.env.LOBBY_TOTAL.limit=()=>({success:true});
 f.env.LOBBIES.get=()=>{throw new Error('internal-secret');};
 const [status,body]=await f.call({action:'list'});check(status===503 && !JSON.stringify(body).includes('internal-secret'));
});

Deno.test('32 rooms with large valid offer/answer messages fit individual SQLite values',async()=>{
 const f=fixture();
 const large=type=>btoa(JSON.stringify({game:'ember-coop',version:1,protocol:1,session:'a'.repeat(32),type,sdp:'v=0'+ 'x'.repeat(32760),ice:Array.from({length:16},()=>['0',0,'candidate:'+ 'x'.repeat(900)])}));
 const offer=large('offer'),answer=large('answer');check(offer.length>60000&&offer.length<65536);
 for(let i=1;i<=32;i++) {
  const seat=i.toString(16).padStart(32,'0'),other=(100+i).toString(16).padStart(32,'0');
  const [status,room]=await f.call({action:'create',seat,name:'Capacity'});check(status===200);
  check((await f.call({action:'join',id:room.id,seat:other}))[0]===200);
  check((await f.call({action:'sync',id:room.id,seat,signal:offer}))[0]===200);
  check((await f.call({action:'sync',id:room.id,seat:other,signal:answer}))[0]===200);
 }
 const rooms=[...f.store].filter(([k])=>k.startsWith('room:')).map(([,r])=>r);
 check(rooms.length===32);check(rooms.reduce((n,r)=>n+r.offer.length+r.answer.length,0)>2000000);
});
Deno.test('Initial single-value records migrate without losing reserved seats or signals',async()=>{
 const f=fixture();const room=(await f.call({action:'create',seat:host,name:'Existing'}))[1];
 await f.call({action:'sync',id:room.id,seat:host,signal:signal('offer')});
 const existing=f.store.get('room:'+room.id);f.store.clear();f.store.set('rooms',{[room.id]:existing});
 check((await f.call({action:'list'}))[1].rooms[0].id===room.id);
 check(!f.store.has('rooms')&&f.store.has('room:'+room.id));
 check((await f.call({action:'join',id:room.id,seat:guest}))[0]===200);
 check((await f.call({action:'sync',id:room.id,seat:guest}))[1].signal===signal('offer'));
});
Deno.test('Operator journal read, browser isolation and correlated room cleanup',async()=>{
 const f=fixture();f.env.DIAGNOSTIC_READ_TOKEN='operator-only';f.env.DIAGNOSTIC_LIMIT={limit:()=>({success:true})};f.env.DIAGNOSTIC_TOTAL={limit:()=>({success:true})};
 const send=async(body,token='operator-only')=>{
  const response=await handle(new Request('https://issuer.example/v1/diagnostics',{method:'POST',headers:{Origin:'https://rareskey.github.io',Authorization:'Bearer '+token},body:JSON.stringify(body)}),f.env);
  return [response.status,await response.json()];
 };
 const report={version:1,build:'diagnostics-v1',attempt:'a'.repeat(16),events:[{event:'begin',ms:0,role:'solo'}]};
 check((await send(report,'test-private'))[0]===200);
 const [status,value]=await send({version:1,action:'read'});
 check(status===200,JSON.stringify(value));check(value.events.length===1,'Upload not retained');
 check((await send({action:'read'},'test-private'))[0]===400,'Playtester read journal');
});
Deno.test('Diagnostic journal bounds, expiry and reserved-action isolation',async()=>{
 const f=fixture();
 for(let i=0;i<270;i++)await f.object.fetch(new Request('https://diagnostics.internal/',{method:'POST',body:JSON.stringify({action:'diagnostics_record',entry:{kind:'lobby',attempt:'a'.repeat(16),status:404}})}));
 check(f.store.get('diagnostics').length===256,'Journal count bound failed');
 check((await f.call({action:'diagnostics_read'}))[0]===400,'Reserved journal action exposed');
 f.store.set('diagnostics',[{kind:'lobby',at:Date.now()-8*86400000}]);
 await f.object.alarm();check(!f.store.has('diagnostics'),'Old diagnostics retained');
});
