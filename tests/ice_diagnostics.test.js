// Execute only the browser diagnostic adapter against controllable local peers.
const source=await Deno.readTextFile(new URL('../adapters/web/ember_core_bridge.js',import.meta.url));
const bootstrap=source.slice(source.indexOf('  // Bounded ICE metadata'),source.indexOf('  const wasmURL'));
const check=(value,message='assertion failed')=>{if(!value)throw Error(message);};
class Peer extends EventTarget {
 iceGatheringState='gathering';iceConnectionState='checking';connectionState='connecting';
 stats=new Map();getStats(){return Promise.resolve(this.stats);}
}
const fixture=()=>{
 const scope={RTCPeerConnection:Peer};new Function('globalThis',bootstrap)(scope);
 return {scope,helper:scope.EmberConnectionDiagnostics,peer:new scope.RTCPeerConnection()};
};
Deno.test('Failed candidate checks are sampled without a selected pair or connection',async()=>{
 const {peer,helper}=fixture();
 peer.stats=new Map([['local',{type:'local-candidate',candidateType:'srflx',address:'PRIVATE-IP'}],['pair',{type:'candidate-pair',state:'failed',requestsSent:7,responsesReceived:0,localCandidateId:'PRIVATE-ID'}]]);
 let selected=false;await helper.sample(v=>selected=JSON.parse(v)!==null);
 const summary=JSON.parse(helper.drain()).find(e=>e.event==='ice_stats');
 check(!selected);check(summary.failed===1&&summary.srflx===1&&summary.requests===7&&summary.responses===0);
 check(!JSON.stringify(summary).includes('PRIVATE'));
});
Deno.test('Server failures retain only scheme/code, with bounded queue and fresh-peer isolation',()=>{
 const {peer,scope,helper}=fixture();
 const event=new Event('icecandidateerror');
 Object.assign(event,{url:'turns:PRIVATE-SERVER:443?credential=PRIVATE-TOKEN',address:'PRIVATE-IP',port:12345,errorText:'PRIVATE-DETAIL',errorCode:701});
 for(let i=0;i<100;i++)peer.dispatchEvent(event);
 const output=helper.drain(),events=JSON.parse(output);
 check(events.length===64);check(events[0].server==='turns'&&events[0].code===701);check(!output.includes('PRIVATE'));
 new scope.RTCPeerConnection();peer.dispatchEvent(event);
 check(!helper.drain().includes('ice_error'),'Old peer contaminated replacement');
 helper.reset();peer.dispatchEvent(event);check(helper.drain()==='[]');
});
Deno.test('Gathering failure state and stats rejection remain observable',async()=>{
 const {peer,helper}=fixture();
 peer.iceGatheringState='complete';peer.iceConnectionState='failed';peer.dispatchEvent(new Event('iceconnectionstatechange'));
 peer.getStats=()=>Promise.reject(Error('PRIVATE-EXCEPTION'));await helper.sample(()=>{});
 const output=helper.drain();check(output.includes('"ice":"failed"'));check(output.includes('ice_stats_unavailable'));check(!output.includes('PRIVATE'));
});
Deno.test('Delayed old stats cannot enter a new attempt',async()=>{
 const {peer,scope,helper}=fixture();let resolve;
 peer.getStats=()=>new Promise(done=>resolve=done);
 let stale='pending';const pending=helper.sample(v=>stale=JSON.parse(v));
 new scope.RTCPeerConnection();helper.drain();resolve(new Map());await pending;
 check(helper.drain()==='[]');check(stale===null,'Stale sample did not complete empty');
});

Deno.test('Gathered candidates are counted before connection without candidate strings',()=>{
 const {peer,helper}=fixture();const event=new Event('icecandidate');
 Object.assign(event,{candidate:{type:'host',candidate:'PRIVATE-CANDIDATE',address:'PRIVATE-IP'}});
 peer.dispatchEvent(event);const output=helper.drain();
 check(JSON.parse(output).some(e=>e.event==='ice_candidates'&&e.host===1));check(!output.includes('PRIVATE'));
});

