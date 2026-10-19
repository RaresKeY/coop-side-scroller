#!/usr/bin/env python3
"""Chromium smoke test under offscreen Gamescope, using only Python's stdlib CDP client."""
import argparse,base64,functools,http.server,json,os,signal,socket,struct,subprocess,tempfile,threading,time,urllib.request
from pathlib import Path
from urllib.parse import urlparse
ROOT=Path(__file__).resolve().parents[1]
from browser_cdp import CDP, QuietHandler
parser=argparse.ArgumentParser();parser.add_argument('--url');parser.add_argument('--ice-diagnostics-check',action='store_true');parser.add_argument('--connection-setup',action='store_true');parser.add_argument('--animation-check',action='store_true');parser.add_argument('--clipboard-check',action='store_true');args=parser.parse_args()
signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(SystemExit(143)))
(ROOT/'build').mkdir(exist_ok=True)
server=http.server.ThreadingHTTPServer(('127.0.0.1',27841 if args.ice_diagnostics_check else 0),functools.partial(QuietHandler,directory=str(ROOT/'build/web')))
threading.Thread(target=server.serve_forever,daemon=True).start()
origin=args.url or f'http://127.0.0.1:{server.server_port}'
with tempfile.TemporaryDirectory(prefix='ember-web-check-') as profile, (ROOT/'build/browser-console.log').open('w') as log:
 browser=subprocess.Popen(['chromium','--ozone-platform=x11','--no-first-run','--no-default-browser-check','--remote-debugging-port=0','--remote-allow-origins=*',f'--user-data-dir={profile}','about:blank'],stdout=log,stderr=log)
 try:
  port_file=Path(profile)/'DevToolsActivePort'
  for _ in range(100):
   if port_file.exists():break
   time.sleep(.1)
  port=int(port_file.read_text().splitlines()[0]);base=f'http://127.0.0.1:{port}'
  control=CDP(json.load(urllib.request.urlopen(base+'/json/version'))['webSocketDebuggerUrl'])
  target=control.call('Target.createTarget',{'url':'about:blank'})['targetId']
  tabs=json.load(urllib.request.urlopen(base+'/json/list'))
  page=CDP(next(t for t in tabs if t['id']==target)['webSocketDebuggerUrl'])
  page.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
  page.call('Runtime.enable');page.call('Page.navigate',{'url':origin})
  ready=None
  for _ in range(100):
   ready=page.evaluate('globalThis.EmberCoreWeb?.diagnostics()')
   if ready and ready['live']==1 and ready['calls']>100:break
   time.sleep(.15)
  assert ready and ready['live']==1 and ready['views'][0]['tick']>0,ready
  page.capture(ROOT/'build/web-onboarding.png')
  assert page.evaluate("""(()=>{const h=EmberCoreWeb.create();try{return [NaN,Infinity,-Infinity,0.5,4294967298,'2',null].every(op=>EmberCoreWeb.command(h,op,0,0)===-2)&&EmberCoreWeb.command(h,1,4294967296,0)===-2&&EmberCoreWeb.command(h,1,0,4294967296)===-2&&EmberCoreWeb.command(h,10,0,0)===0&&EmberCoreWeb.command(0,2,0,0)===-1;}finally{EmberCoreWeb.destroy(h)}})()"""),'Web ABI silently narrowed invalid arguments'

  if args.ice_diagnostics_check:
   page.evaluate("""globalThis.failedIceEvents=[];globalThis.failedIceProbe=new RTCPeerConnection({iceServers:[{urls:'stun:ice-diagnostics.invalid:19302'}]});globalThis.failedIceNativeErrors=[];failedIceProbe.addEventListener('icecandidateerror',e=>failedIceNativeErrors.push(e.errorCode));failedIceProbe.createDataChannel('diagnostic-probe');failedIceProbe.createOffer().then(offer=>failedIceProbe.setLocalDescription(offer));true""")
   for _ in range(200):
    page.evaluate("failedIceEvents.push(...JSON.parse(EmberConnectionDiagnostics.drain()));true")
    if page.evaluate("failedIceEvents.some(e=>e.event==='ice_error'&&e.code===701)||(failedIceProbe.iceGatheringState==='complete'&&failedIceEvents.some(e=>e.event==='ice_candidates'&&e.host+e.srflx+e.prflx+e.relay===0))"):break
    time.sleep(.1)
   assert page.evaluate("failedIceEvents.some(e=>e.event==='ice_error'&&e.code===701)||(failedIceProbe.iceGatheringState==='complete'&&failedIceEvents.some(e=>e.event==='ice_candidates'&&e.host+e.srflx+e.prflx+e.relay===0))"),'Expected unreachable ICE server or no usable candidates'
   page.evaluate("EmberConnectionDiagnostics.sample(()=>{});true");time.sleep(.2)
   page.evaluate("failedIceEvents.push(...JSON.parse(EmberConnectionDiagnostics.drain()));true")
   events=page.evaluate('failedIceEvents')
   assert any(e['event']=='ice_stats' for e in events),'No stats for unconnected peer'
   assert 'ice-diagnostics.invalid' not in json.dumps(events),'Private server address leaked'
   assert all(not any(k in e for k in ['url','address','errorText','port']) for e in events),'Private ICE metadata leaked'
   diagnostic_id=__import__('secrets').token_hex(8)
   token=json.loads((Path.home()/'.config/cloudflare-api/access-coop-side-scroller-issuer.json').read_text())['token']
   events.append({'event':'failure','reason':'gathering'})
   report={'version':1,'build':'diagnostics-v2','attempt':diagnostic_id,'events':[dict(e,seq=i+1,ms=i,role='client') for i,e in enumerate(events[-64:])]}
   status=page.evaluate("(async()=>{const r=await fetch('https://ember-coop-credentials.ember-bridge-playtests.workers.dev/v1/diagnostics',{method:'POST',headers:{'Authorization':'Bearer '+"+json.dumps(token)+",'Content-Type':'application/json'},body:"+json.dumps(json.dumps(report))+"});return r.status})()")
   assert status==200,{'diagnostic_upload_status':status}
   (ROOT/'build/failed-ice-browser.json').write_text(json.dumps({'result':'pass','attempt':diagnostic_id,'events':events},indent=2)+'\n')
   page.evaluate('failedIceProbe.close();EmberConnectionDiagnostics.reset();true')
   print('REAL FAILED ICE DIAGNOSTICS PASS',flush=True)

  if args.clipboard_check:
   parsed=urlparse(origin)
   control.call('Browser.grantPermissions',{'origin':parsed.scheme+'://'+parsed.netloc,'permissions':['clipboardReadWrite','clipboardSanitizedWrite']})
   page.evaluate("globalThis.nativeWrite=navigator.clipboard.writeText.bind(navigator.clipboard);Object.defineProperty(navigator.clipboard,'writeText',{configurable:true,value:()=>Promise.reject(new DOMException('test denial','NotAllowedError'))});true")
   for width,height in [(1920,1080),(1280,720),(960,540),(854,480)]:
    page.call('Emulation.setDeviceMetricsOverride',{'width':width,'height':height,'deviceScaleFactor':1,'mobile':False})
    page.evaluate("globalThis.copyResult=null;EmberClipboard.copy('public-clipboard-probe',success=>copyResult=success);true")
    for _ in range(30):
     if page.evaluate("!!document.querySelector('[data-ember-copy]')"):break
     time.sleep(.05)
    bounds=page.evaluate("(()=>{const e=document.querySelector('[data-ember-copy]'),r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,focused:document.activeElement===e}})()")
    assert 0<bounds['x']<width and 0<bounds['y']<height and bounds['focused'],bounds
    page.capture(ROOT/f'build/clipboard-{width}.png')
    page.click(bounds['x'],bounds['y'])
    assert page.evaluate("copyResult===true && !document.querySelector('[role=dialog]')"),'Copy acknowledgement/cleanup failed'
    assert page.evaluate("navigator.clipboard.readText()")=='public-clipboard-probe','Native DOM Copy did not reach the clipboard'
   page.evaluate("globalThis.copyResult=null;EmberClipboard.copy('public-cancel-probe',success=>copyResult=success);true")
   time.sleep(.1);page.evaluate('EmberClipboard.cancel();true')
   assert page.evaluate("copyResult===false && !document.querySelector('[role=dialog]')"),'Cancelled code retained'
   page.evaluate("globalThis.copyResult=null;Object.defineProperty(navigator.clipboard,'writeText',{configurable:true,value:()=>new Promise(resolve=>globalThis.resolveSlowCopy=resolve)});EmberClipboard.copy('public-slow-probe',success=>copyResult=success);true")
   for _ in range(60):
    if page.evaluate("!!document.querySelector('[data-ember-copy]')"):break
    time.sleep(.1)
   assert page.evaluate("!!document.querySelector('[data-ember-copy]')"),'Copy timeout did not open fallback'
   page.evaluate('resolveSlowCopy();true')
   assert page.evaluate("copyResult===null && !!document.querySelector('[role=dialog]')"),'Late clipboard completion dismissed active fallback'
   page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'Tab','code':'Tab','windowsVirtualKeyCode':9,'modifiers':8})
   page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'Tab','code':'Tab','windowsVirtualKeyCode':9})
   assert page.evaluate("document.activeElement===document.querySelector('[role=dialog] textarea')"),'Copy fallback code cannot be reached with Shift+Tab'
   page.evaluate("globalThis.detachedCodeField=document.querySelector('[role=dialog] textarea');EmberClipboard.cancel();true")
   assert page.evaluate("copyResult===false && detachedCodeField.value==='' && !document.querySelector('[role=dialog]')"),'Cancel retained code in detached fallback field'
   for width,height in [(1920,1080),(1280,720),(960,540),(854,480)]:
    page.call('Emulation.setDeviceMetricsOverride',{'width':width,'height':height,'deviceScaleFactor':1,'mobile':False})
    page.evaluate("globalThis.pasteResult=null;EmberClipboard.paste('Enter host invitation',value=>pasteResult=value);true")
    assert page.evaluate("document.activeElement===document.querySelector('[data-ember-paste]')"),'Paste field not focused'
    page.call('Input.insertText',{'text':'public-paste-probe'})
    bounds=page.evaluate("(()=>{const r=document.querySelector('[data-ember-accept]').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()")
    page.capture(ROOT/f'build/paste-{width}.png')
    page.click(bounds['x'],bounds['y'])
    assert page.evaluate("pasteResult==='public-paste-probe' && !document.querySelector('[role=dialog]')"),'Native paste input/cleanup failed'
   page.evaluate("globalThis.pasteResult=null;EmberClipboard.paste('Cancel probe',value=>pasteResult=value);EmberClipboard.cancel();true")
   assert page.evaluate("pasteResult==='' && !document.querySelector('[role=dialog]')"),'Cancelled paste retained'
   page.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
   page.click(160,283)
   time.sleep(.15)
   assert page.evaluate("document.activeElement===document.querySelector('input[data-ember-paste][type=password]')"),'Access key did not open masked native entry'
   page.capture(ROOT/'build/access-key-entry.png')
   page.call('Input.insertText',{'text':'public-access-probe'})
   page.evaluate("globalThis.detachedEntry=document.querySelector('[data-ember-paste]');true")
   page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'Enter','code':'Enter','windowsVirtualKeyCode':13})
   page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'Enter','code':'Enter','windowsVirtualKeyCode':13})
   assert page.evaluate("!document.querySelector('[role=dialog]') && detachedEntry.value===''")
   page.click(160,283)
   time.sleep(.15)
   assert page.evaluate("document.querySelector('[data-ember-paste]').value==='public-access-probe'"),'Native entry did not update Godot key'
   page.evaluate('EmberClipboard.cancel();true')
   page.evaluate("globalThis.roomResult=null;EmberClipboard.paste('Room name',value=>roomResult=value,'Co-op room',32,false);true")
   assert page.evaluate("document.activeElement.type==='text' && document.activeElement.maxLength===32 && document.activeElement.selectionEnd===10")
   page.call('Input.insertText',{'text':'Pasted room'})
   page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'Enter','code':'Enter','windowsVirtualKeyCode':13})
   page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'Enter','code':'Enter','windowsVirtualKeyCode':13})
   assert page.evaluate("roomResult==='Pasted room' && !document.querySelector('[role=dialog]')")
   page.evaluate("Object.defineProperty(navigator.clipboard,'writeText',{configurable:true,value:globalThis.nativeWrite});true")
   page.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
   print('BROWSER CLIPBOARD FALLBACK PASS: 1920,1280,960,854; real copy, focus, cancel and cleanup')

  page.click(110,177) # Actual Play solo menu button.
  time.sleep(.25)
  before=page.evaluate('EmberCoreWeb.diagnostics()')['views'][0]
  page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'d','code':'KeyD','windowsVirtualKeyCode':68})
  time.sleep(.7)
  page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'d','code':'KeyD','windowsVirtualKeyCode':68})
  after=page.evaluate('EmberCoreWeb.diagnostics()')['views'][0]
  assert after['tick']>before['tick'] and after['x']>before['x']+50000,(before,after)
  page.capture(ROOT/'build/web-gameplay.png')
  if args.animation_check:
   page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'d','code':'KeyD','windowsVirtualKeyCode':68})
   for _ in range(40):
    if page.evaluate('EmberCoreWeb.diagnostics()')['views'][0]['x']>=670000:break
    time.sleep(.1)
   page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'d','code':'KeyD','windowsVirtualKeyCode':68})
   pose=page.evaluate('EmberCoreWeb.diagnostics()')['views'][0]
   assert 655000<=pose['x']<710000,pose
   page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'w','code':'KeyW','windowsVirtualKeyCode':87})
   time.sleep(.25)
   page.capture(ROOT/'build/web-jump.png')
   page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'w','code':'KeyW','windowsVirtualKeyCode':87})
   time.sleep(.55)
   page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'f','code':'KeyF','windowsVirtualKeyCode':70})
   contact=None
   for _ in range(20):
    contact=page.evaluate('EmberCoreWeb.diagnostics()')['views'][0]
    if contact['hp']<pose['hp']:break
    time.sleep(.025)
   page.capture(ROOT/'build/web-attack.png')
   page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'f','code':'KeyF','windowsVirtualKeyCode':70})
   assert contact['hp']<pose['hp'],contact
   print('GODOT WEB ANIMATION/COMBAT PASS',contact)
  if args.connection_setup:
   page.click(55,70) # Open Menu, then Host game.
   time.sleep(.15)
   page.click(110,354) # Reveal manual connection controls.
   page.click(110,387)
   time.sleep(2)
   page.capture(ROOT/'build/web-connection.png')
   # Inspect this capture for setup/failure UI; this does not assert P2P success.
  assert not page.errors,page.errors
  print('GODOT WEB WASM PASS',{'before':before,'after':after,'origin':origin})
 finally:
  browser.terminate()
  try:browser.wait(timeout=5)
  except subprocess.TimeoutExpired:browser.kill();browser.wait()
  server.shutdown();server.server_close()
