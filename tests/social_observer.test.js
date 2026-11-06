const source=await Deno.readTextFile(new URL('../adapters/web/ember_core_bridge.js',import.meta.url));
const check=(ok,message)=>{if(!ok)throw new Error(message);};
Deno.test('Social observation is bounded, immutable and has no input controls',()=>{
 const scope={};new Function('globalThis',source.slice(source.indexOf('// Read-only client-side observations')))(scope);
 const api=scope.EmberSocialObserver;
 check(Object.isFrozen(api)&&Object.keys(api).sort().join(',')==='publish,snapshot','observer exposed controls');
 const value={localSlot:2,names:['Terra','Rae'],messages:[{id:1,slot:2,name:'Rae',text:'<b>literal</b>'}],composing:false,available:true};
 api.publish(JSON.stringify(value));const before=api.snapshot();
 check(Object.isFrozen(before)&&Object.isFrozen(before.names)&&Object.isFrozen(before.messages)&&Object.isFrozen(before.messages[0]),'mutable observations');
 for(const bad of ['{',JSON.stringify({...value,messages:new Array(101).fill(value.messages[0])}),JSON.stringify({...value,names:['x']}),JSON.stringify({...value,messages:[{id:1,slot:3,name:'x',text:'bad'}]})])api.publish(bad);
 check(api.snapshot()===before,'invalid state replaced valid observation');
 check(api.snapshot().messages[0].text==='<b>literal</b>','observer interpreted text');
});

Deno.test('Chat draft follows canvas reflow after window resize and releases its observer',()=>{
 let rect={left:0,top:0,width:1920,height:1080};
 const canvas={getBoundingClientRect:()=>rect}, fields=[], observers=new Set(), events={};
 const previous={focus(){document.activeElement=this;}};
 const document={
  activeElement:previous,
  querySelector:selector=>selector==='canvas'?canvas:null,
  body:{append(field){fields.push(field);}},
  createElement(){return {
   style:{},dataset:{},value:'',
   setAttribute(){},
   focus(){document.activeElement=this;},
   remove(){fields.splice(fields.indexOf(this),1);},
  };},
 };
 class ResizeObserver {
  constructor(callback){this.callback=callback;}
  observe(){observers.add(this);}
  disconnect(){observers.delete(this);}
 }
 const scope={addEventListener:(event,callback)=>events[event]=callback};
 new Function('globalThis','document','ResizeObserver',
  source.slice(source.indexOf('// Inline browser input')))(scope,document,ResizeObserver);
 const api=scope.EmberChatComposer;
 api.open(()=>{},200);
 api.place(632,164,304,28,960,540);
 const field=fields[0];field.value='Keep my draft';
 check(document.activeElement===field,'composer did not focus');
 check(parseFloat(field.style.left)===1264,'initial composer alignment');
 // The window event precedes Godot applying the new canvas layout.
 events.resize();
 rect={...rect,width:1280,height:720};
 for(const observer of observers)observer.callback();
 check(Math.abs(parseFloat(field.style.left)-632*1280/960)<0.01,'composer stayed outside resized canvas');
 check(Math.abs(parseFloat(field.style.width)-304*1280/960)<0.01,'composer kept old width');
 check(field.value==='Keep my draft'&&document.activeElement===field,'resize lost draft or focus');
 const queued=[...observers];
 api.close();
 check(fields.length===0&&document.activeElement===previous,'close leaked field or focus');
 check(observers.size===0,'closed composer kept observing layout');
 for(const observer of queued)observer.callback();
 api.open(()=>{},200);api.place(632,164,304,28,960,540);
 check(fields.length===1&&document.activeElement===fields[0],'composer did not reopen cleanly');
 api.close();check(observers.size===0,'reopened composer leaked observer');
});
