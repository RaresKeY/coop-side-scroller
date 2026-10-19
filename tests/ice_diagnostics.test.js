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
 let selected=false;await helper.sample(()=>selected=true);
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
 const pending=helper.sample(()=>{throw Error('stale callback');});
 new scope.RTCPeerConnection();helper.drain();resolve(new Map());await pending;
 check(helper.drain()==='[]');
});

Deno.test('Gathered candidates are counted before connection without candidate strings',()=>{
 const {peer,helper}=fixture();const event=new Event('icecandidate');
 Object.assign(event,{candidate:{type:'host',candidate:'PRIVATE-CANDIDATE',address:'PRIVATE-IP'}});
 peer.dispatchEvent(event);const output=helper.drain();
 check(JSON.parse(output).some(e=>e.event==='ice_candidates'&&e.host===1));check(!output.includes('PRIVATE'));
});
