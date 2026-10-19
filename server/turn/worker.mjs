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
 if(new URL(request.url).pathname!=='/v1/ice')return reply(404,'not_found');
 if(request.method==='OPTIONS') {
  if(request.headers.get('Access-Control-Request-Method')!=='POST')return reply(405,'method_denied');
  const requested=(request.headers.get('Access-Control-Request-Headers')||'').toLowerCase().split(',').map(s=>s.trim()).filter(Boolean);
  if(requested.some(h=>h!=='authorization'))return reply(403,'headers_denied');
  return new Response(null,{status:204,headers:{...headers,'Access-Control-Allow-Methods':'POST','Access-Control-Allow-Headers':'Authorization','Access-Control-Max-Age':'600'}});
 }
 if(request.method!=='POST')return reply(405,'method_denied');
 if(!env.TURN_KEY_ID || !env.TURN_KEY_TOKEN || !env.PLAYTEST_TOKEN || !env.ISSUE_LIMIT || !env.TOTAL_LIMIT)return reply(503,'issuer_not_configured');
 // Per-IP limits mitigate unauthenticated attempts; shared invitation limit bounds use.
 try {
  if(!(await env.ISSUE_LIMIT.limit({key:`ip:${request.headers.get('CF-Connecting-IP')||'unknown'}`})).success)return reply(429,'rate_limited');
 } catch {return reply(503,'limiter_unavailable');}
 const authorization=request.headers.get('Authorization')||'';
 if(authorization.length>512 || !authorization.startsWith('Bearer ') || !await equalSecret(authorization.slice(7),env.PLAYTEST_TOKEN))return reply(401,'access_denied');
 const now=Math.floor(Date.now()/1000);
 if(!Number.isSafeInteger(Number(env.INVITE_EXPIRES_AT)) || now>=Number(env.INVITE_EXPIRES_AT))return reply(403,'invitation_expired');
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
