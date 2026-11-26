// Provider-session adapter. Video rendering and controls live in native Flutter.
// Never click, solve, change or fabricate a human-verification grant.
(() => {
  'use strict';
  const players = new Set(['xn--tckasiu6cvova0eb5fua2449g98vg.best', 'xn--80adalaab0boiodbce7addhh.delivery']);
  const doc = crypto.getRandomValues(new Uint32Array(4)).join('-');
  const providerAddresses = new Map();
  let target = window.__bechiHostedTarget, busy = false, prepared = '', sent = '', human = false, failed = false, announced = false;
  const normalize = value => String(value).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  function post(type, extra = {}) {
    window.webkit?.messageHandlers?.bechiHosted?.postMessage({type, document: doc, documentURL: location.href, epoch: target?.epoch, ...extra});
  }
  function rootPage() {
    return target?.kind === 'superflix' && location.origin === 'https://superflixapi.boats' && [target.root, target.url].includes(location.origin + location.pathname);
  }
  function playerPage() {
    return target?.kind === 'c7' && location.origin + location.pathname === target.url || target?.kind === 'superflix' && players.has(location.hostname) && /^\/video\/[a-f0-9]{32}$/.test(location.pathname);
  }
  function allowedMedia(value) {
    try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password && !u.port; } catch { return false; }
  }
  window.addEventListener?.('message', event => {
    // Observe the widget's real request for interaction. Never click it or
    // handle its response token; validation remains in the official document.
    if (event.origin !== 'https://challenges.cloudflare.com' ||
        event.data?.source !== 'cloudflare-challenge' || event.data?.event !== 'interactiveBegin' ||
        !event.source || event.source === window ||
        !rootPage() && !playerPage() || human) return;
    human = true; post('human');
  });
  function protect() {
    if (!rootPage() && !playerPage()) return;
    window.open = () => null;
    document.addEventListener('click', event => {
      const a = event.target?.closest?.('a[target="_blank"]');
      if (a) { event.preventDefault(); event.stopImmediatePropagation(); }
    }, true);
  }
  async function principal(page) {
    const movie = page.movie, id = movie ? window.CURRENT_EPISODE?.ID || (typeof INITIAL_CONTENT_ID === 'number' ? INITIAL_CONTENT_ID : undefined) : window.ALL_EPISODES?.[page.season]?.find(e => Number(e.epi_num) === page.episode)?.ID;
    if (!Number.isSafeInteger(id) || id <= 0 || typeof window.fetchBootstrapOptions !== 'function' || typeof window.requirePageTokenClient !== 'function' || typeof window.sfEdgeHeaders !== 'function' || window.API_URL_SOURCE !== '/player/source') return false;
    const rows = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(Error('SOURCE_OPTIONS_TIMEOUT')), 20000);
      window.fetchBootstrapOptions(id, rows => { clearTimeout(timer); resolve(rows); }, () => { clearTimeout(timer); reject(Error('SOURCE_OPTIONS')); });
    });
    if (target.epoch !== page.epoch) return false;
    const row = rows.find(v => String(v.type) === '1' && !v.can_download && !v.is_fake && !v.is_fallback_mode);
    if (!row || !String(row.ID)) throw Error('SOURCE_PRINCIPAL');
    const token = window.requirePageTokenClient();
    if (!token) throw Error('SOURCE_SESSION');
    const body = new URLSearchParams({video_id: String(row.ID), page_token: token, host: window.OWNER_CONTEXT_HOST || '', site: window.OWNER_CONTEXT_HOST || '', _token: window.CSRF_TOKEN || ''});
    const response = await fetch('/player/source', {method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: {...window.sfEdgeHeaders(token), 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'}, body, signal: AbortSignal.timeout(20000)});
    if (!response.ok) throw Error('SOURCE_AUTHORIZATION');
    const text = await response.text(); if (text.length > 262144) throw Error('SOURCE_SIZE');
    const data = JSON.parse(text)?.data, u = new URL(data?.video_url, location.origin);
    if (u.protocol !== 'https:' || u.username || u.password || u.port || u.hash || !(u.origin === location.origin && /^\/player\/redirect(?:\/|$)/.test(u.pathname) || players.has(u.hostname) && /^\/video\/[a-f0-9]{32}$/.test(u.pathname))) throw Error('SOURCE_PLAYER');
    if (target.epoch !== page.epoch) return false;
    window.openIframe(u.href, data.fireplayer_ad_control || null);
    return true;
  }
  async function inspect() {
    if (!target) return;
    if (!announced && (rootPage() || playerPage())) { announced = true; post('loaded'); }
    if (location.hostname === 'challenges.cloudflare.com') {
      // Observation only. The actual person taps the actual WebKit view.
      const check = document.querySelector('input[type="checkbox"]:not(:checked):not(:disabled),[role="checkbox"][aria-checked="false"]');
      if (!human && check?.getClientRects().length) { human = true; post('human'); }
      return;
    }
    if (rootPage() && !busy && !failed && prepared !== target.epoch) {
      if (!target.movie && typeof window.renderEpisodes !== 'function' || target.movie && typeof window.fetchBootstrapOptions !== 'function') return;
      const requested = target;
      post('validated'); protect(); busy = true;
      try {
        if (!target.movie) {
          window.closePlayer?.();
          const select = [...document.querySelectorAll('select')].find(s => [...s.options].some(o => o.value === String(target.season)));
          if (select) select.value = String(target.season);
          window.renderEpisodes(target.season);
        }
        if (await principal(requested)) prepared = requested.epoch;
      } catch (error) { if (target.epoch === requested.epoch) { failed = true; post('failure', {code: /^SOURCE_[A-Z_]+$/.test(error.message) ? error.message : 'SOURCE_PREPARATION'}); } }
      finally { if (target.epoch === requested.epoch) busy = false; }
    }
    if (!playerPage() || sent === target.epoch) return;
    const box = document.querySelector('.jwplayer[id]'), p = box && typeof window.jwplayer === 'function' && window.jwplayer(box.id);
    if (!p) return;
    const config = p.getConfig?.() || {}, item = p.getPlaylistItem?.() || {}, name = config.title || document.title;
    const identity = /(\d+)\s*x\s*(\d+)/i.exec(name);
    const matches = target.kind === 'c7' ? new RegExp(`^Berlim T01_EP-${String(target.episode).padStart(2, '0')}_Dublado_`).test(document.title) : normalize(name).includes(normalize(target.expectedTitle)) && (target.movie || identity && Number(identity[1]) === target.season && Number(identity[2]) === target.episode);
    if (!matches) return;
    const rows = (item.sources?.length ? item.sources : item.file ? [{file: item.file, type: 'hls'}] : config.sources || []).filter(v => allowedMedia(v.file));
    if (!rows.length) return;
    protect(); p.pause?.(true); p.setMute?.(true);
    // Use the provider's public ad API. No episode seeking or forged ad grant.
    if (typeof p.skipAdBreak === 'function') setTimeout(() => { try { p.skipAdBreak(); } catch {} }, 0);
    const variants = rows.map(v => {
      // Provider-only fragment metadata stays in this document. The native
      // transport sees an address; reads retain the provider's original input.
      const media = new URL(v.file); media.hash = '';
      providerAddresses.set(media.href, v.file);
      return {url: media.href, height: Number.parseInt(v.label) || 0, label: v.label || 'Automática', type: v.type || (media.pathname.includes('.m3u8') ? 'hls' : 'mp4')};
    }).sort((a, b) => b.height - a.height);
    sent = target.epoch; post('ready', {url: variants[0].url, variants, title: name, format: target.kind === 'c7' || variants[0].type === 'mp4' ? 'mp4' : 'hls'});
  }
  window.__bechiConfigureHosted = next => { target = window.__bechiHostedTarget = next; prepared = sent = ''; providerAddresses.clear(); busy = false; human = false; failed = false; void inspect(); };
  window.__bechiReadHosted = async (url, range, binary = false) => {
    if (!playerPage() || !allowedMedia(url) || sent !== target.epoch || range && !/^bytes=\d+-\d*$/.test(range)) throw Error('SOURCE_READ');
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 25000);
    try {
      const response = await fetch(providerAddresses.get(url) || url, {credentials: 'same-origin', redirect: 'error', headers: range ? {Range: range} : {}, signal: controller.signal});
      if (![200, 206, 416].includes(response.status)) return {status: response.status};
      const reader = response.body?.getReader(), chunks = []; let length = 0;
      if (reader) try { for (;;) { const part = await reader.read(); if (part.done) break; if ((length += part.value.length) > 16777216) throw Error('SOURCE_SIZE'); chunks.push(part.value); } } finally { await reader.cancel(); }
      const bytes = new Uint8Array(length); let offset = 0; for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      if (binary) return {status: response.status, type: response.headers.get('content-type'), range: response.headers.get('content-range'), data: bytes.buffer};
      let text = ''; for (let i = 0; i < bytes.length; i += 32768) text += String.fromCharCode(...bytes.subarray(i, i + 32768));
      return {status: response.status, type: response.headers.get('content-type'), range: response.headers.get('content-range'), data: btoa(text)};
    } finally { clearTimeout(timer); }
  };
  document.addEventListener('DOMContentLoaded', () => void inspect(), {once: true});
  setInterval(() => void inspect(), 500);
  void inspect();
})();
