// No packages. Account credentials never enter this Worker; only a scoped TURN key.
const ORIGINS = new Set(['https://rareskey.github.io','http://127.0.0.1:27841','https://ember-bridge-playtest.web.app','https://ember-bridge-playtest.firebaseapp.com']);
export const TTL = 3600;
const URL_PATTERN = /^(stun|turn|turns):(?:stun|turn)\.cloudflare\.com:(?:3478|5349|443|80)(?:\?transport=(?:udp|tcp))?$/;
const encoder = new TextEncoder();
async function equalSecret(a, b) {
 const [x,y] = await Promise.all([a,b].map(s => crypto.subtle.digest('SHA-256',encoder.encode(s))));
 const one=new Uint8Array(x),two=new Uint8Array(y);let difference=0;
 for(let i=0;i<one.length;i++)difference|=one[i]^two[i];
 return difference===0;
}
export function publicServers(value) {
 if(!Array.isArray(value) || value.length>16)throw new Error('Invalid ICE list');
 const result=[];
 for(const entry of value) {
  const urls=(Array.isArray(entry?.urls)?entry.urls:[entry?.urls]).filter(u=>typeof u==='string' && URL_PATTERN.test(u));
  if(!urls.length)continue; // Excludes browser-blocked port 53.
  const server={urls};
  if(urls.some(u=>u.startsWith('turn'))) {
   if(typeof entry.username!=='string'||!entry.username||entry.username.length>4096||typeof entry.credential!=='string'||!entry.credential||entry.credential.length>4096)throw new Error('Missing relay credential');
   server.username=entry.username;server.credential=entry.credential;
  }
  result.push(server);
 }
 if(!result.some(e=>e.username))throw new Error('No relay supplied');
 return result;
}
async function readBounded(response) {
 const reader=response.body.getReader();let size=0;const chunks=[];
 try {
  while(true) {
   const {done,value}=await reader.read();if(done)break;
   size+=value.length;if(size>65536)throw new Error('Response too large');chunks.push(value);
  }
 } finally { await reader.cancel().catch(()=>{}); }
 const bytes=new Uint8Array(size);let offset=0;
 for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
 return JSON.parse(new TextDecoder().decode(bytes));
}
async function handleRequest(request,env,fetcher=(url,options)=>fetch(url,options)) {
 const origin=request.headers.get('Origin');
 const headers={'Cache-Control':'no-store, private','Vary':'Origin','Content-Type':'application/json','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
 const reply=(status,error,extra={})=>Response.json({error,...extra},{status,headers});
 if(!ORIGINS.has(origin))return reply(403,'origin_denied');
 headers['Access-Control-Allow-Origin']=origin;
 const diagnostic=new URL(request.url).pathname==='/v1/diagnostics';
 const lobby=new URL(request.url).pathname==='/v1/lobby';
 if(!diagnostic && !lobby && new URL(request.url).pathname!=='/v1/ice')return reply(404,'not_found');
 if(request.method==='OPTIONS') {
  if(request.headers.get('Access-Control-Request-Method')!=='POST')return reply(405,'method_denied');
  const requested=(request.headers.get('Access-Control-Request-Headers')||'').toLowerCase().split(',').map(s=>s.trim()).filter(Boolean);
  if(requested.some(h=>h!=='authorization' && !((lobby||diagnostic) && h==='content-type')))return reply(403,'headers_denied');
  return new Response(null,{status:204,headers:{...headers,'Access-Control-Allow-Methods':'POST','Access-Control-Allow-Headers':(lobby||diagnostic)?'Authorization, Content-Type':'Authorization','Access-Control-Max-Age':'600'}});
 }
 if(request.method!=='POST')return reply(405,'method_denied');
 if(!env.TURN_KEY_ID || !env.TURN_KEY_TOKEN || !env.PLAYTEST_TOKEN || !env.ISSUE_LIMIT || !env.TOTAL_LIMIT)return reply(503,'issuer_not_configured');
 // Per-IP limits mitigate unauthenticated attempts; shared invitation limit bounds use.
 try {
  const limiter=diagnostic?env.DIAGNOSTIC_LIMIT:lobby?env.LOBBY_LIMIT:env.ISSUE_LIMIT;
  if(!limiter)return reply(503,'limiter_unavailable');
  if(!(await limiter.limit({key:`ip:${request.headers.get('CF-Connecting-IP')||'unknown'}`})).success)return reply(429,'rate_limited');
 } catch {return reply(503,'limiter_unavailable');}
 const authorization=request.headers.get('Authorization')||'';
 const operator=diagnostic && env.DIAGNOSTIC_READ_TOKEN && await equalSecret(authorization.slice(7),env.DIAGNOSTIC_READ_TOKEN);
 if(authorization.length>512 || !authorization.startsWith('Bearer ') || (!operator && !await equalSecret(authorization.slice(7),env.PLAYTEST_TOKEN)))return reply(401,'access_denied');
 const now=Math.floor(Date.now()/1000);
 if(!Number.isSafeInteger(Number(env.INVITE_EXPIRES_AT)) || now>=Number(env.INVITE_EXPIRES_AT))return reply(403,'invitation_expired');
 if(diagnostic) {
  let report;
  try {report=await readBounded(request);}catch{return reply(400,'invalid_diagnostics');}
  try {
   if(!env.DIAGNOSTIC_TOTAL || !(await env.DIAGNOSTIC_TOTAL.limit({key:'diagnostics'})).success)return reply(429,'rate_limited');
   const stub=env.LOBBIES.get(env.LOBBIES.idFromName('private-playtest-v1'));
   if(operator){
    if(!report||report.action!=='read'||(report.attempt!==undefined&&!/^[a-f0-9]{16}$/.test(report.attempt)))return reply(400,'invalid_diagnostics');
    const result=await stub.fetch(new Request('https://diagnostics.internal/',{method:'POST',body:JSON.stringify({action:'diagnostics_read',attempt:report.attempt})}));
    return new Response(result.body,{status:result.status,headers});
   }
   const clean=diagnosticReport(report);
   if(!clean)return reply(400,'invalid_diagnostics');
   console.log({kind:'browser',...clean});
   const saved=await stub.fetch(new Request('https://diagnostics.internal/',{method:'POST',body:JSON.stringify({action:'diagnostics_record',entry:{kind:'browser',...clean}})}));
   if(!saved.ok)return reply(503,'diagnostics_unavailable');
   return Response.json({version:1,accepted:true},{headers});
  } catch {return reply(503,'diagnostics_unavailable');}
 }
 if(lobby) {
  if(!env.LOBBIES || !env.LOBBY_TOTAL)return reply(503,'lobby_not_configured');
  try {if(!(await env.LOBBY_TOTAL.limit({key:'private-lobbies'})).success)return reply(429,'rate_limited');}
  catch{return reply(503,'limiter_unavailable');}
  let data;try{data=await readBounded(request);}catch{return reply(400,'invalid_lobby_request');}
  try {
   if(!['list','create','join','sync','leave'].includes(data?.action))return reply(400,'invalid_lobby_request');
   const stub=env.LOBBIES.get(env.LOBBIES.idFromName('private-playtest-v1'));
   const started=Date.now();
   const result=await stub.fetch(new Request('https://lobby.internal/',{method:'POST',body:JSON.stringify(data)}));
   const payload=await result.clone().json();
   const entry={kind:'lobby',action:['list','create','join','sync','leave'].includes(data.action)?data.action:'invalid',attempt:/^[a-f0-9]{16}$/.test(data.diagnostic)?data.diagnostic:'unknown',room:/^[A-F0-9]{8}$/.test(data.id)?data.id:(payload.id||''),status:result.status,code:payload.error||'ok',duration:Date.now()-started};
   console.log(entry);
   if(result.status!==200||['create','join','leave'].includes(data.action)||data.signal||data.ready)try{await stub.fetch(new Request('https://diagnostics.internal/',{method:'POST',body:JSON.stringify({action:'diagnostics_record',entry})}));}catch{}
   return new Response(result.body,{status:result.status,headers});
  } catch {return reply(503,'lobby_unavailable');}
 }
 if(request.body!==null) {
  const reader=request.body.getReader();
  try {const {value}=await reader.read();if(value?.length)return reply(400,'body_not_allowed');}
  finally {await reader.cancel().catch(()=>{});}
 }
 try {
  if(!(await env.TOTAL_LIMIT.limit({key:'invitation'})).success)return reply(429,'rate_limited');
 } catch {return reply(503,'limiter_unavailable');}
 let stage='fetch';
 const started=Date.now();const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),8000);
 try {
  const response=await fetcher(`https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`,{
   method:'POST',headers:{'Authorization':`Bearer ${env.TURN_KEY_TOKEN}`,'Content-Type':'application/json','User-Agent':'ember-coop-turn-issuer/1'},
   body:JSON.stringify({ttl:TTL}),redirect:'manual',signal:controller.signal,
  });
  if(!response.ok)return reply(502,'relay_provider_failed',{providerStatus:response.status});
  stage='parse';const payload=await readBounded(response);
  stage='normalize';
  return Response.json({version:1,iceServers:publicServers(payload.iceServers),expiresAt:Math.floor(started/1000)+TTL},{headers});
 } catch(error) {
  const message=String(error?.message||'').toLowerCase();
  const reason=['illegal invocation','invalid header','disallowed','aborted','timeout','fetch failed','redirect'].find(word=>message.includes(word))||'other';
  return reply(502,'relay_provider_failed',{stage,reason});
 }
 finally {clearTimeout(timer);}
}
export async function handle(request,env,fetcher) {
 const response=await handleRequest(request,env,fetcher);
 if(new URL(request.url).pathname==='/v1/ice' && request.method==='POST') {
  let code='ok';
  if(response.status!==200){try{code=(await response.clone().json()).error||'unknown_error';}catch{code='unknown_error';}}
  console.log({kind:'ice',status:response.status,code});
 }
 return response;
}
export default {fetch:(request,env)=>handle(request,env)};

