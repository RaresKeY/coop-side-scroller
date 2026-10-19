#!/usr/bin/env python3
"""Public Godot game: workstation host / owned Runpod controller guest.
Run under headless Gamescope after explicitly deploying tooling/runpod-browser.
Pairing codes and the private TURN invitation stay in memory; output is sanitized.
This script never creates or deletes cloud resources.
"""
import argparse,json,signal,subprocess,sys,tempfile,time,urllib.request
from pathlib import Path
from browser_cdp import CDP
from browser_relay import INSTRUMENT,wait_until,type_text,key
ROOT=Path(__file__).resolve().parents[1]
URL='https://rareskey.github.io/coop-side-scroller/'
COPY_CAPTURE="""(()=>{const original=EmberClipboard;globalThis.testCopied='';globalThis.EmberClipboard={cancel:()=>original.cancel(),paste:(...a)=>original.paste(...a),copy:(text,done)=>{testCopied=text;done(true)}};return true})()"""
ROUTE="""(async()=>{const p=testPeers.at(-1),s=await p.getStats();const transport=[...s.values()].find(x=>x.type==='transport'&&x.selectedCandidatePairId);const pair=s.get(transport?.selectedCandidatePairId)||[...s.values()].find(x=>x.type==='candidate-pair'&&x.state==='succeeded'&&x.nominated);return {policy:p.getConfiguration().iceTransportPolicy,state:p.connectionState,local:s.get(pair?.localCandidateId)?.candidateType,remote:s.get(pair?.remoteCandidateId)?.candidateType,bytesSent:pair?.bytesSent,bytesReceived:pair?.bytesReceived,rttMs:1000*(pair?.currentRoundTripTime||0),core:EmberCoreWeb.diagnostics().views[0]}})()"""
SAFE="({http:globalThis.testHttp,peers:globalThis.testPeers?.map(p=>({state:p.connectionState,gather:p.iceGatheringState,local:p.localDescription?.type,remote:p.remoteDescription?.type})),core:globalThis.EmberCoreWeb?.diagnostics()})"
class Remote:
 def __init__(self,browser):self.browser=browser
 def evaluate(self,text):return self.browser.evaluate(text)
 def call(self,method,params=None):return self.browser.command(method,params)
 def click(self,x,y):
  point=self.evaluate("(()=>{const r=document.querySelector('canvas').getBoundingClientRect(),s=Math.min(r.width/960,r.height/540);return {x:r.x+(r.width-960*s)/2+"+str(x)+"*s,y:r.y+(r.height-540*s)/2+"+str(y)+"*s}})()")
  self.browser.click(point['x'],point['y']);time.sleep(.15)
 def capture(self,path):self.browser.screenshot(path)
def enter(page,text):
 wait_until(lambda:page.evaluate("!!document.querySelector('[data-ember-paste]')"),5)
 page.call('Input.insertText',{'text':text})
 # DOM dialog coordinates already use browser pixels, not game coordinates.
 point=page.evaluate("(()=>{const r=document.querySelector('[data-ember-accept]').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()")
 if isinstance(page,Remote):page.browser.click(point['x'],point['y'])
 else:page.click(point['x'],point['y'])
 time.sleep(.15)
def run():
 parser=argparse.ArgumentParser();parser.add_argument('--controller-dir',type=Path,default=ROOT.parent/'tooling/runpod-browser');args=parser.parse_args()
 output=ROOT/'build';output.mkdir(exist_ok=True)
 # Keep historical success, but never leave it labelled as the current attempt.
 started=time.time()
 report_path=output/'cross-network-latest.json'
 report_path.write_text(json.dumps({'result':'running','started_at_unix':started})+'\n')
 sys.path.insert(0,str(args.controller_dir));from client import Browser
 remote=Browser();health=remote.request('/health');assert health['ready'],'Controller not ready'
 guest=Remote(remote)
 token=json.loads((Path.home()/'.config/cloudflare-api/access-coop-side-scroller-issuer.json').read_text())['token']
 stage='startup';host=None
 with tempfile.TemporaryDirectory(prefix='ember-cross-network-') as profile,(output/'cross-network-browser.log').open('w') as log:
  process=subprocess.Popen(['chromium','--ozone-platform=x11','--mute-audio','--no-first-run','--no-default-browser-check','--disable-background-timer-throttling','--disable-renderer-backgrounding','--remote-debugging-port=0','--remote-allow-origins=*',f'--user-data-dir={profile}','about:blank'],stdout=log,stderr=log)
  try:
   wait_until(lambda:(Path(profile)/'DevToolsActivePort').exists(),10)
   port=int((Path(profile)/'DevToolsActivePort').read_text().splitlines()[0]);tabs=json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list'))
   host=CDP(tabs[0]['webSocketDebuggerUrl'])
   for page in [host,guest]:
    page.call('Page.enable');page.call('Runtime.enable');page.call('Page.addScriptToEvaluateOnNewDocument',{'source':'(()=>{if(globalThis.testPeers)return;'+INSTRUMENT+'})()'})
   host.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
   host.call('Page.navigate',{'url':URL});remote.navigate(URL)
   for page in [host,guest]:
    wait_until(lambda:page.evaluate('globalThis.EmberCoreWeb?.diagnostics().calls>120'),90)
    page.evaluate(COPY_CAPTURE)
    page.click(160,283);type_text(page,token)
    page.click(180,317);page.click(160,378);page.click(160,354)
   stage='host invitation';print('BOTH BROWSERS CONFIGURED',flush=True);host.click(160,387)
   wait_until(lambda:host.evaluate('testPeers.at(-1)?.iceGatheringState==="complete"'),30)
   host.click(90,185);offer=host.evaluate('testCopied');assert len(offer)>100
   stage='guest reply';print('HOST INVITATION READY',flush=True);guest.click(160,421);guest.click(240,185);enter(guest,offer)
   wait_until(lambda:guest.evaluate('testPeers.at(-1)?.iceGatheringState==="complete"'),30)
   guest.click(90,185);answer=wait_until(lambda:guest.evaluate('testCopied'),5);assert len(answer)>100 and answer!=offer
   stage='connect';print('GUEST REPLY READY',flush=True);host.click(240,185);enter(host,answer)
   for page in [host,guest]:wait_until(lambda:page.evaluate('testPeers.at(-1)?.connectionState==="connected" && EmberCoreWeb.diagnostics().views[0].actors===2'),40)
   print('CROSS-NETWORK CONNECTED: independent cores, two actors',flush=True)
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
   host.capture(output/'cross-network-host.png');guest.capture(output/'cross-network-guest.png')
   report={'result':'pass','started_at_unix':started,'game_url':URL,'host_network':'workstation','guest_network':'Runpod','guest_browser':health['browser'],'pairing':'guided UI with in-memory test copy capture and native DOM input; no remote desktop clipboard','routes':reports,'limitations':['Chrome only','remote software rendering','no blocked-UDP/TCP-only test','no general NAT reliability claim']}
   (output/'cross-network.json').write_text(json.dumps(report,indent=2)+'\n')
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
     try:page.evaluate("(()=>{globalThis.testCopied='';return true})()")
     except Exception:pass
   process.terminate()
   try:process.wait(timeout=5)
   except subprocess.TimeoutExpired:process.kill();process.wait()
if __name__=='__main__':
 signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(SystemExit(143)))
 run()
