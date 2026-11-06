const source=await Deno.readTextFile(new URL('../adapters/web/ember_core_bridge.js',import.meta.url));
const check=(ok,message)=>{if(!ok)throw Error(message);};
Deno.test('Invite field supports passwords, isolates pending/stale submits and erases closed fields',()=>{
 const nodes=[],observers=new Set(),messages=[];
 const canvas={getBoundingClientRect:()=>({left:0,top:0,width:960,height:540}),focus(){}};
 const document={activeElement:canvas,querySelector:()=>canvas,body:{append(node){nodes.push(node);}},
 createElement(tag){return {tagName:tag.toUpperCase(),style:{},dataset:{},value:'',children:[],setAttribute(){},
  append(node){this.children.push(node);},focus(){document.activeElement=this;},blur(){document.activeElement=canvas;},
  remove(){const i=nodes.indexOf(this);if(i>=0)nodes.splice(i,1);}};}};
 class ResizeObserver{constructor(f){this.callback=f;}observe(){observers.add(this);}disconnect(){observers.delete(this);}}
 const scope={addEventListener(){}};
 Object.defineProperty(scope,'localStorage',{get(){throw Error('credential persistence attempted');}});
 Object.defineProperty(scope,'sessionStorage',{get(){throw Error('credential persistence attempted');}});
 new Function('globalThis','document','ResizeObserver',source.slice(source.indexOf('// Password-manager compatible invite entry')))(scope,document,ResizeObserver);
 const api=scope.EmberInviteField;
 api.open((...args)=>messages.push(args),128);api.place(300,220,360,42,960,540);
 const field=nodes[0].children[0];
 check(field.type==='password'&&field.autocomplete==='current-password'&&field.maxLength===128,'password field semantics missing');
 check(field===document.activeElement,'invite did not receive initial focus');
 const event=key=>({key,isComposing:false,preventDefault(){},stopPropagation(){}});
 field.value='a'.repeat(64);field.onkeydown(event('Enter'));
 check(messages.length===1&&messages[0][0]==='submit','Enter did not submit');
 api.setBusy(true);field.onkeydown(event('Enter'));check(messages.length===1,'pending submit overlapped');
 api.setBusy(false);check(document.activeElement===field&&!field.disabled,'retry lost keyboard focus');
 const stale=field.onkeydown;api.close();
 check(field.value===''&&nodes.length===0&&observers.size===0,'closing retained password/DOM observer');
 api.open((...args)=>messages.push(args),128);api.place(300,220,360,42,960,540);
 nodes[0].children[0].value='b'.repeat(64);stale(event('Enter'));
 check(messages.length===1,'detached invite field submitted a new session');
 api.close();
});