// One SQLite Durable Object serializes the small private room directory.
// Rooms temporarily persist SDP/ICE, which can include peer addresses.
// No gameplay or account credentials are stored here.
const ROOM_IDLE_MS=90000, ROOM_LIFETIME_MS=600000, ROOM_LIMIT=32;
const SEAT=/^[a-f0-9]{32}$/;
const CODE=/^[A-F0-9]{8}$/;
function signalEnvelope(code,role) {
 if(typeof code!=='string'||code.length>65536)return null;
 try {
  const data=JSON.parse(atob(code));
  if(data.game!=='ember-coop'||data.version!==1||data.protocol!==1||!SEAT.test(data.session)||data.type!==(role==='host'?'offer':'answer'))return null;
  if(typeof data.sdp!=='string'||!data.sdp.startsWith('v=0')||data.sdp.length>32768||!Array.isArray(data.ice)||!data.ice.length||data.ice.length>64)return null;
  if(data.ice.some(c=>!Array.isArray(c)||c.length!==3||typeof c[0]!=='string'||c[0].length>256||!Number.isInteger(c[1])||c[1]<0||c[1]>65535||typeof c[2]!=='string'||!c[2].startsWith('candidate:')||c[2].length>4096))return null;
  return data;
 }catch{return null;}
}
export class PrivateLobbies {
 constructor(state) {this.state=state;}
 async cleanupEvent(id,reason) {
  const entry={kind:'room_cleanup',room:id,reason,at:Date.now()};
  console.log(entry);
  const entries=(await this.state.storage.get('diagnostics')||[]).filter(e=>Date.now()-e.at<7*86400000);
  entries.push(entry);
  while(entries.length>256||encoder.encode(JSON.stringify(entries)).length>262144)entries.shift();
  await this.state.storage.put('diagnostics',entries);
 }

