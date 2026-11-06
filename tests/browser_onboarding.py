#!/usr/bin/env python3
"""Finite software-rendered Godot onboarding/UI acceptance, with no live credentials."""
import argparse,functools,http.server,json,os,subprocess,sys,tempfile,threading,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tests'))
from browser_cdp import CDP,QuietHandler
from browser_relay import wait_until,key
p=argparse.ArgumentParser();p.add_argument('label',nargs='?',default='latest');p.add_argument('--quick',action='store_true');args=p.parse_args()
out=ROOT/'build/onboarding'/args.label;out.mkdir(parents=True,exist_ok=True)
(out/'result.json').write_text(json.dumps({'result':'running'})+'\n')
fixture='K'*64
instrument="""
globalThis.inviteTest={status:401,delay:350,calls:0,bodyLeak:false,copyCount:0,copyLeak:false};
const realFetch=fetch;
globalThis.fetch=async(...args)=>{
 const url=String(args[0]), options=args[1]||{};
 if(url.includes('ember-coop-credentials.')&&url.endsWith('/v1/lobby')){
  inviteTest.calls++;
  const headers=new Headers(options.headers);
  inviteTest.authOk=headers.get('Authorization')==='Bearer '+FIXTURE;
  const raw=options.body,body=typeof raw==='string'?raw:new TextDecoder().decode(raw);
  inviteTest.bodyLeak ||= body.includes(FIXTURE);
  const status=inviteTest.status;
  await new Promise(resolve=>setTimeout(resolve,inviteTest.delay));
  return Response.json(status===200?{version:1,rooms:[]}:{error:'access_denied'},{status,headers:{'Cache-Control':'no-store'}});
 }
 if(url.includes('ember-coop-credentials.')&&url.endsWith('/v1/diagnostics'))return Response.json({version:1,accepted:true});
 return realFetch(...args);
};
Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{inviteTest.copyCount++;inviteTest.copyLeak ||= text.includes(FIXTURE);}}});
""".replace('FIXTURE',json.dumps(fixture))
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT/'build/web')))
threading.Thread(target=server.serve_forever,daemon=True).start()
with tempfile.TemporaryDirectory(prefix='ember-onboarding-') as profile,(out/'browser.log').open('w') as log:
 browser=subprocess.Popen(['chromium','--headless=new','--ozone-platform=headless','--use-angle=swiftshader','--enable-unsafe-swiftshader',*(['--proxy-server='+os.environ['HTTPS_PROXY']] if os.environ.get('HTTPS_PROXY') else []),'--mute-audio','--no-first-run','--no-default-browser-check','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows','--remote-debugging-port=0','--remote-allow-origins=*','--user-data-dir='+profile,'about:blank'],stdout=log,stderr=log)
 page=control=None
 try:
  wait_until(lambda:(Path(profile)/'DevToolsActivePort').exists(),15)
  port=int((Path(profile)/'DevToolsActivePort').read_text().splitlines()[0]);base=f'http://127.0.0.1:{port}'
  control=CDP(json.load(urllib.request.urlopen(base+'/json/version'))['webSocketDebuggerUrl'])
  target=control.call('Target.createTarget',{'url':'about:blank','newWindow':True})['targetId']
  tabs=json.load(urllib.request.urlopen(base+'/json/list'));page=CDP(next(t for t in tabs if t['id']==target)['webSocketDebuggerUrl'])
  page.call('Runtime.enable');page.call('Page.enable');page.call('Page.addScriptToEvaluateOnNewDocument',{'source':instrument})
  page.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False})
  page.call('Page.navigate',{'url':f'http://127.0.0.1:{server.server_port}/'})
  wait_until(lambda:page.evaluate("!!document.querySelector('[data-ember-invite]')"),35)
  control.call('Target.activateTarget',{'targetId':target})
  cases=[(854,480),(960,540),(1280,720),(1920,1080)]
  placements=[]
  for w,h in cases:
   page.call('Emulation.setDeviceMetricsOverride',{'width':w,'height':h,'deviceScaleFactor':1,'mobile':False});time.sleep(.4)
   s=page.evaluate("""(()=>{
    const f=document.querySelector('[data-ember-invite]'),r=f.getBoundingClientRect();
    return {type:f.type,autocomplete:f.autocomplete,focused:document.activeElement===f,x:r.x,y:r.y,right:r.right,bottom:r.bottom};
   })()""")
   assert s['type']=='password' and s['autocomplete']=='current-password' and s['focused'],s
   assert 0<s['x']<s['right']<w and 0<s['y']<s['bottom']<h,s
   placements.append(s);page.capture(out/f'invite-{w}.png')
  page.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False});time.sleep(.3)
  x=page.evaluate('EmberCoreWeb.diagnostics().views[0].x')
  key(page,'d','KeyD',68);key(page,'d','KeyD',68,False)
  assert page.evaluate('EmberCoreWeb.diagnostics().views[0].x')==x,'invite typing moved actor'
  page.evaluate("document.querySelector('[data-ember-invite]').select()")
  page.call('Input.insertText',{'text':'short'})
  key(page,'Enter','Enter',13);key(page,'Enter','Enter',13,False)
  assert page.evaluate('inviteTest.calls===0'),'malformed key left browser'
  page.evaluate("document.querySelector('[data-ember-invite]').select()")
  page.call('Input.insertText',{'text':fixture})
  key(page,'Enter','Enter',13);key(page,'Enter','Enter',13,False)
  wait_until(lambda:page.evaluate("inviteTest.calls===1&&!document.querySelector('[data-ember-invite]').disabled"),5)
  page.capture(out/'invalid-invite.png')
  page.evaluate("inviteTest.status=200;inviteTest.oldField=document.querySelector('[data-ember-invite]')")
  key(page,'Enter','Enter',13);key(page,'Enter','Enter',13,False)
  assert page.evaluate("document.querySelector('[data-ember-invite]').disabled"),'pending invite remained editable'
  page.capture(out/'checking-invite.png')
  wait_until(lambda:page.evaluate("!document.querySelector('[data-ember-invite]')"),5)
  assert page.evaluate("inviteTest.oldField.value===''&&inviteTest.authOk&&!inviteTest.bodyLeak"),'invite erasure/authentication failed'
  assert page.evaluate("![...Object.values(localStorage),...Object.values(sessionStorage),location.href,document.cookie].some(x=>x.includes("+json.dumps(fixture)+"))"),'invite persisted'
  for w,h in cases:
   page.call('Emulation.setDeviceMetricsOverride',{'width':w,'height':h,'deviceScaleFactor':1,'mobile':False});time.sleep(.3)
   page.capture(out/f'main-{w}.png')
   page.click(80*w/960,(h-36*h/540));time.sleep(.2)
   assert not page.evaluate('EmberSocialObserver.snapshot().available'),'Settings did not suppress chat'
   page.capture(out/f'settings-{w}.png')
   page.click(80*w/960,(h-36*h/540));time.sleep(.15)
  page.call('Emulation.setDeviceMetricsOverride',{'width':960,'height':540,'deviceScaleFactor':1,'mobile':False});time.sleep(.3)
  page.click(80,504);time.sleep(.2);page.capture(out/'settings.png')
  if not args.quick:
   page.click(180,296)
   wait_until(lambda:page.evaluate('inviteTest.copyCount===1'),4)
   assert page.evaluate('!inviteTest.copyLeak'),'diagnostic copy contained invite'
   page.click(220,251);time.sleep(.25);page.capture(out/'advanced-expanded.png')
   page.click(180,344);time.sleep(.4);page.capture(out/'manual-join.png')
   page.click(60,57);time.sleep(.2)
   page.click(180,193);time.sleep(.3)
   wait_until(lambda:page.evaluate('EmberSocialObserver.snapshot().available'),5)
   x=page.evaluate('EmberCoreWeb.diagnostics().views[0].x')
   key(page,'d','KeyD',68);time.sleep(.25);key(page,'d','KeyD',68,False)
   assert page.evaluate('EmberCoreWeb.diagnostics().views[0].x')>x,'movement did not resume'
   key(page,'Enter','Enter',13);key(page,'Enter','Enter',13,False)
   wait_until(lambda:page.evaluate("!!document.querySelector('[data-ember-chat]')"),4)
   page.call('Input.insertText',{'text':'Hello\nReady'})
   key(page,'Enter','Enter',13);key(page,'Enter','Enter',13,False)
   wait_until(lambda:page.evaluate('EmberSocialObserver.snapshot().messages.length===1'),5)
   page.click(80,504);time.sleep(.2)
   page.click(220,251);time.sleep(.2)
   page.click(180,344)
   wait_until(lambda:page.evaluate("!!document.querySelector('[data-ember-invite]')"),5)
   assert page.evaluate("document.querySelector('[data-ember-invite]').value===''"),'switch invite retained old secret'
   page.capture(out/'change-invite.png')
  assert not page.errors,page.errors
  result={'result':'pass','cases':cases,'placements':placements,'validation':'real Godot HTTPRequest with deterministic service responses','password_semantics':'pass','malformed_rejection':'pass','invalid_retry':'pass','pending':'pass','erasure_and_no_persistence':'pass','runtime_errors':0,'quick':args.quick,'build':page.evaluate('EmberBuildInfo')}
  (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='placements'}))
 except BaseException as error:
  (out/'result.json').write_text(json.dumps({'result':'fail','error_type':type(error).__name__})+'\n')
  if page:
   try:page.capture(out/'failed.png');(out/'failure.json').write_text(json.dumps({'runtime_errors':page.errors,'request_count':page.evaluate('inviteTest.calls')},indent=2)+'\n')
   except Exception:pass
  raise
 finally:
  for c in [page,control]:
   if c:c.socket.close()
  browser.terminate()
  try:browser.wait(timeout=5)
  except subprocess.TimeoutExpired:browser.kill();browser.wait()
  server.shutdown();server.server_close()
