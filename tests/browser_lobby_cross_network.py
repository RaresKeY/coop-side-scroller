#!/usr/bin/env python3
"""Public lobby flow: workstation host / owned Runpod controller guest.
Run under headless Gamescope after explicitly deploying tooling/runpod-browser.
The private playtest key stays in memory; no offer/answer copying is used.
This script never creates or deletes cloud resources.
"""
import argparse,json,signal,subprocess,sys,tempfile,time,urllib.request
from pathlib import Path
from browser_cdp import CDP
from browser_cross_network import Remote, ROUTE, SAFE
from browser_relay import INSTRUMENT,wait_until,type_text,key
ROOT=Path(__file__).resolve().parents[1]
URL='https://rareskey.github.io/coop-side-scroller/'

def access_key(page, token):
 # Published builds before the text-entry patch still use Godot LineEdit.
 # Detect the real dialog so this harness also accepts the patched UI.
 page.click(160,283)
 if page.evaluate("!!document.querySelector('[data-ember-paste]')"):
  page.call('Input.insertText',{'text':token})
  point=page.evaluate("(()=>{const r=document.querySelector('[data-ember-accept]').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()")
  if isinstance(page,Remote):page.browser.click(point['x'],point['y'])
  else:page.click(point['x'],point['y'])
  return 'native DOM'
 type_text(page,token)
 return 'Godot key events'

