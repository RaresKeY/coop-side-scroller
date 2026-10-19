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

// Browser clipboard fallback stays outside simulation. execCommand preserves
// Firefox's native Copy path where asynchronous Clipboard API access is denied.
globalThis.EmberClipboard = Object.freeze({
  copy: (text) => {
    if (typeof text !== 'string' || text.length > 65536) return false;
    const previous = document.activeElement;
    const field = document.createElement('textarea');
    field.value = text;
    field.setAttribute('readonly', '');
    field.style.cssText = 'position:fixed;left:-10000px;top:0;';
    document.body.appendChild(field);
    let copied = false;
    try { field.select(); copied = document.execCommand('copy'); }
    catch { copied = false; }
    finally { field.value = ''; field.remove(); previous?.focus(); }
    return copied;
  },
});
