import {handle,diagnosticReport} from './worker.mjs';
const check=(x,m='assertion failed')=>{if(!x)throw Error(m);};
const report=()=>({version:1,build:'diagnostics-v1',attempt:'a'.repeat(16),events:[{event:'http',ms:1,role:'host',action:'sync',status:404,code:'room_expired'}]});
Deno.test('Reports reject arbitrary text, credentials, addresses and unbounded events',()=>{
 check(diagnosticReport(report()));
 for(const change of [v=>v.token='secret',v=>v.events[0].sdp='private',v=>v.events[0].code='arbitrary response',v=>v.events[0].ms=Infinity,v=>v.events=Array(65).fill(v.events[0]),v=>v.attempt='bad']){
  const value=report();change(value);check(!diagnosticReport(value),'invalid report accepted');
 }
});
Deno.test('Diagnostic upload is authenticated, origin protected and independently rate limited',async()=>{
 const env={LOBBIES:{idFromName:x=>x,get:()=>({fetch:()=>Response.json({version:1})})},TURN_KEY_ID:'key',TURN_KEY_TOKEN:'master',PLAYTEST_TOKEN:'invitation',INVITE_EXPIRES_AT:String(Date.now()/1000+600|0),ISSUE_LIMIT:{limit:()=>({success:true})},TOTAL_LIMIT:{limit:()=>({success:true})},DIAGNOSTIC_LIMIT:{limit:()=>({success:true})},DIAGNOSTIC_TOTAL:{limit:()=>({success:true})}};
 const send=(value=report(),auth='invitation')=>handle(new Request('https://issuer.example/v1/diagnostics',{method:'POST',headers:{Origin:'https://rareskey.github.io',Authorization:'Bearer '+auth,'Content-Type':'application/json'},body:JSON.stringify(value)}),env);
 const captured=[],original=console.log;console.log=value=>captured.push(value);
 try{
  check((await send()).status===200);check(captured[0].attempt===report().attempt);
  check(!JSON.stringify(captured).includes('invitation'));
  check((await send(report(),'wrong')).status===401);
  check((await send({...report(),token:'secret'})).status===400);
  env.DIAGNOSTIC_LIMIT.limit=()=>({success:false});check((await send()).status===429);
 }finally{console.log=original;}
});
Deno.test('Failed ICE reports accept bounded enums/counts but reject private server details',()=>{
 const value=report();value.build='diagnostics-v2';
 value.events=[
  {event:'ice_error',ms:0,role:'client',server:'turns',code:701},
  {event:'ice_state',ms:1,role:'client',gathering:'complete',ice:'failed'},
  {event:'ice_stats',ms:2,role:'client',host:1,srflx:0,prflx:0,relay:0,pairs:1,failed:1,checking:0,succeeded:0,requests:7,responses:0},
  {event:'ice_stats_unavailable',ms:3,role:'client'},
 ];
 check(diagnosticReport(value));
 for(const change of [v=>v.events[0].url='turn:PRIVATE',v=>v.events[0].code=65536,v=>v.events[1].ice='PRIVATE',v=>v.events[2].failed=-2]){
  const invalid=structuredClone(value);change(invalid);check(!diagnosticReport(invalid));
 }
});

Deno.test('Diagnostic malformed bodies differ from storage outages on each hosted origin',async()=>{
 const env={TURN_KEY_ID:'key',TURN_KEY_TOKEN:'master',PLAYTEST_TOKEN:'invitation',INVITE_EXPIRES_AT:String(Math.floor(Date.now()/1000)+600),ISSUE_LIMIT:{},TOTAL_LIMIT:{},DIAGNOSTIC_LIMIT:{limit:()=>({success:true})},DIAGNOSTIC_TOTAL:{limit:()=>({success:true})},LOBBIES:{idFromName:x=>x,get:()=>({fetch:()=>{throw Error('private storage failure');}})}};
 for(const origin of ['https://rareskey.github.io','https://ember-bridge-playtest.web.app','https://ember-bridge-playtest.firebaseapp.com']){
  const send=body=>handle(new Request('https://issuer.example/v1/diagnostics',{method:'POST',headers:{Origin:origin,Authorization:'Bearer invitation'},body}),env);
  const malformed=await send('{');check(malformed.status===400);
  const outage=await send(JSON.stringify(report()));check(outage.status===503);
  check((await outage.json()).error==='diagnostics_unavailable');
  check(outage.headers.get('Access-Control-Allow-Origin')===origin);
 }
});

Deno.test('Inherited event names are invalid reports, never service errors',()=>{
 for(const event of ['toString','constructor','__proto__']){
  const v=report();v.events[0].event=event;check(diagnosticReport(v)===null);
 }
});
Deno.test('V3 preserves release identity and bounded route evidence without arbitrary metadata',()=>{
 const v=report();v.build='diagnostics-v3';
 v.context={commit:'a'.repeat(40),payload:'b'.repeat(64),built:'2026-10-19T18:00:00Z',dirty:true,site:'firebase',test:'runpod'};
 v.events=[{event:'network',ms:0,role:'host',online:false},{event:'transport',ms:10,role:'host',local:'relay',remote:'relay',protocol:'udp',relayProtocol:'tls',relayPort:443,rtt:-1,bytesSent:100,bytesSentPerSecond:-1,transportBytesReceived:200,transportBytesReceivedPerSecond:100}];
 check(diagnosticReport(v)?.context.payload===v.context.payload);
 for(const change of [x=>x.context.url='private',x=>x.context.commit=['a'.repeat(40)],x=>x.events[0].event=['network'],x=>x.context.commit='secret',x=>x.context.test='arbitrary',x=>x.context.site='private-host',x=>x.events[1].relayPort=12345,x=>x.events[0].online=1]){
  const invalid=structuredClone(v);change(invalid);check(!diagnosticReport(invalid));
 }
 const legacy=structuredClone(v);legacy.build='diagnostics-v2';delete legacy.context;check(!diagnosticReport(legacy));
});

Deno.test('V3 distinguishes completed signaling from terminal transport failures',()=>{
 const v=report();v.build='diagnostics-v3';
 v.context={commit:'unknown',payload:'unknown',built:'unknown',dirty:true,site:'local',test:'browser'};
 v.events=[{event:'lobby_end',ms:0,role:'client',cause:'error_after_connected'},
  {event:'failure',ms:10001,role:'client',reason:'connection',source:'disconnect_timeout',state:3,established:true}];
 check(diagnosticReport(v));
 for(const edit of [x=>x.events[0].cause='private',x=>x.events[1].source='private',x=>x.events[1].established='yes']){
  const bad=structuredClone(v);edit(bad);check(!diagnosticReport(bad));
 }
});