RENDERER="""(()=>{const gl=document.querySelector('canvas').getContext('webgl2'),ext=gl.getExtension('WEBGL_debug_renderer_info');return ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER)})()"""
def run():
 parser=argparse.ArgumentParser();parser.add_argument('--controller-dir',type=Path,default=ROOT.parent/'tooling/runpod-browser');args=parser.parse_args()
 output=ROOT/'build';output.mkdir(exist_ok=True)
 # Keep historical success, but never leave it labelled as the current attempt.
 started=time.time()
 report_path=output/'lobby-cross-network-latest.json'
 report_path.write_text(json.dumps({'result':'running','started_at_unix':started})+'\n')
 try:
  sys.path.insert(0,str(args.controller_dir));from client import Browser
  remote=Browser();health=remote.request('/health');assert health['ready'],'Controller not ready'
  guest=Remote(remote)
  token=json.loads((Path.home()/'.config/cloudflare-api/access-coop-side-scroller-issuer.json').read_text())['token']
 except Exception as error:
  report_path.write_text(json.dumps({'result':'fail','started_at_unix':started,'stage':'preflight','error_type':type(error).__name__})+'\n')
  raise SystemExit('Lobby test preflight failed; see sanitized latest report') from None
 stage='startup';host=None
 with tempfile.TemporaryDirectory(prefix='ember-lobby-cross-network-') as profile,(output/'lobby-cross-network-browser.log').open('w') as log:
  process=subprocess.Popen(['chromium','--ozone-platform=x11','--mute-audio','--no-first-run','--no-default-browser-check','--disable-background-timer-throttling','--disable-renderer-backgrounding','--remote-debugging-port=0','--remote-allow-origins=*',f'--user-data-dir={profile}','about:blank'],stdout=log,stderr=log)
  try:
   wait_until(lambda:(Path(profile)/'DevToolsActivePort').exists(),10)
   port=int((Path(profile)/'DevToolsActivePort').read_text().splitlines()[0]);tabs=json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list'))
   host=CDP(tabs[0]['webSocketDebuggerUrl'])
   for page in [host,guest]:
    page.call('Page.enable');page.call('Runtime.enable');page.call('Page.addScriptToEvaluateOnNewDocument',{'source':'(()=>{if(globalThis.testPeers)return;'+INSTRUMENT+'})()'})
   host.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
   host.call('Page.navigate',{'url':URL});remote.navigate(URL)
   input_modes=[]
   for page in [host,guest]:
    wait_until(lambda:page.evaluate('globalThis.EmberCoreWeb?.diagnostics().calls>120'),90)
    input_modes.append(access_key(page,token))
    page.click(180,317);page.click(160,378)
   stage='create room';host.click(160,216)
   wait_until(lambda:host.evaluate('Array.isArray(globalThis.testRoomList)'),15)
   time.sleep(.5) # Allow Godot to consume HTTP completion and re-enable Create.
   host.capture(output/'lobby-cross-network-directory.png')
   host.click(160,201)
   room_id=wait_until(lambda:host.evaluate('globalThis.testRoomId'),15)
   host.capture(output/'lobby-cross-network-waiting.png')
   print('HOST ROOM CREATED',flush=True)
   stage='join room';guest.click(160,216)
   wait_until(lambda:guest.evaluate('globalThis.testRoomList?.some(r=>r.id==='+json.dumps(room_id)+')'),15)
   index=guest.evaluate('testRoomList.findIndex(r=>r.id==='+json.dumps(room_id)+')')
   assert 0<=index<3,'Test room outside visible rows; do not join another room'
   guest.capture(output/'lobby-cross-network-list.png')
   guest.click(160,285+index*36)
   print('GUEST JOINED THROUGH DIRECTORY',flush=True)
   stage='automatic signaling'
   for page in [host,guest]:wait_until(lambda:page.evaluate('testPeers.at(-1)?.connectionState==="connected" && EmberCoreWeb.diagnostics().views[0].actors===2'),40)
   wait_until(lambda:any(page.evaluate('globalThis.testRoomComplete===true') for page in [host,guest]),12)
   print('LOBBY CONNECTED: independent cores, two actors; signaling room cleaned up',flush=True)
   stage='movement';guest.click(800,420)
   # Bounded real key pulses include remote control-request latency.
   for _ in range(12):
    x=host.evaluate('EmberCoreWeb.diagnostics().views[0].guestX')
    if 660000<=x<=710000:break
    right=x<660000;letter='d' if right else 'a'
    key(guest,letter,'Key'+letter.upper(),ord(letter.upper()))
    try:time.sleep(.07)
    finally:key(guest,letter,'Key'+letter.upper(),ord(letter.upper()),False)
    time.sleep(.4)
   # Reject a bad approach rather than counting a missed attack as network loss.
   x=host.evaluate('EmberCoreWeb.diagnostics().views[0].guestX')
   assert 655000<x<720000,'Guest approach outside attack range'
   stage='guest combat';before=host.evaluate('EmberCoreWeb.diagnostics().views[0].hp')
   key(guest,'f','KeyF',70)
   try:time.sleep(.3)
   finally:key(guest,'f','KeyF',70,False)
   wait_until(lambda:host.evaluate('EmberCoreWeb.diagnostics().views[0].hp')<before,8)
   wait_until(lambda:guest.evaluate('EmberCoreWeb.diagnostics().views[0].hp')==host.evaluate('EmberCoreWeb.diagnostics().views[0].hp'),8)
   stage='host movement';before_x=guest.evaluate('EmberCoreWeb.diagnostics().views[0].x')
   key(host,'d','KeyD',68)
   try:time.sleep(.3)
   finally:key(host,'d','KeyD',68,False)
   wait_until(lambda:guest.evaluate('EmberCoreWeb.diagnostics().views[0].x')>before_x+20000,8)
   stage='route evidence';reports=[page.evaluate(ROUTE) for page in [host,guest]]
   for report in reports:assert report['policy']=='relay' and report['local']=='relay' and report['remote']=='relay' and report['bytesReceived']>0 and report['bytesSent']>0,'Relay route not proven'
   assert not host.errors,'Host browser errors (details withheld)'
   host.capture(output/'lobby-cross-network-host.png');guest.capture(output/'lobby-cross-network-guest.png')
   report={'result':'pass','started_at_unix':started,'game_url':URL,'host_network':'workstation','guest_network':'Runpod','guest_browser':health['browser'],'pairing':'authenticated lobby Create/Join; automatic signaling; no code copying','access_input':input_modes,'room_cleanup':True,'renderers':[page.evaluate(RENDERER) for page in [host,guest]],'routes':reports,'limitations':['Chrome only','remote software rendering','no blocked-UDP/TCP-only test','no general NAT reliability claim']}
   (output/'lobby-cross-network.json').write_text(json.dumps(report,indent=2)+'\n')
   report_path.write_text(json.dumps(report,indent=2)+'\n')
   print('CROSS-NETWORK RELAY/COMBAT PASS',json.dumps(report),flush=True)
  except Exception as error:
   report_path.write_text(json.dumps({'result':'fail','started_at_unix':started,'stage':stage,'error_type':type(error).__name__})+'\n')
   print('CROSS-NETWORK FAILED AT',stage,'error type',type(error).__name__,flush=True)
   for name,page in [('host',host),('guest',guest)]:
    if page is not None:
     try:print(name.upper(),'SAFE DIAGNOSTIC',json.dumps(page.evaluate(SAFE)),flush=True)
     except Exception:pass
   raise SystemExit(1) from None
  finally:
   for page in [host,guest]:
    if page is not None:
     try:page.call('Page.navigate',{'url':'about:blank'})
     except Exception:pass
   process.terminate()
   try:process.wait(timeout=5)
   except subprocess.TimeoutExpired:process.kill();process.wait()
if __name__=='__main__':
 signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(SystemExit(143)))
 run()
