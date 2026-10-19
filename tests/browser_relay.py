#!/usr/bin/env python3
"""Two actual Godot Web instances through the live protected issuer and TURN.
Run under offscreen Gamescope. Invitation is read privately; never logged/saved.
This same-machine test proves relay use, not independent access networks.
"""
import functools,http.server,json,signal,subprocess,tempfile,threading,time,urllib.request
from pathlib import Path
from browser_cdp import CDP,QuietHandler
ROOT=Path(__file__).resolve().parents[1]
signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(SystemExit(143)))
INSTRUMENT='''globalThis.testPeers=[];globalThis.testHttp=[];const nativeFetch=globalThis.fetch;globalThis.fetch=async(...args)=>{const r=await nativeFetch(...args);if(String(args[0]).includes('workers.dev'))testHttp.push(r.status);return r;};const NativeRTC=globalThis.RTCPeerConnection;
globalThis.RTCPeerConnection=class extends NativeRTC {constructor(...args){super(...args);testPeers.push(this);}};'''
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
def run():
 token=json.loads((Path.home()/'.config/cloudflare-api/access-coop-side-scroller-issuer.json').read_text())['token']
 server=http.server.ThreadingHTTPServer(('127.0.0.1',27841),functools.partial(QuietHandler,directory=str(ROOT/'build/web')))
 threading.Thread(target=server.serve_forever,daemon=True).start();origin='http://127.0.0.1:27841'
 with tempfile.TemporaryDirectory(prefix='ember-relay-') as profile,(ROOT/'build/relay-browser.log').open('w') as log:
  browser=subprocess.Popen(['chromium','--ozone-platform=x11','--no-first-run','--no-default-browser-check','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows','--remote-debugging-port=0','--remote-allow-origins=*',f'--user-data-dir={profile}','about:blank'],stdout=log,stderr=log)
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
    control.call('Target.activateTarget',{'targetId':target});time.sleep(.2);page.click(160,327);type_text(page,token);page.click(180,361)
    page.click(160,422) # Second popup item: Relay only.
    pages.append((target,page));print('SETUP',role,flush=True)
   host,guest=[item[1] for item in pages]
   control.call('Target.activateTarget',{'targetId':pages[0][0]});host.click(160,216)
   wait_until(lambda:host.evaluate('testPeers.length'),15)
   wait_until(lambda:host.evaluate('testPeers.length && testPeers.at(-1).iceGatheringState==="complete"'))
   assert host.evaluate('testPeers.at(-1).getConfiguration().iceTransportPolicy')=='relay','Relay-only UI selection failed'
   print('HOST RELAY READY',flush=True)
   # Godot's actual Copy/Paste buttons exchange its versioned codes in memory.
   host.click(370,209);time.sleep(.2)
   offer=host.evaluate('navigator.clipboard.readText()');assert len(offer)>100,'No offer copied'
   control.call('Target.activateTarget',{'targetId':pages[1][0]});guest.click(160,260)
   guest.evaluate('navigator.clipboard.writeText('+json.dumps(offer)+')');guest.click(490,209)
   wait_until(lambda:guest.evaluate('testPeers.length && testPeers.at(-1).iceGatheringState==="complete"'))
   guest.click(370,209);time.sleep(.2);answer=guest.evaluate('navigator.clipboard.readText()');assert answer!=offer and len(answer)>100,'No answer copied'
   control.call('Target.activateTarget',{'targetId':pages[0][0]});host.evaluate('navigator.clipboard.writeText('+json.dumps(answer)+')');host.click(490,209)
   print('CODES EXCHANGED',flush=True)
   for page in [host,guest]:wait_until(lambda:page.evaluate('testPeers.at(-1).connectionState==="connected"'))
   wait_until(lambda:all(page.evaluate('EmberCoreWeb.diagnostics().views[0].actors===2') for page in [host,guest]))
   control.call('Target.activateTarget',{'targetId':pages[1][0]});guest.click(800,420)
   key(guest,'d','KeyD',68)
   wait_until(lambda:guest.evaluate('EmberCoreWeb.diagnostics().views[0].guestX>=620000'),8)
   key(guest,'d','KeyD',68,False);guest.click(800,420);key(guest,'f','KeyF',70)
   wait_until(lambda:all(page.evaluate('EmberCoreWeb.diagnostics().views[0].hp<12') for page in [host,guest]),5)
   key(guest,'f','KeyF',70,False)
   reports=[]
   for page in [host,guest]:
    report=page.evaluate('''(async()=>{const p=testPeers.at(-1),s=await p.getStats();const pair=[...s.values()].find(x=>x.type==='candidate-pair'&&x.state==='succeeded'&&x.nominated);return {policy:p.getConfiguration().iceTransportPolicy,state:p.connectionState,local:s.get(pair?.localCandidateId)?.candidateType,remote:s.get(pair?.remoteCandidateId)?.candidateType,bytesSent:pair?.bytesSent,bytesReceived:pair?.bytesReceived,rttMs:1000*(pair?.currentRoundTripTime||0),core:EmberCoreWeb.diagnostics().views[0]};})()''')
    assert report['local']=='relay' and report['remote']=='relay' and report['bytesReceived']>0,'Relay traffic not proven'
    reports.append(report)
   assert not host.errors and not guest.errors,'Browser console errors (details withheld)'
   host.capture(ROOT/'build/relay-host.png');guest.capture(ROOT/'build/relay-guest.png')
   print('GODOT LIVE FORCED RELAY PASS',json.dumps(reports))
  finally:
   for i,(_,page) in enumerate(locals().get('pages',[])):
    try:
     print('RELAY DIAGNOSTIC',i,page.evaluate('({core:globalThis.EmberCoreWeb?.diagnostics(),http:globalThis.testHttp,peers:globalThis.testPeers?.map(p=>({gathering:p.iceGatheringState,state:p.connectionState,policy:p.getConfiguration().iceTransportPolicy,candidates:(p.localDescription?.sdp.match(/a=candidate:/g)||[]).length}))})'))
     if page.evaluate('testPeers.length===0'):page.capture(ROOT/f'build/relay-setup-{i}.png')
    except Exception:pass
   browser.terminate()
   try:browser.wait(timeout=5)
   except subprocess.TimeoutExpired:browser.kill();browser.wait()
   server.shutdown();server.server_close()
if __name__=='__main__':run()
