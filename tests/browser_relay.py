#!/usr/bin/env python3
"""Two actual Godot Web instances through the live protected issuer and TURN.
Run under offscreen Gamescope. Invitation is read privately; never logged/saved.
This same-machine test proves relay use, not independent access networks.
"""
import argparse,functools,http.server,json,signal,subprocess,tempfile,threading,time,urllib.request
from pathlib import Path
from browser_cdp import CDP,QuietHandler
ROOT=Path(__file__).resolve().parents[1]
signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(SystemExit(143)))
INSTRUMENT='''globalThis.testPeers=[];globalThis.testHttp=[];globalThis.testDiagnosticHttp=[];globalThis.testDiagnosticEvents=[];globalThis.testDiagnosticReports=[];globalThis.EmberDiagnosticTest='browser';const nativeFetch=globalThis.fetch;globalThis.fetch=async(...args)=>{const r=await nativeFetch(...args);if(String(args[0]).includes('workers.dev'))testHttp.push(r.status);if(r.url.endsWith('/v1/diagnostics')){testDiagnosticHttp.push(r.status);try{const b=args[1]?.body;const text=typeof b==='string'?b:new TextDecoder().decode(b);const report=JSON.parse(text);testDiagnosticEvents.push(...report.events.map(e=>e.event));testDiagnosticReports.push({build:report.build,attempt:report.attempt,context:report.context,status:r.status,error:r.ok?null:(await r.clone().json()).error});}catch{}}if(r.url.endsWith('/v1/lobby')&&r.ok){const d=await r.clone().json();if(d.rooms)globalThis.testRoomList=d.rooms;if(d.id)globalThis.testRoomId=d.id;if(d.complete)globalThis.testRoomComplete=true;}return r;};const NativeRTC=globalThis.RTCPeerConnection;
globalThis.RTCPeerConnection=class extends NativeRTC {constructor(...args){super(...args);testPeers.push(this);}};'''
def diagnostic_uploads_ok(page):
 return page.evaluate("testDiagnosticReports.length===testDiagnosticHttp.length && testDiagnosticReports.some(r=>r.status===200) && testDiagnosticReports.filter(r=>r.status===400).length<=1 && testDiagnosticReports.every(r=>r.status===200 || (r.status===400 && r.build==='diagnostics-v3' && r.error==='invalid_diagnostics'))")

def wait_until(check,seconds=35):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=check()
  if value:return value
  time.sleep(.15)
 raise RuntimeError('Browser relay stage timed out')
def key(page,key,code,number,down=True):page.call('Input.dispatchKeyEvent',{'type':'keyDown' if down else 'keyUp','key':key,'code':code,'windowsVirtualKeyCode':number})
def type_text(page,text):
 for char in text:
  for kind in ['keyDown','keyUp']:
   page.call('Input.dispatchKeyEvent',{'type':kind,'key':char,'text':char if kind=='keyDown' else '', 'windowsVirtualKeyCode':ord(char.upper())})
 time.sleep(.15)
def enter_code(page,text):
 wait_until(lambda:page.evaluate("!!document.querySelector('[data-ember-paste]')"),3)
 page.call('Input.insertText',{'text':text})
 bounds=page.evaluate("(()=>{const r=document.querySelector('[data-ember-accept]').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()")
 page.click(bounds['x'],bounds['y'])
