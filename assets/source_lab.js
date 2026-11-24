async function bechiSourceLab(config) {
  'use strict';
  const notify = value => { try { window.flutter_inappwebview?.callHandler('bechiLabStatus', value)?.catch(() => {}); } catch {} };
  const normalize = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const isApp = location.origin === config.origin && window === window.top;
  const isProvider = location.origin === 'https://superflixapi.boats' &&
    /^\/serie\/[1-9][0-9]{0,8}(?:\/[1-9][0-9]?\/[1-9][0-9]{0,2})?$/.test(location.pathname) && config.id.startsWith('superflix-');
  const isPlayer = ['https://xn--tckasiu6cvova0eb5fua2449g98vg.best', 'https://xn--80adalaab0boiodbce7addhh.delivery', 'https://abyssplayer.com'].includes(location.origin);
  if (!isApp && !isProvider && !isPlayer) return;
  const watch = () => {
    for (const video of document.querySelectorAll('video')) {
      if (video.dataset.bechiLabWatched) continue;
      video.dataset.bechiLabWatched = '1';
      for (const [event, state] of [['playing', 'playing'], ['pause', 'paused'], ['waiting', 'buffering'], ['error', 'error']]) video.addEventListener(event, () => notify(state));
    }
  };
  const timer = setInterval(watch, 1200); watch();
  addEventListener('pagehide', () => clearInterval(timer), {once: true});
  if (config.id === 'c7' && location.origin === 'https://abyssplayer.com') {
    let qualityChosen = false, playing = false, attempts = 0;
    const prepare = setInterval(() => {
      if (++attempts > 40) {clearInterval(prepare); return;}
      if (document.querySelector('.cf-turnstile,iframe[src*="challenges.cloudflare.com"]')) return;
      if (!new RegExp('^Berlim T01_EP-' + String(config.episode).padStart(2, '0') + '_Dublado_').test(document.title)) return;
      const container = document.querySelector('.jwplayer[id]');
      if (!container || typeof window.jwplayer !== 'function') return;
      try {
        const player = window.jwplayer(container.id);
        const levels = (player.getQualityLevels?.() || []).map((level, id) => ({id, height: Number(level.height) || Number(/(\d{3,4})p?/i.exec(level.label || '')?.[1]) || 0})).filter(level => level.height > 0);
        if (!levels.length) return;
        if (!qualityChosen) {
          const preferred = levels.filter(level => level.height <= 1080).sort((a, b) => b.height - a.height)[0] || levels.sort((a, b) => b.height - a.height)[0];
          if (player.getCurrentQuality?.() !== preferred.id) player.setCurrentQuality(preferred.id);
          qualityChosen = true;
        }
        if (!playing) {player.play(true); playing = true; clearInterval(prepare);}
      } catch {}
    }, 1000);
    addEventListener('pagehide', () => clearInterval(prepare), {once: true});
    return;
  }
  if (isProvider) {
    let started = false;
    const expected = config.id === 'superflix-sereias' ? '246992' : '71225';
    if (location.pathname.split('/')[2] !== expected) return;
    const prepare = setInterval(async () => {
      if (started || typeof window.fetchBootstrapOptions !== 'function' || window.API_URL_SOURCE !== '/player/source') return;
      const address = location.pathname.split('/'), season = Number(address[3] || config.season), number = Number(address[4] || config.episode);
      const episode = window.ALL_EPISODES?.[season]?.find(item => Number(item.epi_num) === number);
      if (!episode || !Number.isSafeInteger(episode.ID) || episode.ID <= 0) return;
      started = true; clearInterval(prepare); notify('principal');
      try {
        const rows = await new Promise((resolve, reject) => {
          const timeout = setTimeout(() => reject(Error('timeout')), 12000);
          window.fetchBootstrapOptions(episode.ID, rows => {clearTimeout(timeout); resolve(rows);}, () => {clearTimeout(timeout); reject(Error('source'));});
        });
        const principal = rows.find(item => String(item.type) === '1' && !item.can_download && !item.is_fake && !item.is_fallback_mode);
        if (!principal || !window.requirePageTokenClient || !window.sfEdgeHeaders || !window.openIframe) throw Error('source');
        const token = window.requirePageTokenClient(); if (!token) throw Error('session');
        const body = new URLSearchParams({video_id: String(principal.ID), page_token: token,
          host: window.OWNER_CONTEXT_HOST || '', site: window.OWNER_CONTEXT_HOST || '', _token: window.CSRF_TOKEN || ''});
        const response = await fetch('/player/source', {method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error',
          headers: {...window.sfEdgeHeaders(token), 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'}, body, signal: AbortSignal.timeout(15000)});
        if (!response.ok) throw Error('denied');
        const text = await response.text(); if (text.length > 262144) throw Error('size');
        const data = JSON.parse(text)?.data, url = new URL(data?.video_url, location.origin);
        if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
            !(url.origin === location.origin && /^\/player\/redirect(?:\/|$)/.test(url.pathname) ||
              ['xn--tckasiu6cvova0eb5fua2449g98vg.best', 'xn--80adalaab0boiodbce7addhh.delivery'].includes(url.hostname) && /^\/video\/[a-f0-9]{32}$/.test(url.pathname))) throw Error('player');
        window.openIframe(url.href, data.fireplayer_ad_control || null);
      } catch { notify('manual'); }
    }, 1000);
    addEventListener('pagehide', () => clearInterval(prepare), {once: true});
    return;
  }
  if (!isApp || config.liveId || location.pathname.startsWith('/assistir/')) return;
  if (config.sourceType === 'torrent' && location.pathname.startsWith('/titulo/')) {notify('magnet'); return;}
  const api = async path => {
    const response = await fetch('/api/v1/' + path, {credentials: 'same-origin', cache: 'no-store', signal: AbortSignal.timeout(20000)});
    if (response.status === 401 || response.status === 403) throw Error('login'); if (!response.ok) throw Error('source');
    return (await response.json()).data;
  };
  let running = false;
  const open = setInterval(async () => {
    if (running) return; running = true;
    try {
      notify('search');
      const search = config.slug ? {items: [{slug: config.slug, release_year: config.year, name: config.query}]}
        : await api('search?q=' + encodeURIComponent(config.query) + '&limit=12');
      const titles = (search.items || []).filter(title => !config.year || title.release_year === config.year)
        .sort((a, b) => Number(normalize(b.name) === normalize(config.query)) - Number(normalize(a.name) === normalize(config.query)));
      for (const result of titles.slice(0, 4)) {
        const title = await api('titles/' + encodeURIComponent(result.slug));
        if (config.sourceType === 'torrent') {clearInterval(open); notify('magnet'); location.replace('/titulo/' + title.slug); return;}
        let streams = title.streams || [];
        if (title.kind === 'series') {
          const seasons = await api('titles/' + title.id + '/seasons');
          streams = seasons.find(item => item.season_number === config.season)?.episodes?.find(item => item.episode_number === config.episode)?.streams || [];
        }
        const source = streams.find(stream => stream.source_type === config.sourceType && stream.available !== false);
        if (!source || !/^[a-f0-9-]{36}$/i.test(source.id)) continue;
        clearInterval(open); notify('source');
        if (config.id.startsWith('superflix-')) sessionStorage.setItem('bechi.superflix.web-player', 'official');
        location.replace('/assistir/' + source.id); return;
      }
      clearInterval(open); notify('missing');
    } catch (error) {
      if (error.message === 'login') {notify('login'); running = false;}
      else {clearInterval(open); notify('error');}
    }
  }, 3000);
  addEventListener('pagehide', () => clearInterval(open), {once: true});
}
