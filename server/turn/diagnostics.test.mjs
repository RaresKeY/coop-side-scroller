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