def run(lobby=False, url=None):
 token=json.loads((Path.home()/'.config/cloudflare-api/access-coop-side-scroller-issuer.json').read_text())['token']
 server=http.server.ThreadingHTTPServer(('127.0.0.1',27841),functools.partial(QuietHandler,directory=str(ROOT/'build/web')))
 threading.Thread(target=server.serve_forever,daemon=True).start();origin=url or 'http://127.0.0.1:27841'
 with tempfile.TemporaryDirectory(prefix='ember-relay-') as profile,(ROOT/'build/relay-browser.log').open('w') as log:
  browser=subprocess.Popen(['chromium','--ozone-platform=x11','--mute-audio','--no-first-run','--no-default-browser-check','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows','--remote-debugging-port=0','--remote-allow-origins=*',f'--user-data-dir={profile}','about:blank'],stdout=log,stderr=log)
  try:
   wait_until(lambda:(Path(profile)/'DevToolsActivePort').exists(),10)
   port=int((Path(profile)/'DevToolsActivePort').read_text().splitlines()[0]);base=f'http://127.0.0.1:{port}'
   control=CDP(json.load(urllib.request.urlopen(base+'/json/version'))['webSocketDebuggerUrl'])
   control.call('Browser.grantPermissions',{'origin':origin,'permissions':['clipboardReadWrite','clipboardSanitizedWrite']})
   pages=[]
   for role in ['host','guest']:
    target=control.call('Target.createTarget',{'url':'about:blank','newWindow':True})['targetId']
    tabs=json.load(urllib.request.urlopen(base+'/json/list'));page=CDP(next(t for t in tabs if t['id']==target)['webSocketDebuggerUrl'])
    page.call('Runtime.enable');page.call('Page.enable');page.call('Page.addScriptToEvaluateOnNewDocument',{'source':INSTRUMENT})
    page.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
    page.call('Page.navigate',{'url':origin});wait_until(lambda:page.evaluate('globalThis.EmberCoreWeb?.diagnostics().calls>100'))
    control.call('Target.activateTarget',{'targetId':target});time.sleep(.2);page.click(160,283);enter_code(page,token);page.click(180,317)
    page.click(160,378) # Second popup item: Relay only.
    if not lobby: page.click(160,354) # Advanced manual pairing.
    pages.append((target,page));print('SETUP',role,flush=True)
   host,guest=[item[1] for item in pages]
   if lobby:
    control.call('Target.activateTarget',{'targetId':pages[0][0]});host.click(160,216)
    wait_until(lambda:host.evaluate('testHttp.includes(200)'),12)
    time.sleep(.3);host.capture(ROOT/'build/lobby-directory.png')
    host.click(160,170)
    enter_code(host,'W'*32)
    host.click(160,201) # Create room.
    wait_until(lambda:host.evaluate('testPeers.length'),15)
    host.capture(ROOT/'build/lobby-waiting.png')
    control.call('Target.activateTarget',{'targetId':pages[1][0]});guest.click(160,216)
    wait_until(lambda:guest.evaluate('testHttp.includes(200)'),12)
    room_id=wait_until(lambda:host.evaluate('globalThis.testRoomId'),5)
    wait_until(lambda:guest.evaluate('globalThis.testRoomList?.some(r=>r.id==='+json.dumps(room_id)+')'),8)
    time.sleep(.2)
    for width,height in [(1920,1080),(1280,720),(960,540),(854,480)]:
     guest.call('Emulation.setDeviceMetricsOverride',{'width':width,'height':height,'deviceScaleFactor':1,'mobile':False})
     time.sleep(.15);guest.capture(ROOT/f'build/lobby-join-{width}.png')
    guest.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
    guest.capture(ROOT/'build/lobby-join.png')
    index=guest.evaluate('testRoomList.findIndex(r=>r.id==='+json.dumps(room_id)+')')
    assert 0<=index<3,'Test room outside visible rows; do not join another room'
    guest.click(160,285+index*36) # First room's Join button.
    wait_until(lambda:guest.evaluate('testPeers.length'),25)
    assert all(page.evaluate('testPeers.at(-1).getConfiguration().iceTransportPolicy')=='relay' for page in [host,guest])
    print('LOBBY AUTOMATIC SIGNALING',flush=True)
   else:
    control.call('Target.activateTarget',{'targetId':pages[0][0]});host.click(160,387)
    wait_until(lambda:host.evaluate('testPeers.length'),15)
    wait_until(lambda:host.evaluate('testPeers.length && testPeers.at(-1).iceGatheringState==="complete"'))
    assert host.evaluate('testPeers.at(-1).getConfiguration().iceTransportPolicy')=='relay','Relay-only UI selection failed'
    print('HOST RELAY READY',flush=True)
    for width,height in [(1920,1080),(1280,720),(960,540),(854,480)]:
     host.call('Emulation.setDeviceMetricsOverride',{'width':width,'height':height,'deviceScaleFactor':1,'mobile':False})
     time.sleep(.15);host.capture(ROOT/f'build/pairing-host-{width}.png')
    host.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})

    # Godot's actual Copy/Paste buttons exchange its versioned codes in memory.
    host.click(90,185);time.sleep(.2)
    offer=host.evaluate('navigator.clipboard.readText()');assert len(offer)>100,'No offer copied'
    control.call('Target.activateTarget',{'targetId':pages[1][0]});guest.click(160,421)
    guest.click(240,185);enter_code(guest,offer)
    wait_until(lambda:guest.evaluate('testPeers.length && testPeers.at(-1).iceGatheringState==="complete"'))
    guest.click(90,185);time.sleep(.2);answer=guest.evaluate('navigator.clipboard.readText()');assert answer!=offer and len(answer)>100,'No answer copied'
    control.call('Target.activateTarget',{'targetId':pages[0][0]});host.click(240,185);enter_code(host,answer)
    print('CODES EXCHANGED',flush=True)
   for page in [host,guest]:wait_until(lambda:page.evaluate('testPeers.at(-1).connectionState==="connected"'))
   wait_until(lambda:all(page.evaluate('EmberCoreWeb.diagnostics().views[0].actors===2') for page in [host,guest]))
   control.call('Target.activateTarget',{'targetId':pages[1][0]});guest.click(800,420)
   key(guest,'d','KeyD',68)
   wait_until(lambda:guest.evaluate('EmberCoreWeb.diagnostics().views[0].guestX>=640000'),8)
   key(guest,'d','KeyD',68,False);guest.click(800,420);key(guest,'f','KeyF',70)
   wait_until(lambda:all(page.evaluate('EmberCoreWeb.diagnostics().views[0].hp<12') for page in [host,guest]),5)
   key(guest,'f','KeyF',70,False)
   reports=[]
   for page in [host,guest]:
    def selected_route():
     report=page.evaluate('''(async()=>{const p=testPeers.at(-1),s=await p.getStats();const transport=[...s.values()].find(x=>x.type==='transport'&&x.selectedCandidatePairId);const pair=s.get(transport?.selectedCandidatePairId)||[...s.values()].find(x=>x.type==='candidate-pair'&&x.state==='succeeded'&&x.nominated);return {policy:p.getConfiguration().iceTransportPolicy,state:p.connectionState,local:s.get(pair?.localCandidateId)?.candidateType,remote:s.get(pair?.remoteCandidateId)?.candidateType,bytesSent:pair?.bytesSent,bytesReceived:pair?.bytesReceived,transportBytesSent:transport?.bytesSent,transportBytesReceived:transport?.bytesReceived,rttMs:1000*(pair?.currentRoundTripTime||0),core:EmberCoreWeb.diagnostics().views[0]};})()''')
     return report if report.get('local')=='relay' and report.get('remote')=='relay' and report.get('transportBytesReceived',0)>0 and report.get('transportBytesSent',0)>0 else None
    report=wait_until(selected_route,8)
    reports.append(report)
   if lobby:wait_until(lambda:any(page.evaluate('globalThis.testRoomComplete===true') for page in [host,guest]),8)
   assert not host.errors and not guest.errors,'Browser console errors (details withheld)'
   host.capture(ROOT/'build/relay-host.png');guest.capture(ROOT/'build/relay-guest.png')
   # Production helper exposes only selected route metadata, not candidate addresses.
   for page in [host,guest]:
    page.evaluate("globalThis.routeDiagnostic=null;EmberConnectionDiagnostics.sample(value=>routeDiagnostic=JSON.parse(value));true")
    selected=wait_until(lambda:page.evaluate('globalThis.routeDiagnostic'),5)
    assert selected['local']=='relay' and selected['remote']=='relay',selected
    wait_until(lambda:page.evaluate('globalThis.testDiagnosticHttp.includes(200)'),12)
    assert diagnostic_uploads_ok(page), 'Diagnostic upload failed'
   # Force a terminal transport failure and verify automatic report delivery.
   pages_to_check=[host,guest]
   failures_before=[page.evaluate("testDiagnosticEvents.filter(e=>e==='failure').length") for page in pages_to_check]
   forced_disconnect={'target':'host','at_unix':time.time(),'attempts':[page.evaluate('testDiagnosticReports.at(-1)?.attempt') for page in pages_to_check]}
   host.evaluate('testPeers.at(-1).close();true')
   wait_until(lambda:any(page.evaluate("testDiagnosticEvents.filter(e=>e==='failure').length")>count for page,count in zip(pages_to_check,failures_before)),25)
   assert all(diagnostic_uploads_ok(page) for page in [host,guest]), 'Failure report upload failed'
   print('DIAGNOSTIC UPLOAD AND ROUTE PASS',flush=True)
   print('GODOT LIVE PRIVATE LOBBY RELAY PASS' if lobby else 'GODOT LIVE FORCED RELAY PASS',json.dumps(reports))
   (ROOT/('build/lobby-relay.json' if lobby else 'build/relay.json')).write_text(json.dumps({'result':'pass','lobby':lobby,'reports':reports,'forced_disconnect':forced_disconnect,'diagnostic_reports':[page.evaluate('testDiagnosticReports') for page in pages_to_check]},indent=2)+'\n')
  finally:
   for i,(_,page) in enumerate(locals().get('pages',[])):
    try:
     print('SAFE ROUTE STATS',i,page.evaluate("(async()=>{const p=testPeers.at(-1);if(!p)return [];const stats=await p.getStats();return [...stats.values()].filter(s=>['transport','candidate-pair','local-candidate','remote-candidate'].includes(s.type)).map(s=>({type:s.type,candidateType:s.candidateType,state:s.state,nominated:s.nominated,bytesReceived:s.bytesReceived,selected:!!s.selectedCandidatePairId}));})()"))
     print('RELAY DIAGNOSTIC',i,page.evaluate('({core:globalThis.EmberCoreWeb?.diagnostics(),http:globalThis.testHttp,peers:globalThis.testPeers?.map(p=>({gathering:p.iceGatheringState,state:p.connectionState,policy:p.getConfiguration().iceTransportPolicy,candidates:(p.localDescription?.sdp.match(/a=candidate:/g)||[]).length}))})'))
     page.capture(ROOT/f'build/relay-setup-{i}.png')
    except Exception:pass
   browser.terminate()
   try:browser.wait(timeout=5)
   except subprocess.TimeoutExpired:browser.kill();browser.wait()
   server.shutdown();server.server_close()
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--lobby',action='store_true');parser.add_argument('--url');args=parser.parse_args();run(args.lobby,args.url)