 async loadRooms() {
  // Compatibility with the initial single-value prototype; existing sessions
  // survive the first upgrade. Per-room values stay below SQLite's 2 MB cap.
  const legacy=await this.state.storage.get('rooms');
  const stored=await this.state.storage.list({prefix:'room:',limit:ROOM_LIMIT+1});
  if(stored.size>ROOM_LIMIT)throw new Error('Directory capacity exceeded');
  const rooms={...(legacy||{})};
  for(const [key,room] of stored)rooms[key.slice(5)]=structuredClone(room);
  return {rooms,stored,legacy:!!legacy};
 }
 async saveRooms(rooms,stored,legacy,now) {
  const writes={};
  for(const [id,room] of Object.entries(rooms)) {
   const key='room:'+id;
   if(JSON.stringify(stored.get(key))!==JSON.stringify(room))writes[key]=room;
  }
  if(Object.keys(writes).length)await this.state.storage.put(writes);
  for(const key of stored.keys())if(!rooms[key.slice(5)])await this.state.storage.delete(key);
  if(legacy)await this.state.storage.delete('rooms');
  await this.scheduleAlarm(rooms,now);
 }
 async scheduleAlarm(rooms,now) {
  const deadlines=Object.values(rooms).flatMap(r=>[r.expires,r.hostSeen+ROOM_IDLE_MS,...(r.guest?[r.guestSeen+ROOM_IDLE_MS]:[])]);
  const entries=await this.state.storage.get('diagnostics');
  if(entries?.length)deadlines.push(entries[0].at+7*86400000);
  if(deadlines.length)await this.state.storage.setAlarm(Math.max(now+1,Math.min(...deadlines)));
  else await this.state.storage.deleteAlarm();
 }

