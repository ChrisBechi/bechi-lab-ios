// Origin-scoped AndroidX WebMessageListener; no JavaScriptInterface is exposed.
// Reads run inside the provider's own frame, preserving its normal session.
(() => {
  'use strict';
  const bridge = window.bechiHosted;
  if (!bridge) return;
  let ownerDocument = '';
  window.__bechiAndroidPost = value => {
    if (typeof value.document === 'string') ownerDocument = value.document;
    bridge.postMessage(JSON.stringify(value));
  };
  bridge.onmessage = async event => {
    let command;
    try { command = JSON.parse(event.data); } catch { return; }
    if (command.type === 'configure') {
      window.__bechiConfigureHosted?.(command.target);
      return;
    }
    if (command.type !== 'read' || command.epoch !== window.__bechiHostedTarget?.epoch ||
        typeof command.request !== 'string' || typeof command.url !== 'string') return;
    const identity = {epoch: command.epoch, request: command.request,
      document: ownerDocument, documentURL: location.href};
    try {
      const result = await window.__bechiReadHosted(command.url, command.range || null, __BECHI_BINARY__);
      if (command.epoch !== window.__bechiHostedTarget?.epoch) return;
      if (__BECHI_BINARY__ && result.data instanceof ArrayBuffer) {
        const {data, ...metadata} = result;
        const header = new TextEncoder().encode(JSON.stringify({type: 'readResult', ...identity, payload: metadata}));
        if (header.length > 4096 || data.byteLength > 16777216) throw Error('SOURCE_SIZE');
        const packet = new Uint8Array(4 + header.length + data.byteLength);
        new DataView(packet.buffer).setUint32(0, header.length, true);
        packet.set(header, 4); packet.set(new Uint8Array(data), 4 + header.length);
        bridge.postMessage(packet.buffer);
      } else {
        bridge.postMessage(JSON.stringify({type: 'readResult', ...identity, payload: result}));
      }
    } catch {
      bridge.postMessage(JSON.stringify({type: 'readError', ...identity}));
    }
  };
})();
