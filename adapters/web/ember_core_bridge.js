// Dependency-free, classic-script boot for the Godot Web reference adapter.
// Core readiness is awaited before starting Godot; failures reach its loading notice.
(() => {
  // Bounded ICE metadata for successful and failed attempts. No addresses/SDP/URLs.
  let diagnosticPeer = null, diagnosticEvents = [];
  const bounded = n => Number.isFinite(n) ? Math.min(2147483647, Math.max(0, Math.round(n))) : 0;
  const candidateType = value => ['host','srflx','prflx','relay'].includes(value) ? value : 'unknown';
  const protocol = value => ['udp','tcp'].includes(value) ? value : 'unknown';
  const enqueue = (peer, event) => {
    if (peer !== diagnosticPeer) return;
    diagnosticEvents.push(event);
    if (diagnosticEvents.length > 64) diagnosticEvents.shift();
  };
  const stateEvent = peer => ({event:'ice_state',
    gathering:['new','gathering','complete'].includes(peer.iceGatheringState)?peer.iceGatheringState:'unknown',
    ice:['new','checking','connected','completed','disconnected','failed','closed'].includes(peer.iceConnectionState)?peer.iceConnectionState:'unknown'});
  const BrowserRTC = globalThis.RTCPeerConnection;
  if (BrowserRTC) globalThis.RTCPeerConnection = class extends BrowserRTC {
    constructor(...args) {
      super(...args);
      diagnosticPeer = this;
      diagnosticEvents = [];
      enqueue(this,stateEvent(this));
      const candidates={host:0,srflx:0,prflx:0,relay:0};
      this.addEventListener('icecandidate',event=>{
        if(this!==diagnosticPeer)return;
        const type=candidateType(event.candidate?.type);
        if(type!=='unknown')candidates[type]=bounded(candidates[type]+1);
        enqueue(this,{event:'ice_candidates',...candidates});
      });
      for (const name of ['icegatheringstatechange','iceconnectionstatechange'])
        this.addEventListener(name,()=>enqueue(this,stateEvent(this)));
      this.addEventListener('icecandidateerror',event=>{
        // Keep only the scheme; URL, errorText, address and port may contain private data.
        const scheme = /^(stun|turn|turns):/.exec(typeof event.url==='string'?event.url:'')?.[1] || 'unknown';
        enqueue(this,{event:'ice_error',server:scheme,code:Math.min(65535,bounded(event.errorCode))});
      });
    }
  };
  globalThis.EmberConnectionDiagnostics = Object.freeze({
    reset: () => { diagnosticPeer = null; diagnosticEvents = []; },
    drain: () => { const events=diagnosticEvents;diagnosticEvents=[];return JSON.stringify(events); },
    sample: async finish => {
      const peer=diagnosticPeer;
      if (!peer) return;
      try {
        const stats=await peer.getStats();
        if (peer!==diagnosticPeer) return;
        const summary={event:'ice_stats',host:0,srflx:0,prflx:0,relay:0,pairs:0,failed:0,checking:0,succeeded:0,requests:0,responses:0};
        for (const stat of stats.values()) {
          if (stat.type==='local-candidate' && candidateType(stat.candidateType)!=='unknown') summary[stat.candidateType]++;
          if (stat.type==='candidate-pair') {
            summary.pairs++;
            if (stat.state==='failed') summary.failed++;
            if (['waiting','in-progress','frozen'].includes(stat.state)) summary.checking++;
            if (stat.state==='succeeded') summary.succeeded++;
            summary.requests=bounded(summary.requests+bounded(stat.requestsSent));
            summary.responses=bounded(summary.responses+bounded(stat.responsesReceived));
          }
        }
        enqueue(peer,summary);
        const transport=[...stats.values()].find(x=>x.type==='transport'&&x.selectedCandidatePairId);
        const pair=stats.get(transport?.selectedCandidatePairId);
        if (!pair) return;
        const local=stats.get(pair.localCandidateId),remote=stats.get(pair.remoteCandidateId);
        finish(JSON.stringify({local:candidateType(local?.candidateType),remote:candidateType(remote?.candidateType),protocol:protocol(local?.protocol),rtt:bounded((pair.currentRoundTripTime||0)*1000)}));
      } catch {
        enqueue(peer,{event:'ice_stats_unavailable'});
      }
    },
  });
  const wasmURL = new URL('ember_core.wasm', document.currentScript.src);
  globalThis.EmberCoreWebReady = (async () => {
    const response = await fetch(wasmURL);
    if (!response.ok) throw new Error(`Portable core download failed: ${response.status}`);
    const {module, instance} = await WebAssembly.instantiate(await response.arrayBuffer(), {});
    if (WebAssembly.Module.imports(module).length !== 0) throw new Error('Unexpected portable core imports');
    const api = instance.exports;
    if (api.ec_v1_abi_version() !== 0x10000) throw new Error('Portable core ABI mismatch');
    const handles = new Set();
    let calls = 0;
    globalThis.EmberCoreWeb = Object.freeze({
      create: () => { const h = api.ec_v1_create(0x10000, 1, 1); if (h) handles.add(h); return h; },
      command: (handle, operation, a=0, b=0) => {
        if (!handles.has(handle)) return -1;
        if (![operation,a,b].every(n => Number.isInteger(n) && n >= -2147483648 && n <= 2147483647)) return -2;
        calls++;
        return api.ec_v1_command(handle, operation, a, b);
      },
      destroy: (handle) => { api.ec_v1_destroy(handle); handles.delete(handle); },
      diagnostics: () => ({calls, live: handles.size, views: [...handles].map(h => ({tick: api.ec_v1_command(h,10,0,0), x: api.ec_v1_command(h,10,3,1), guestX: api.ec_v1_command(h,10,3,2), actors: api.ec_v1_command(h,10,2,1) + api.ec_v1_command(h,10,2,2), hp: api.ec_v1_command(h,10,1,0)}))}),
    });
    return globalThis.EmberCoreWeb;
  })();
})();