 async fetch(request) {
  // blockConcurrencyWhile also spans storage awaits: two simultaneous joins
  // cannot both reserve the guest slot. Expiry cleanup also runs for rejected actions.
  return this.state.blockConcurrencyWhile(async()=>{
   let data;try{data=await readBounded(request);}catch{return Response.json({error:'invalid_request'},{status:400});}
   if(data.action==='diagnostics_read'||data.action==='diagnostics_record'){
    const entries=(await this.state.storage.get('diagnostics')||[]).filter(e=>Date.now()-e.at<7*86400000);
    if(data.action==='diagnostics_read'){
     const rooms=new Set(entries.filter(e=>e.attempt===data.attempt).flatMap(e=>[e.room,...(e.events||[]).map(x=>x.room)]).filter(Boolean));
     return Response.json({version:1,events:entries.filter(e=>!data.attempt||e.attempt===data.attempt||rooms.has(e.room)||(e.events||[]).some(x=>rooms.has(x.room))),limit:256,retentionDays:7});
    }
    if(data.action!=='diagnostics_record')return Response.json({error:'invalid_request'},{status:400});
    entries.push({...data.entry,at:Date.now()});
    while(entries.length>256||encoder.encode(JSON.stringify(entries)).length>262144)entries.shift();
    await this.state.storage.put('diagnostics',entries);
    await this.scheduleAlarm((await this.loadRooms()).rooms,Date.now());
    return Response.json({version:1});
   }
   return this.apply(data,Date.now());
  });
 }
 async apply(data,now) {
  const reply=(status,error)=>Response.json({error},{status});
  if(!data || typeof data!=='object'||Array.isArray(data)||data.version!==1||!['list','create','join','sync','leave'].includes(data.action))return reply(400,'invalid_request');
  const {rooms,stored,legacy}=await this.loadRooms();
  let pruned=false;
  for(const [id,room] of Object.entries(rooms))if(now>=room.expires||now-room.hostSeen>=ROOM_IDLE_MS||(room.guest && now-room.guestSeen>=ROOM_IDLE_MS)){await this.cleanupEvent(id,now>=room.expires?'lifetime':now-room.hostSeen>=ROOM_IDLE_MS?'host_lease':'guest_lease');delete rooms[id];pruned=true;}
  const save=()=>this.saveRooms(rooms,stored,legacy,now);
  if(pruned)await save();
  if(data.action==='list') {
   if(legacy&&!pruned)await save();
   return Response.json({version:1,rooms:Object.entries(rooms).filter(([,r])=>!r.guest).map(([id,r])=>({id,name:r.name,players:1,capacity:2,protocol:1}))});
  }
  if(typeof data.seat!=='string'||!SEAT.test(data.seat))return reply(400,'invalid_seat');
  if(data.action==='create') {
   // A client-generated random seat makes a retried creation idempotent.
   const existing=Object.entries(rooms).find(([,r])=>r.host===data.seat);
   if(existing)return Response.json({version:1,id:existing[0],role:'host'});
   if(Object.keys(rooms).length>=ROOM_LIMIT)return reply(429,'rooms_full');
   if(typeof data.name!=='string'||!data.name.trim()||data.name.length>32||/[\x00-\x1f\x7f]/.test(data.name))return reply(400,'invalid_name');
   let id;do{id=crypto.randomUUID().replaceAll('-','').slice(0,8).toUpperCase();}while(rooms[id]);
   rooms[id]={name:data.name.trim(),host:data.seat,guest:null,hostSeen:now,guestSeen:now,expires:now+ROOM_LIFETIME_MS,offer:'',answer:'',hostReady:false,guestReady:false};
   await save();return Response.json({version:1,id,role:'host'});
  }
  if(typeof data.id!=='string'||!CODE.test(data.id))return reply(400,'invalid_room');
  const room=rooms[data.id];
  if(!room){await save();return reply(404,'room_expired');}
  if(data.action==='join') {
   if(data.seat===room.host)return reply(409,'own_room');
   if(room.guest && room.guest!==data.seat)return reply(409,'room_full');
   room.guest=data.seat;room.guestSeen=now;await save();
   return Response.json({version:1,id:data.id,role:'client'});
  }
  const host=data.seat===room.host;
  if(!host && data.seat!==room.guest)return reply(403,'seat_denied');
  if(data.action==='leave') {await this.cleanupEvent(data.id,host?'host_leave':'guest_leave');delete rooms[data.id];await save();return Response.json({version:1,closed:true});}
  if(data.retryTls!==undefined && typeof data.retryTls!=='boolean')return reply(400,'invalid_request');
  if(data.epoch!==undefined && (!Number.isInteger(data.epoch)||data.epoch<0||data.epoch>1))return reply(400,'invalid_request');
  // One idempotent compatibility retry per room, authorized by seat membership.
  // Epoch fencing prevents in-flight UDP signals/readiness contaminating TLS.
  if(data.retryTls && !room.epoch) {
   room.epoch=1;room.offer='';room.answer='';room.hostReady=false;room.guestReady=false;
  }
  room[host?'hostSeen':'guestSeen']=now;
  if((data.epoch??0)!==(room.epoch??0)) {
   await save();return Response.json({version:1,id:data.id,players:room.guest?2:1,epoch:room.epoch??0,retrySupported:true,signal:'',complete:false});
  }
  if(data.ready!==undefined && typeof data.ready!=='boolean')return reply(400,'invalid_ready');
  if(data.signal!==undefined && data.signal!=='') {
   const envelope=signalEnvelope(data.signal,host?'host':'client');
   if(!envelope)return reply(400,'invalid_signal');
   const field=host?'offer':'answer';
   if(room[field] && room[field]!==data.signal)return reply(409,'signal_already_set');
   if(!host && (!room.offer||signalEnvelope(room.offer,'host').session!==envelope.session))return reply(409,'session_mismatch');
   room[field]=data.signal;
  }
  room[host?'hostSeen':'guestSeen']=now;
  if(data.ready)room[host?'hostReady':'guestReady']=true;
  const result={version:1,id:data.id,epoch:room.epoch??0,retrySupported:true,players:room.guest?2:1,signal:host?room.answer:room.offer,complete:room.hostReady&&room.guestReady};
  // Signaling ends once both browsers are connected. Gameplay keeps running.
  if(result.complete){await this.cleanupEvent(data.id,'connected');delete rooms[data.id];}
  await save();return Response.json(result);
 }
 async alarm() {
  await this.state.blockConcurrencyWhile(async()=>{
   const now=Date.now();
   const journal=(await this.state.storage.get('diagnostics')||[]).filter(e=>now-e.at<7*86400000);
   if(journal.length)await this.state.storage.put('diagnostics',journal);else await this.state.storage.delete('diagnostics');
   const {rooms,stored,legacy}=await this.loadRooms();
   for(const [id,r] of Object.entries(rooms))if(now>=r.expires||now-r.hostSeen>=ROOM_IDLE_MS||(r.guest&&now-r.guestSeen>=ROOM_IDLE_MS)){await this.cleanupEvent(id,now>=r.expires?'lifetime':now-r.hostSeen>=ROOM_IDLE_MS?'host_lease':'guest_lease');delete rooms[id];}
   await this.saveRooms(rooms,stored,legacy,now);
  });
 }
}

