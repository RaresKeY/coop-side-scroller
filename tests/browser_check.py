#!/usr/bin/env python3
"""Chromium smoke test under offscreen Gamescope, using only Python's stdlib CDP client."""
import argparse,base64,functools,http.server,json,os,signal,socket,struct,subprocess,tempfile,threading,time,urllib.request
from pathlib import Path
from urllib.parse import urlparse
ROOT=Path(__file__).resolve().parents[1]
from browser_cdp import CDP, QuietHandler
parser=argparse.ArgumentParser();parser.add_argument('--url');parser.add_argument('--connection-setup',action='store_true');parser.add_argument('--animation-check',action='store_true');parser.add_argument('--clipboard-check',action='store_true');args=parser.parse_args()
signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(SystemExit(143)))
(ROOT/'build').mkdir(exist_ok=True)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'build/web')))
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
   page.click(110,212)
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
