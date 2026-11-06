"""UI entrypoints for the invite-first browser adapter. Credentials never enter reports."""
import getpass,sys,time
LOCAL_INVITE_KEY='K'*64
LOCAL_INVITE_STUB="""
const inviteFetch=globalThis.fetch;
globalThis.fetch=(input,options={})=>{
 const url=String(input);
 if(url.includes('ember-coop-credentials.')&&url.endsWith('/v1/lobby')){
  const raw=options.body,text=typeof raw==='string'?raw:new TextDecoder().decode(raw);
  try{
   const body=JSON.parse(text);
   if(body.action==='list'&&new Headers(options.headers).get('Authorization')==='Bearer '+('K'.repeat(64)))
    return Promise.resolve(Response.json({version:1,rooms:[]},{headers:{'Cache-Control':'no-store'}}));
  }catch{}
 }
 return inviteFetch(input,options);
};
"""
def read_invite(use_stdin=False):
 if use_stdin and sys.stdin.isatty():raise RuntimeError('Use masked input for a terminal; stdin mode requires a protected pipe.')
 if use_stdin:value=sys.stdin.read(131).strip()
 elif sys.stdin.isatty():value=getpass.getpass('Playtest invite key: ').strip()
 else:raise RuntimeError('Invite requires masked terminal input or an explicitly protected stdin pipe.')
 if not 32<=len(value)<=128 or any(not 33<=ord(c)<=126 for c in value):
  raise RuntimeError('Invalid invite key shape; value withheld.')
 return value
def enter_invite(page,value,seconds=20):
 deadline=time.monotonic()+seconds
 while not page.evaluate("!!document.querySelector('[data-ember-invite]')"):
  if time.monotonic()>deadline:raise RuntimeError('Invite screen did not appear')
  time.sleep(.1)
 page.evaluate("(()=>{const f=document.querySelector('[data-ember-invite]');f.focus();f.select();return true})()")
 page.call('Input.insertText',{'text':value})
 for kind in ['keyDown','keyUp']:
  page.call('Input.dispatchKeyEvent',{'type':kind,'key':'Enter','code':'Enter','windowsVirtualKeyCode':13})
 while page.evaluate("!!document.querySelector('[data-ember-invite]')"):
  if time.monotonic()>deadline:raise RuntimeError('Invite was not accepted; credential withheld.')
  time.sleep(.1)
def settings_route(page,index,manual=False):
 page.click(80,504)
 page.click(180,216)
 for _ in range(index):
  for kind in ['keyDown','keyUp']:
   page.call('Input.dispatchKeyEvent',{'type':kind,'key':'ArrowDown','code':'ArrowDown','windowsVirtualKeyCode':40})
 for kind in ['keyDown','keyUp']:
  page.call('Input.dispatchKeyEvent',{'type':kind,'key':'Enter','code':'Enter','windowsVirtualKeyCode':13})
 if manual:page.click(220,251)
 else:page.click(80,504)