// Clipboard needs a trusted DOM click on some browsers; keep it in this adapter.
globalThis.EmberClipboard = (() => {
  let cancel = null;
  return Object.freeze({
    cancel: () => { if (cancel) cancel(); },
    paste: (titleText, finish, initial = "", limit = 65536, secret = false) => {
      if (cancel) return;
      const previous = document.activeElement;
      const overlay = document.createElement('div');
      overlay.setAttribute('role', 'dialog');
      overlay.setAttribute('aria-modal', 'true');
      overlay.setAttribute('aria-label', titleText);
      overlay.style.cssText = 'position:fixed;inset:0;z-index:10000;background:rgba(8,14,22,.65);color:#fff;display:grid;place-items:center;font:16px sans-serif;';
      const panel = document.createElement('div');
      panel.style.cssText = 'box-sizing:border-box;width:min(560px,calc(100vw - 32px));max-height:calc(100dvh - 32px);overflow:auto;padding:24px;background:#17212d;border:1px solid #43545d;border-radius:8px;';
      const title = document.createElement('h2');
      title.textContent = titleText;
      const hint = document.createElement('p');
      hint.textContent = limit <= 128 ? 'Type or paste below, then press Enter or Continue.' : 'Paste your partner’s entire code below, then Continue.';
      const field = document.createElement(limit <= 128 ? 'input' : 'textarea');
      if (field.tagName === 'INPUT') field.type = secret ? 'password' : 'text';
      field.autocomplete = 'off';
      field.setAttribute('autocapitalize', 'off');
      field.setAttribute('aria-label', titleText);
      field.dataset.emberPaste = '';
      field.maxLength = limit;
      field.value = initial.slice(0, limit);
      field.spellcheck = false;
      field.style.cssText = 'box-sizing:border-box;width:100%;min-height:44px;font:16px monospace;';
      if (field.tagName === 'TEXTAREA') field.style.height = '140px';
      const accept = document.createElement('button');
      accept.textContent = 'Continue';
      accept.dataset.emberAccept = '';
      accept.disabled = !field.value.trim();
      const close = document.createElement('button');
      close.textContent = 'Cancel';
      for (const button of [accept, close]) button.style.cssText = 'min-height:44px;padding:8px 20px;margin:12px 12px 0 0;';
      field.oninput = () => { accept.disabled = !field.value.trim(); };
      const done = value => {
        field.value = '';
        overlay.remove();
        cancel = null;
        previous?.focus();
        finish(value);
      };
      cancel = () => done('');
      accept.onclick = () => done(field.value.trim());
      close.onclick = cancel;
      overlay.onkeydown = event => {
        event.stopPropagation();
        if (event.key === 'Enter' && event.target === field && !event.isComposing && field.tagName === 'INPUT' && !accept.disabled) { event.preventDefault(); done(field.value.trim()); }
        if (event.key === 'Escape') { event.preventDefault(); done(''); }
        if (event.key === 'Tab') {
          event.preventDefault();
          const focus = [field, accept, close].filter(x => !x.disabled);
          const next = (focus.indexOf(document.activeElement) + (event.shiftKey ? focus.length - 1 : 1)) % focus.length;
          focus[next].focus();
        }
      };
      panel.append(title, hint, field, accept, close);
      overlay.append(panel);
      document.body.append(overlay);
      field.focus();
      field.select();
    },
    copy: (text, finish) => {
      if (typeof text !== 'string' || !text || text.length > 65536 || cancel) { finish(false); return; }
      let settled = false, overlay = null, timer = null, codeField = null;
      const previous = document.activeElement;
      const done = success => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (codeField) codeField.value = '';
        overlay?.remove();
        overlay = null;
        text = '';
        cancel = null;
        previous?.focus();
        finish(success);
      };
      cancel = () => done(false);
      const fallback = () => {
        if (settled || overlay) return;
        clearTimeout(timer);
        overlay = document.createElement('div');
        overlay.setAttribute('role', 'dialog');
        overlay.setAttribute('aria-modal', 'true');
        overlay.setAttribute('aria-label', 'Copy connection code');
        overlay.style.cssText = 'position:fixed;inset:0;z-index:10000;background:rgba(8,14,22,.65);color:#fff;display:grid;place-items:center;font:16px sans-serif;';
        const panel = document.createElement('div');
        panel.style.cssText = 'box-sizing:border-box;width:min(560px,calc(100vw - 32px));max-height:calc(100dvh - 32px);overflow:auto;padding:24px;background:#17212d;border:1px solid #43545d;border-radius:8px;';
        const title = document.createElement('h2');
        title.textContent = 'Copy connection code';
        const hint = document.createElement('p');
        hint.textContent = 'Your browser needs a direct click to copy. Share the code privately with your partner.';
        const copy = document.createElement('button');
        copy.textContent = 'Copy code';
        copy.dataset.emberCopy = '';
        copy.style.cssText = 'min-height:44px;padding:8px 20px;margin-right:12px;';
        const close = document.createElement('button');
        close.textContent = 'Cancel';
        close.dataset.emberCancel = '';
        close.style.cssText = 'min-height:44px;padding:8px 20px;';
        const field = document.createElement('textarea');
        codeField = field;
        field.value = text;
        field.setAttribute('readonly', '');
        field.setAttribute('aria-label', 'Your connection code');
        field.style.cssText = 'box-sizing:border-box;width:100%;height:100px;margin-bottom:16px;';
        copy.onclick = () => {
          // Compatibility fallback runs synchronously in the trusted DOM click.
          let copied = false;
          try { field.select(); copied = document.execCommand('copy'); }
          catch { copied = false; }
          if (copied) { field.value = ''; done(true); }
          else { hint.textContent = 'Select the code above and use Ctrl+C or your browser’s Copy command.'; field.focus(); field.select(); }
        };
        close.onclick = () => done(false);
        overlay.onkeydown = event => {
          event.stopPropagation();
          if (event.key === 'Escape') { event.preventDefault(); done(false); }
          if (event.key === 'Tab') {
            event.preventDefault();
            const focus = [field, copy, close];
            focus[(focus.indexOf(document.activeElement) + (event.shiftKey ? 2 : 1)) % 3].focus();
          }
        };
        panel.append(title, hint, field, copy, close);
        overlay.append(panel);
        document.body.append(overlay);
        copy.focus();
      };
      timer = setTimeout(fallback, 5000);
      // Once the fallback is visible, only its explicit actions may dismiss it.
      try { Promise.resolve(navigator.clipboard.writeText(text)).then(() => { if (!overlay) done(true); }, fallback); }
      catch { fallback(); }
    },
  });
})();