Deno.test('TLS relay and counter rates distinguish relay transport from candidate UDP',async()=>{
 const {peer,helper}=fixture();
 const pair={id:'p',type:'candidate-pair',timestamp:1000,localCandidateId:'l',remoteCandidateId:'r',bytesSent:100,bytesReceived:200,packetsSent:3,packetsReceived:5};
 peer.stats=new Map([['t',{type:'transport',selectedCandidatePairId:'p'}],['p',pair],['l',{candidateType:'relay',protocol:'udp',relayProtocol:'tls',url:'turns:turn.cloudflare.com:443?transport=tcp',address:'PRIVATE'}],['r',{candidateType:'relay'}]]);
 let result;await helper.sample(v=>result=JSON.parse(v));
 check(result.protocol==='udp'&&result.relayProtocol==='tls'&&result.relayPort===443);
 check(result.bytesSentPerSecond===-1&&result.rtt===-1);
 Object.assign(pair,{timestamp:3000,bytesSent:500,bytesReceived:1000,packetsSent:7,packetsReceived:11});
 await helper.sample(v=>result=JSON.parse(v));
 check(result.bytesSentPerSecond===200&&result.packetsReceivedPerSecond===3);
 check(!JSON.stringify(result).includes('PRIVATE'));
 pair.id='replacement';pair.timestamp=4000;
 await helper.sample(v=>result=JSON.parse(v));check(result.bytesSentPerSecond===-1);
 pair.timestamp=5000;pair.bytesSent=1;delete pair.packetsSent;
 await helper.sample(v=>result=JSON.parse(v));check(result.bytesSentPerSecond===-1&&result.packetsSentPerSecond===-1&&result.packetsSent===-1);
});

Deno.test('Release context selects only build identity and enum site/test markers',()=>{
 const {scope,helper}=fixture();
 scope.EmberBuildInfo={commit:'a'.repeat(40),payload:'b'.repeat(64),built:'2026-10-19T18:00:00Z',dirty:true,private:'PRIVATE'};
 scope.location={hostname:'ember-bridge-playtest.web.app',href:'PRIVATE'};
 scope.EmberDiagnosticTest='runpod';
 const c=JSON.parse(helper.context());check(c.site==='firebase'&&c.test==='runpod'&&c.dirty&&c.payload==='b'.repeat(64));
 check(!helper.context().includes('PRIVATE'));
 scope.EmberBuildInfo.commit=['a'.repeat(40)];scope.EmberBuildInfo.payload=['b'.repeat(64)];
 const malformed=JSON.parse(helper.context());check(malformed.commit==='unknown'&&malformed.payload==='unknown');
 scope.location.hostname='PRIVATE';scope.EmberDiagnosticTest='PRIVATE';scope.EmberBuildInfo.commit='PRIVATE';
 const unknown=JSON.parse(helper.context());check(unknown.site==='other'&&unknown.test==='none'&&unknown.commit==='unknown');
});

Deno.test('Transport counters remain distinct when the selected pair has no inbound bytes',async()=>{
 const {peer,helper}=fixture();
 const t={id:'t',type:'transport',selectedCandidatePairId:'p',timestamp:1000,bytesSent:100,bytesReceived:200};
 const p={id:'p',type:'candidate-pair',timestamp:1000,bytesSent:100,bytesReceived:0};
 peer.stats=new Map([['t',t],['p',p]]);
 let sample;await helper.sample(v=>sample=JSON.parse(v));
 check(sample.bytesReceived===0&&sample.transportBytesReceived===200&&sample.transportBytesReceivedPerSecond===-1);
 t.timestamp=p.timestamp=2000;t.bytesReceived=600;p.bytesSent=t.bytesSent=300;
 await helper.sample(v=>sample=JSON.parse(v));
 check(sample.bytesReceivedPerSecond===0&&sample.transportBytesReceivedPerSecond===400&&sample.transportBytesSentPerSecond===200);
});

Deno.test('Out-of-order samples complete empty and cannot replace newer route baselines',async()=>{
 const {peer,helper}=fixture();const pending=[];peer.getStats=()=>new Promise(r=>pending.push(r));
 const stats=(id,t,n)=>new Map([['t',{id:'t',type:'transport',timestamp:t,selectedCandidatePairId:id}], [id,{id,type:'candidate-pair',timestamp:t,bytesSent:n}]]);
 let old,newer,last;
 const a=helper.sample(v=>old=JSON.parse(v)),b=helper.sample(v=>newer=JSON.parse(v));
 pending[1](stats('new',2000,200));await b;
 pending[0](stats('old',1000,100));await a;
 check(old===null&&newer.bytesSent===200);
 const c=helper.sample(v=>last=JSON.parse(v));pending[2](stats('new',3000,500));await c;
 check(last.bytesSentPerSecond===300,'Stale pair replaced the newer baseline');
 helper.reset();let empty='pending';await helper.sample(v=>empty=JSON.parse(v));check(empty===null);
});
