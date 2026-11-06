"""Small standard-library CDP helpers for offscreen browser tests."""
import base64,http.server,json,os,socket,struct,time
from urllib.parse import urlparse
class CDP:
 def __init__(self,url):
  u=urlparse(url);self.socket=socket.create_connection((u.hostname,u.port),timeout=15);self.sequence=0;self.errors=[]
  key=base64.b64encode(os.urandom(16)).decode()
  self.socket.sendall(f'GET {u.path} HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'.encode())
  reply=b''
  while not reply.endswith(b'\r\n\r\n'):reply+=self.read(1)
  if b'101' not in reply:raise RuntimeError('CDP handshake failed')
 def read(self,size,deadline=None):
  result=b''
  while len(result)<size:
   if deadline is not None:
    remaining=deadline-time.monotonic()
    if remaining<=0:raise TimeoutError('CDP read deadline')
    self.socket.settimeout(remaining)
   chunk=self.socket.recv(size-len(result))
   if not chunk:raise RuntimeError('CDP closed')
   result+=chunk
  return result
 def call(self,method,params=None,timeout=20):
  deadline=time.monotonic()+timeout
  self.socket.settimeout(timeout)
  self.sequence+=1;request=self.sequence
  raw=json.dumps({'id':request,'method':method,'params':params or {}}).encode();mask=os.urandom(4);size=len(raw)
  header=bytes([0x81,0x80|size]) if size<126 else bytes([0x81,0xfe])+struct.pack('!H',size) if size<65536 else bytes([0x81,0xff])+struct.pack('!Q',size)
  self.socket.sendall(header+mask+bytes(v^mask[i%4] for i,v in enumerate(raw)))
  while time.monotonic()<deadline:
   opcode,length=self.read(2,deadline);length&=127
   if length==126:length=struct.unpack('!H',self.read(2,deadline))[0]
   elif length==127:length=struct.unpack('!Q',self.read(8,deadline))[0]
   data=json.loads(self.read(length,deadline))
   if data.get('method')=='Runtime.consoleAPICalled' and data['params'].get('type')=='error':self.errors.append(data['params']['args'])
   if data.get('method')=='Runtime.exceptionThrown':self.errors.append(data['params'])
   if data.get('id')==request:
    if 'error' in data:raise RuntimeError(data['error'])
    return data.get('result',{})
  raise TimeoutError(method)
 def evaluate(self,expression,timeout=30):
  # ICE gathering can wait 20 seconds; its page error must beat the CDP budget.
  result=self.call('Runtime.evaluate',{'expression':expression,'returnByValue':True,'awaitPromise':True,'userGesture':True},timeout=timeout)
  if 'exceptionDetails' in result:raise RuntimeError(result['exceptionDetails'])
  return result.get('result',{}).get('value')
 def click(self,x,y):
  self.call('Input.dispatchMouseEvent',{'type':'mouseMoved','x':x,'y':y})
  for kind in ['mousePressed','mouseReleased']:self.call('Input.dispatchMouseEvent',{'type':kind,'x':x,'y':y,'button':'left','clickCount':1})
  time.sleep(.12) # Godot processes GUI focus on the next frame.
 def capture(self,path):path.write_bytes(base64.b64decode(self.call('Page.captureScreenshot',{'format':'png'})['data']))
class QuietHandler(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
