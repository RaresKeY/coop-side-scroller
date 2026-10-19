// Dependency-free, classic-script boot for the Godot Web reference adapter.
// Core readiness is awaited before starting Godot; failures reach its loading notice.
(() => {
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
      command: (handle, operation, a, b) => { calls++; return api.ec_v1_command(handle, operation, a, b); },
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
    copy: (text, finish) => {
      if (typeof text !== 'string' || !text || text.length > 65536 || cancel) { finish(false); return; }
      let settled = false, overlay = null, timer = null;
      const previous = document.activeElement;
      const done = success => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
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
        overlay.style.cssText = 'position:fixed;inset:0;z-index:10000;background:#17212d;color:#fff;display:grid;place-items:center;font:16px sans-serif;';
        const panel = document.createElement('div');
        panel.style.cssText = 'width:min(480px,calc(100vw - 64px));padding:24px;border:1px solid #43545d;';
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
        copy.onclick = () => {
          // Compatibility fallback runs synchronously in the trusted DOM click.
          const field = document.createElement('textarea');
          field.value = text;
          field.setAttribute('readonly', '');
          field.style.cssText = 'position:fixed;left:-10000px;top:0;';
          document.body.appendChild(field);
          let copied = false;
          try { field.select(); copied = document.execCommand('copy'); }
          catch { copied = false; }
          finally { field.value = ''; field.remove(); }
          if (copied) done(true);
          else { hint.textContent = 'Copy was blocked. Cancel and select the code in the setup screen.'; copy.focus(); }
        };
        close.onclick = () => done(false);
        overlay.onkeydown = event => {
          if (event.key === 'Escape') { event.preventDefault(); done(false); }
          if (event.key === 'Tab') { event.preventDefault(); (document.activeElement === copy ? close : copy).focus(); }
        };
        panel.append(title, hint, copy, close);
        overlay.append(panel);
        document.body.append(overlay);
        copy.focus();
      };
      timer = setTimeout(fallback, 5000);
      try { Promise.resolve(navigator.clipboard.writeText(text)).then(() => done(true), fallback); }
      catch { fallback(); }
    },
  });
})();