export function diagnosticReport(value) {
 if(!value || value.version!==1 || !['diagnostics-v1','diagnostics-v2','diagnostics-v3'].includes(value.build) || typeof value.attempt!=='string' || !/^[a-f0-9]{16}$/.test(value.attempt) || !Array.isArray(value.events) || !value.events.length || value.events.length>64)return null;
 if(Object.keys(value).some(k=>!['version','build','attempt','events',...(value.build==='diagnostics-v3'?['context']:[])].includes(k)))return null;
 const v3=value.build==='diagnostics-v3';
 if(v3){
  const c=value.context;
  if(!c||typeof c!=='object'||Array.isArray(c)||Object.keys(c).sort().join(',')!=='built,commit,dirty,payload,site,test')return null;
  if(typeof c.commit!=='string'||typeof c.payload!=='string'||!/^(?:[a-f0-9]{40}|unknown)$/.test(c.commit)||!/^(?:[a-f0-9]{64}|unknown)$/.test(c.payload)||typeof c.dirty!=='boolean')return null;
  if(typeof c.built!=='string'||!(c.built==='unknown'||/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(c.built)))return null;
  if(!['firebase','pages','local','other'].includes(c.site)||!['none','runpod','browser'].includes(c.test))return null;
 }
 const actions=['ice','list','create','join','sync','leave','unknown'];
 const codes=["access_denied","origin_denied","rate_limited","limiter_unavailable","issuer_not_configured","lobby_not_configured","lobby_unavailable","invalid_lobby_request","relay_provider_failed",'ok','unknown_error','room_expired','room_full','own_room','signal_already_set','session_mismatch','seat_denied','invitation_expired','invalid_request','invalid_seat','invalid_room','invalid_name','invalid_signal','invalid_ready','rooms_full'];
 const shapes={ice_candidates:['host','srflx','prflx','relay'],ice_stats_unavailable:[],ice_state:['gathering','ice'],ice_error:['server','code'],ice_stats:['host','srflx','prflx','relay','pairs','failed','checking','succeeded','requests','responses'],transport:['local','remote','protocol','rtt'],begin:[],leave:[],failure:['reason'],rtc:['state'],visibility:['visible'],summary:['rtt','rx','tx','gaps','actors'],http:['action','status','code'],room:['room'],rtc_begin:['route']};
 if(v3){shapes.lobby_end=['cause'];shapes.failure.push('source','state','established');shapes.network=['online'];shapes.transport.push('relayProtocol','relayPort',...['bytesSent','bytesReceived','packetsSent','packetsReceived'].flatMap(k=>[k,k+'PerSecond','transport'+k[0].toUpperCase()+k.slice(1),'transport'+k[0].toUpperCase()+k.slice(1)+'PerSecond']));}
 for(const event of value.events) {
  if(!event || typeof event!=='object' || Array.isArray(event) || typeof event.event!=='string' || !Object.hasOwn(shapes,event.event) || !['solo','host','client'].includes(event.role) || !Number.isInteger(event.ms) || event.ms<0 || event.ms>86400000)return null;
  if(Object.keys(event).some(k=>!['seq','event','ms','role',...shapes[event.event]].includes(k)))return null;
  for(const [key,v] of Object.entries(event)) {
   if(['event','ms','role'].includes(key))continue;
   if(key==='gathering'){if(!['new','gathering','complete','unknown'].includes(v))return null;}
   else if(key==='ice'){if(!['new','checking','connected','completed','disconnected','failed','closed','unknown'].includes(v))return null;}
   else if(key==='server'){if(!['stun','turn','turns','unknown'].includes(v))return null;}
   else if(key==='code'&&event.event==='ice_error'){if(!Number.isInteger(v)||v<0||v>65535)return null;}
   else if(key==='local'||key==='remote'){if(!['host','srflx','prflx','relay','unknown'].includes(v))return null;}
   else if(key==='protocol'){if(!['udp','tcp','unknown'].includes(v))return null;}
   else if(key==='relayProtocol'){if(!['udp','tcp','tls','unknown'].includes(v))return null;}
   else if(key==='relayPort'){if(![0,443].includes(v))return null;}
   else if(key==='source'){if(!['setup','multiplayer_disconnect','multiplayer_connect_failed','rtc_terminal','disconnect_timeout','connect_timeout','gather_timeout','lobby_errors'].includes(v))return null;}
   else if(key==='cause'){if(!['complete','error_after_connected'].includes(v))return null;}
   else if(key==='established'){if(typeof v!=='boolean')return null;}
   else if(key==='online'){if(typeof v!=='boolean')return null;}
   else if(key==='reason'){if(!['timeout','gathering','description','candidate','relay','connection','other'].includes(v))return null;}
   else if(key==='visible'){if(typeof v!=='boolean')return null;}
   else if(key==='room'){if(typeof v!=='string'||!/^[A-F0-9]{8}$/.test(v))return null;}
   else if(key==='action'){if(!actions.includes(v))return null;}
   else if(key==='code'){if(!codes.includes(v))return null;}
   else if(!Number.isInteger(v)||v< -1||v>2147483647)return null;
  }
 }
 return {version:1,build:value.build,attempt:value.attempt,events:value.events,...(v3?{context:value.context}:{})};
}
