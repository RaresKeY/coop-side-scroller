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

Deno.test('Chat editor bounds growth, editing keys, scroll and delayed canvas reflow',()=>{
 let rect={left:0,top:0,width:1920,height:1080};
 const canvas={getBoundingClientRect:()=>rect}, fields=[], observers=new Set(), events={};
 const previous={focus(){document.activeElement=this;}};
 const document={
  activeElement:previous,
  querySelector:selector=>selector==='canvas'?canvas:null,
  body:{append(field){fields.push(field);}},
  createElement(tag){return {
   tagName:tag.toUpperCase(),scrollHeight:28,scrollTop:0,selectionEnd:0,
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
 const outcomes=[];
 api.open((...args)=>outcomes.push(args),200);
 api.place(632,164,304,28,960,540);
 const editor=fields[0];editor.value='Keep my draft';editor.scrollHeight=500;editor.selectionEnd=editor.value.length;editor.oninput();
 check(editor.tagName==='TEXTAREA','chat editor stayed single-line');
 editor.scrollTop=9;events.resize();check(editor.scrollTop===9,'layout stole draft scroll position');
 check(parseFloat(editor.style.height)>56&&parseFloat(editor.style.height)<=168,'draft did not grow within its cap');
 const key=(key,shiftKey=false,isComposing=false)=>({key,shiftKey,isComposing,preventDefault(){this.prevented=true;},stopPropagation(){this.stopped=true;}});
 const newline=key('Enter',true);editor.onkeydown(newline);check(!newline.prevented,'Shift+Enter was intercepted');
 const composing=key('Enter',false,true);editor.onkeydown(composing);check(!composing.prevented,'IME confirmation submitted text');
 const send=key('Enter');editor.onkeydown(send);check(send.prevented&&outcomes.at(-1)[0]==='send','Enter did not submit');
 const cancel=key('Escape');editor.onkeydown(cancel);check(cancel.prevented&&outcomes.at(-1)[0]==='cancel','Escape did not cancel');
 const wheel=key('wheel');editor.onwheel(wheel);check(wheel.stopped&&!wheel.prevented,'wheel did not retain native editor scrolling');
 editor.scrollHeight=28;editor.oninput();

 check(document.activeElement===editor,'composer did not focus');
 check(parseFloat(editor.style.left)===1264,'initial composer alignment');
 // The window event precedes Godot applying the new canvas layout.
 events.resize();
 rect={...rect,width:1280,height:720};
 for(const observer of observers)observer.callback();
 check(Math.abs(parseFloat(editor.style.left)-632*1280/960)<0.01,'composer stayed outside resized canvas');
 check(Math.abs(parseFloat(editor.style.width)-304*1280/960)<0.01,'composer kept old width');
 check(editor.value==='Keep my draft'&&document.activeElement===editor,'resize lost draft or focus');
 const queued=[...observers];
 api.close();
 check(fields.length===0&&document.activeElement===previous,'close leaked field or focus');
 check(observers.size===0,'closed composer kept observing layout');
 for(const observer of queued)observer.callback();
 api.open(()=>{},200);api.place(632,164,304,28,960,540);
 check(fields.length===1&&document.activeElement===fields[0],'composer did not reopen cleanly');
 api.close();check(observers.size===0,'reopened composer leaked observer');
});
