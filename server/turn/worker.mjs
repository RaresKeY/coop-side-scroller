// No packages. Account credentials never enter this Worker; only a scoped TURN key.
const ORIGINS = new Set(['https://rareskey.github.io','http://127.0.0.1:27841']);
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
export async function handle(request,env,fetcher=(url,options)=>fetch(url,options)) {
 const origin=request.headers.get('Origin');
 const headers={'Cache-Control':'no-store, private','Vary':'Origin','Content-Type':'application/json','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
 const reply=(status,error,extra={})=>Response.json({error,...extra},{status,headers});
 if(!ORIGINS.has(origin))return reply(403,'origin_denied');
 headers['Access-Control-Allow-Origin']=origin;
 const lobby=new URL(request.url).pathname==='/v1/lobby';
 if(!lobby && new URL(request.url).pathname!=='/v1/ice')return reply(404,'not_found');
 if(request.method==='OPTIONS') {
  if(request.headers.get('Access-Control-Request-Method')!=='POST')return reply(405,'method_denied');
  const requested=(request.headers.get('Access-Control-Request-Headers')||'').toLowerCase().split(',').map(s=>s.trim()).filter(Boolean);
  if(requested.some(h=>h!=='authorization' && !(lobby && h==='content-type')))return reply(403,'headers_denied');
  return new Response(null,{status:204,headers:{...headers,'Access-Control-Allow-Methods':'POST','Access-Control-Allow-Headers':lobby?'Authorization, Content-Type':'Authorization','Access-Control-Max-Age':'600'}});
 }
 if(request.method!=='POST')return reply(405,'method_denied');
 if(!env.TURN_KEY_ID || !env.TURN_KEY_TOKEN || !env.PLAYTEST_TOKEN || !env.ISSUE_LIMIT || !env.TOTAL_LIMIT)return reply(503,'issuer_not_configured');
 // Per-IP limits mitigate unauthenticated attempts; shared invitation limit bounds use.
 try {
  const limiter=lobby?env.LOBBY_LIMIT:env.ISSUE_LIMIT;
  if(!limiter)return reply(503,'limiter_unavailable');
  if(!(await limiter.limit({key:`ip:${request.headers.get('CF-Connecting-IP')||'unknown'}`})).success)return reply(429,'rate_limited');
 } catch {return reply(503,'limiter_unavailable');}
 const authorization=request.headers.get('Authorization')||'';
 if(authorization.length>512 || !authorization.startsWith('Bearer ') || !await equalSecret(authorization.slice(7),env.PLAYTEST_TOKEN))return reply(401,'access_denied');
 const now=Math.floor(Date.now()/1000);
 if(!Number.isSafeInteger(Number(env.INVITE_EXPIRES_AT)) || now>=Number(env.INVITE_EXPIRES_AT))return reply(403,'invitation_expired');
 if(lobby) {
  if(!env.LOBBIES || !env.LOBBY_TOTAL)return reply(503,'lobby_not_configured');
  try {if(!(await env.LOBBY_TOTAL.limit({key:'private-lobbies'})).success)return reply(429,'rate_limited');}
  catch{return reply(503,'limiter_unavailable');}
  let data;try{data=await readBounded(request);}catch{return reply(400,'invalid_lobby_request');}
  try {
   const stub=env.LOBBIES.get(env.LOBBIES.idFromName('private-playtest-v1'));
   const result=await stub.fetch(new Request('https://lobby.internal/',{method:'POST',body:JSON.stringify(data)}));
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
export default {fetch:(request,env)=>handle(request,env)};

// One SQLite Durable Object serializes the small private room directory.
// No gameplay, account credentials, peer addresses or identity are stored here.
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
  if(Object.keys(rooms).length)await this.state.storage.setAlarm(now+ROOM_IDLE_MS);
  else await this.state.storage.deleteAlarm();
 }
 async fetch(request) {
  // blockConcurrencyWhile also spans storage awaits: two simultaneous joins
  // cannot both reserve the guest slot. Failed requests cannot alter the store.
  return this.state.blockConcurrencyWhile(async()=>{
   let data;try{data=await readBounded(request);}catch{return Response.json({error:'invalid_request'},{status:400});}
   return this.apply(data,Date.now());
  });
 }
 async apply(data,now) {
  const reply=(status,error)=>Response.json({error},{status});
  if(!data || typeof data!=='object'||Array.isArray(data)||data.version!==1||!['list','create','join','sync','leave'].includes(data.action))return reply(400,'invalid_request');
  const {rooms,stored,legacy}=await this.loadRooms();
  let pruned=false;
  for(const [id,room] of Object.entries(rooms))if(now>=room.expires||now-room.hostSeen>=ROOM_IDLE_MS||(room.guest && now-room.guestSeen>=ROOM_IDLE_MS)){delete rooms[id];pruned=true;}
  const save=()=>this.saveRooms(rooms,stored,legacy,now);
  if(data.action==='list') {
   if(pruned||legacy)await save();
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
  if(data.action==='leave') {delete rooms[data.id];await save();return Response.json({version:1,closed:true});}
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
  const result={version:1,id:data.id,players:room.guest?2:1,signal:host?room.answer:room.offer,complete:room.hostReady&&room.guestReady};
  // Signaling ends once both browsers are connected. Gameplay keeps running.
  if(result.complete)delete rooms[data.id];
  await save();return Response.json(result);
 }
 async alarm() {
  await this.state.blockConcurrencyWhile(async()=>{
   const now=Date.now();
   const {rooms,stored,legacy}=await this.loadRooms();
   for(const [id,r] of Object.entries(rooms))if(now>=r.expires||now-r.hostSeen>=ROOM_IDLE_MS||(r.guest&&now-r.guestSeen>=ROOM_IDLE_MS))delete rooms[id];
   await this.saveRooms(rooms,stored,legacy,now);
  });
 }
}
