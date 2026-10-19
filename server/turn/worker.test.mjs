import {handle,publicServers,TTL} from './worker.mjs';
const check=(value,message)=>{if(!value)throw new Error(message);};
const origin='https://rareskey.github.io';
const env=()=>({TURN_KEY_ID:'key',TURN_KEY_TOKEN:'master-never-public',PLAYTEST_TOKEN:'private-invitation',INVITE_EXPIRES_AT:String(Math.floor(Date.now()/1000)+600),ISSUE_LIMIT:{limit:()=>({success:true})},TOTAL_LIMIT:{limit:()=>({success:true})}});
const request=(options={})=>new Request('https://issuer.example/v1/ice',{method:'POST',headers:{Origin:origin,Authorization:'Bearer private-invitation',...options.headers},...options});
const credentials={iceServers:[{urls:['stun:stun.cloudflare.com:3478','stun:stun.cloudflare.com:53']},{urls:['turn:turn.cloudflare.com:3478?transport=udp','turns:turn.cloudflare.com:443?transport=tcp'],username:'temporary-user',credential:'temporary-password'}]};
let calls=0;
const upstream=async(url,options)=>{calls++;check(url.startsWith('https://rtc.live.cloudflare.com/'),'wrong API host');check(options.redirect==='manual','Workers must refuse redirects without unsupported error mode');check(JSON.parse(options.body).ttl===TTL,'caller-controlled TTL');check(options.headers.Authorization==='Bearer master-never-public','wrong upstream token');return Response.json(credentials);};
Deno.test('Authenticated issuance returns only temporary ICE and no-store CORS',async()=>{
 const response=await handle(request(),env(),upstream);check(response.status===200,'issuance failed');
 const text=await response.text();check(!text.includes('master-never-public')&&!text.includes('private-invitation'),'secret leaked');
 check(!text.includes(':53'),'blocked port 53 retained');check(response.headers.get('Cache-Control').includes('no-store'),'cached secret');check(response.headers.get('Access-Control-Allow-Origin')===origin,'wrong CORS');
 const data=JSON.parse(text);check(data.iceServers[1].credential==='temporary-password'&&data.expiresAt> Date.now()/1000,'missing expiring credential');
});
Deno.test('Origin, bearer, expiry, method, request body, path and rate failures never mint',async()=>{
 const cases=[
  [new Request('https://issuer.example/v1/ice',{method:'POST'}),env(),403],
  [request({headers:{Origin:origin}}),env(),401],
  [request(),{...env(),INVITE_EXPIRES_AT:'0'},403],
  [request({method:'GET'}),env(),405],
  [request({body:'{}'}),env(),400],
  [new Request('https://issuer.example/other',{method:'POST',headers:{Origin:origin}}),env(),404],
  [request(),{...env(),ISSUE_LIMIT:{limit:()=>({success:false})}},429],
  [request(),{...env(),TOTAL_LIMIT:{limit:()=>({success:false})}},429],
  [request(),{...env(),TURN_KEY_TOKEN:undefined},503],
 ];
 for(const [req,config,status] of cases){const before=calls;check((await handle(req,config,upstream)).status===status,`expected ${status}`);check(calls===before,'rejected request minted');}
});
Deno.test('Preflight allows only the known origin, POST and Authorization',async()=>{
 const response=await handle(request({method:'OPTIONS',headers:{Origin:origin,'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization'}}),env(),upstream);
 check(response.status===204,'preflight failed');
});
Deno.test('Provider failures are redacted and invalid provider ICE is rejected',async()=>{
 const response=await handle(request(),env(),async()=>new Response('master-never-public',{status:403}));
 check(response.status===502 && !((await response.text()).includes('master-never-public')),'provider secret leaked');
 let failed=false;try{publicServers([{urls:['turn:evil.invalid:3478'],username:'u',credential:'c'}]);}catch{failed=true;}check(failed,'arbitrary TURN host accepted');
 const broken=await handle(request(),env(),async()=>Response.json({iceServers:[]}));check(broken.status===502,'empty ICE accepted');
});

Deno.test('Redirects never forward the master credential',async()=>{
 let count=0;const result=await handle(request(),env(),async(_url,options)=>{count++;check(options.redirect==='manual','redirect following enabled');return new Response(null,{status:302,headers:{Location:'https://evil.invalid'}});});
 check(result.status===502 && count===1,'redirect was followed');
});
