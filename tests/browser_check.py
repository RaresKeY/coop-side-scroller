#!/usr/bin/env python3
"""Chromium smoke test under offscreen Gamescope, using only Python's stdlib CDP client."""
import argparse,base64,functools,http.server,json,os,signal,socket,struct,subprocess,tempfile,threading,time,urllib.request
from pathlib import Path
from urllib.parse import urlparse
ROOT=Path(__file__).resolve().parents[1]
class CDP:
 def __init__(self,url):
  u=urlparse(url);self.socket=socket.create_connection((u.hostname,u.port),timeout=15);self.sequence=0;self.errors=[]
  key=base64.b64encode(os.urandom(16)).decode()
  self.socket.sendall(f'GET {u.path} HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'.encode())
  reply=b''
  while not reply.endswith(b'\r\n\r\n'):reply+=self.read(1)
  if b'101' not in reply:raise RuntimeError('CDP handshake failed')
 def read(self,size):
  result=b''
  while len(result)<size:
   chunk=self.socket.recv(size-len(result))
   if not chunk:raise RuntimeError('CDP closed')
   result+=chunk
  return result
 def call(self,method,params=None):
  self.sequence+=1;request=self.sequence
  raw=json.dumps({'id':request,'method':method,'params':params or {}}).encode();mask=os.urandom(4);size=len(raw)
  header=bytes([0x81,0x80|size]) if size<126 else bytes([0x81,0xfe])+struct.pack('!H',size) if size<65536 else bytes([0x81,0xff])+struct.pack('!Q',size)
  self.socket.sendall(header+mask+bytes(v^mask[i%4] for i,v in enumerate(raw)))
  deadline=time.monotonic()+20
  while time.monotonic()<deadline:
   opcode,length=self.read(2);length&=127
   if length==126:length=struct.unpack('!H',self.read(2))[0]
   elif length==127:length=struct.unpack('!Q',self.read(8))[0]
   data=json.loads(self.read(length))
   if data.get('method')=='Runtime.consoleAPICalled' and data['params'].get('type')=='error':self.errors.append(data['params']['args'])
   if data.get('method')=='Runtime.exceptionThrown':self.errors.append(data['params'])
   if data.get('id')==request:
    if 'error' in data:raise RuntimeError(data['error'])
    return data.get('result',{})
  raise TimeoutError(method)
 def evaluate(self,expression):
  result=self.call('Runtime.evaluate',{'expression':expression,'returnByValue':True,'awaitPromise':True,'userGesture':True})
  if 'exceptionDetails' in result:raise RuntimeError(result['exceptionDetails'])
  return result.get('result',{}).get('value')
 def click(self,x,y):
  for kind in ['mousePressed','mouseReleased']:self.call('Input.dispatchMouseEvent',{'type':kind,'x':x,'y':y,'button':'left','clickCount':1})
 def capture(self,path):path.write_bytes(base64.b64decode(self.call('Page.captureScreenshot',{'format':'png'})['data']))
class QuietHandler(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
parser=argparse.ArgumentParser();parser.add_argument('--url');args=parser.parse_args()
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
  page.click(110,177) # Actual Play solo menu button.
  time.sleep(.25)
  before=page.evaluate('EmberCoreWeb.diagnostics()')['views'][0]
  page.call('Input.dispatchKeyEvent',{'type':'keyDown','key':'d','code':'KeyD','windowsVirtualKeyCode':68})
  time.sleep(.7)
  page.call('Input.dispatchKeyEvent',{'type':'keyUp','key':'d','code':'KeyD','windowsVirtualKeyCode':68})
  after=page.evaluate('EmberCoreWeb.diagnostics()')['views'][0]
  assert after['tick']>before['tick'] and after['x']>before['x']+50000,(before,after)
  page.capture(ROOT/'build/web-gameplay.png')
  assert not page.errors,page.errors
  print('GODOT WEB WASM PASS',{'before':before,'after':after,'origin':origin})
 finally:
  browser.terminate()
  try:browser.wait(timeout=5)
  except subprocess.TimeoutExpired:browser.kill();browser.wait()
  server.shutdown();server.server_close()
