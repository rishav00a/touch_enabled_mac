// TE Mac — YouTube media control footer (youtube.com only).
// Same iPadOS-style dock as the YouTube Touch Player app, gated by the
// shared TE Mac enabled state. Built with createElement only (Trusted Types).

(() => {
  if (window.__teYtLoaded) return;
  window.__teYtLoaded = true;

  const STORE_KEY = 'te-mac-enabled';

  function loadSetting(cb) {
    try {
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
        chrome.storage.local.get([STORE_KEY], (r) => cb(r[STORE_KEY]));
        return;
      }
    } catch {}
    try { cb(localStorage.getItem(STORE_KEY) || undefined); }
    catch { cb(undefined); }
  }

  function isTouchScreen() {
    return (navigator.maxTouchPoints || 0) > 0 ||
      window.matchMedia('(any-pointer: coarse)').matches;
  }

  function getVideo() {
    return document.querySelector('video.html5-main-video') || document.querySelector('video');
  }

  const YT_SEARCH_SEL = 'input#search, input[name="search_query"], input.ytSearchboxComponentInput';

  function fmtTime(s) {
    if (!isFinite(s)) return '0:00';
    s = Math.max(0, Math.floor(s));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    return h > 0
      ? `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
      : `${m}:${String(sec).padStart(2, '0')}`;
  }

  function el(tag, props = {}, ...children) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'dataset') Object.assign(node.dataset, v);
      else if (k in node) node[k] = v;
      else node.setAttribute(k, v);
    }
    for (const c of children) {
      node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return node;
  }

  const SVG_NS = 'http://www.w3.org/2000/svg';

  const ICONS = {
    play: 'M8 5.14v13.72c0 .8.87 1.3 1.56.88l10.54-6.86c.63-.4.63-1.36 0-1.76L9.56 4.26C8.87 3.84 8 4.34 8 5.14z',
    pause: 'M7 4.5h3a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1v-13a1 1 0 0 1 1-1zm7 0h3a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-3a1 1 0 0 1-1-1v-13a1 1 0 0 1 1-1z',
    prev: 'M6 6a1 1 0 0 1 2 0v5l9.5-6.3c.66-.44 1.5.04 1.5.83v12.94c0 .8-.84 1.27-1.5.83L8 13v5a1 1 0 0 1-2 0V6z',
    next: 'M18 6a1 1 0 0 0-2 0v5L6.5 4.7C5.84 4.26 5 4.74 5 5.53v12.94c0 .8.84 1.27 1.5.83L16 13v5a1 1 0 0 0 2 0V6z',
    replay10: 'M11.99 5V1.8L7.6 5.6c-.3.26-.3.72 0 .98l4.39 3.8V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6h-2c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z',
    forward10: 'M12.01 5V1.8l4.39 3.8c.3.26.3.72 0 .98l-4.39 3.8V7c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6h2c0 4.42-3.58 8-8 8s-8-3.58-8-8 3.58-8 8-8z',
    home: 'M11.34 3.55a1 1 0 0 1 1.32 0l8 7.11c.7.62.26 1.78-.68 1.78H19v6.56a1 1 0 0 1-1 1h-3.5v-5a1 1 0 0 0-1-1h-3a1 1 0 0 0-1 1v5H6a1 1 0 0 1-1-1v-6.56H4.02c-.94 0-1.38-1.16-.68-1.78l8-7.11z',
    search: 'M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l4.29 4.28a1 1 0 0 0 1.41-1.41L15.5 14zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z',
    fullscreen: 'M8.5 5H6a1 1 0 0 0-1 1v2.5a1 1 0 0 0 2 0V7h1.5a1 1 0 0 0 0-2zM18 5h-2.5a1 1 0 0 0 0 2H17v1.5a1 1 0 0 0 2 0V6a1 1 0 0 0-1-1zM7 15.5a1 1 0 0 0-2 0V18a1 1 0 0 0 1 1h2.5a1 1 0 0 0 0-2H7v-1.5zm12 0a1 1 0 0 0-2 0V17h-1.5a1 1 0 0 0 0 2H18a1 1 0 0 0 1-1v-2.5z',
    volOn: 'M12 4.75a.9.9 0 0 0-1.47-.7L7 7H4a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3l3.53 2.95a.9.9 0 0 0 1.47-.7V4.75zM16.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z',
    volOff: 'M12 4.75a.9.9 0 0 0-1.47-.7L7.6 6.5 12 10.9V4.75zM4.27 3.56a1 1 0 0 0-1.41 1.41L7.59 9.7 7 10.2H4a1 1 0 0 0-1 1v1.6a1 1 0 0 0 1 1h3l3.53 2.95a.9.9 0 0 0 1.47-.7v-3.32l6.4 6.4a1 1 0 0 0 1.41-1.41L4.27 3.56z'
  };

  function svgIcon(name, size = 26, label) {
    const s = document.createElementNS(SVG_NS, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('width', size);
    s.setAttribute('height', size);
    s.setAttribute('fill', 'currentColor');
    s.setAttribute('aria-hidden', 'true');
    const p = document.createElementNS(SVG_NS, 'path');
    p.setAttribute('d', ICONS[name]);
    s.appendChild(p);
    if (label) {
      const t = document.createElementNS(SVG_NS, 'text');
      t.setAttribute('x', '12');
      t.setAttribute('y', '15.5');
      t.setAttribute('text-anchor', 'middle');
      t.setAttribute('font-size', '7');
      t.setAttribute('font-weight', '700');
      t.setAttribute('fill', 'currentColor');
      t.setAttribute('font-family', '-apple-system, sans-serif');
      t.textContent = label;
      s.appendChild(t);
    }
    return s;
  }

  /* ---------- dock ---------- */

  let enabled = false;
  let dock = null;

  function applyEnabled() {
    document.documentElement.classList.toggle('te-yt-on', enabled);
    if (dock) dock.classList.toggle('te-yt-dock-off', !enabled);
  }

  function buildDock() {
    if (document.getElementById('te-yt-dock')) return;

    const timeCur = el('span', { className: 'te-yt-time' }, '0:00');
    const timeDur = el('span', { className: 'te-yt-time' }, '0:00');
    const seekbar = el('input', { type: 'range', id: 'te-yt-seekbar', min: '0', max: '1000', value: '0', step: '1' });
    const volume = el('input', { type: 'range', id: 'te-yt-volume', min: '0', max: '100', value: '100', step: '1', title: 'Volume' });

    const playIcon = svgIcon('play', 34);
    const playPath = playIcon.querySelector('path');
    const volOnIcon = svgIcon('volOn', 24);
    const volOffIcon = svgIcon('volOff', 24);
    volOffIcon.style.display = 'none';

    const homeBtn = el('button', { className: 'te-yt-btn', title: 'Home' }, svgIcon('home'));
    const prevBtn = el('button', { className: 'te-yt-btn', title: 'Previous' }, svgIcon('prev'));
    const rewBtn = el('button', { className: 'te-yt-btn', title: 'Back 10 seconds' }, svgIcon('replay10', 26, '10'));
    const playBtn = el('button', { className: 'te-yt-btn te-yt-play', title: 'Play/Pause' }, playIcon);
    const fwdBtn = el('button', { className: 'te-yt-btn', title: 'Forward 10 seconds' }, svgIcon('forward10', 26, '10'));
    const nextBtn = el('button', { className: 'te-yt-btn', title: 'Next' }, svgIcon('next'));
    const muteBtn = el('button', { className: 'te-yt-btn te-yt-btn-sm', title: 'Mute' }, volOnIcon, volOffIcon);
    const searchBtn = el('button', { className: 'te-yt-btn', title: 'Search' }, svgIcon('search'));
    const fullBtn = el('button', { className: 'te-yt-btn', title: 'Fullscreen' }, svgIcon('fullscreen'));

    dock = el('div', { id: 'te-yt-dock' },
      el('div', { className: 'te-yt-progress' }, timeCur, seekbar, timeDur),
      el('div', { className: 'te-yt-buttons' },
        homeBtn,
        el('div', { className: 'te-yt-group' }, prevBtn, rewBtn, playBtn, fwdBtn, nextBtn),
        el('div', { className: 'te-yt-group' }, muteBtn, volume),
        searchBtn, fullBtn
      )
    );
    document.body.appendChild(dock);
    applyEnabled();

    let scrubbing = false;
    const act = (fn) => (e) => { e.preventDefault(); e.stopPropagation(); fn(); };
    const setFill = (slider, pct) => slider.style.setProperty('--fill', pct + '%');
    setFill(seekbar, 0);
    setFill(volume, 100);

    homeBtn.addEventListener('click', act(() => { location.href = 'https://www.youtube.com/'; }));
    rewBtn.addEventListener('click', act(() => { const v = getVideo(); if (v) v.currentTime -= 10; }));
    fwdBtn.addEventListener('click', act(() => { const v = getVideo(); if (v) v.currentTime += 10; }));

    nextBtn.addEventListener('click', act(() => {
      const btn = document.querySelector('.ytp-next-button');
      if (btn) btn.click();
    }));

    prevBtn.addEventListener('click', act(() => {
      const v = getVideo();
      const btn = document.querySelector('.ytp-prev-button');
      if (btn && btn.getAttribute('aria-disabled') !== 'true') {
        btn.click();
      } else if (v && v.currentTime > 3) {
        v.currentTime = 0;
      } else {
        history.back();
      }
    }));

    playBtn.addEventListener('click', act(() => {
      const v = getVideo();
      if (!v) return;
      v.paused ? v.play() : v.pause();
    }));

    muteBtn.addEventListener('click', act(() => {
      const v = getVideo();
      if (!v) return;
      v.muted = !v.muted;
    }));

    volume.addEventListener('input', () => {
      const v = getVideo();
      setFill(volume, volume.value);
      if (!v) return;
      v.volume = volume.value / 100;
      v.muted = volume.value === '0';
    });

    seekbar.addEventListener('pointerdown', () => { scrubbing = true; });
    seekbar.addEventListener('input', () => {
      setFill(seekbar, seekbar.value / 10);
      const v = getVideo();
      if (v && isFinite(v.duration)) timeCur.textContent = fmtTime((seekbar.value / 1000) * v.duration);
    });
    seekbar.addEventListener('change', () => {
      const v = getVideo();
      if (v && isFinite(v.duration)) v.currentTime = (seekbar.value / 1000) * v.duration;
      scrubbing = false;
    });

    searchBtn.addEventListener('click', act(() => {
      const input = document.querySelector(YT_SEARCH_SEL);
      if (input) {
        window.scrollTo({ top: 0, behavior: 'smooth' });
        input.focus(); // the TE keyboard opens via its own focusin listener
      }
    }));

    fullBtn.addEventListener('click', act(() => {
      const fsBtn = document.querySelector('.ytp-fullscreen-button');
      if (fsBtn) fsBtn.click();
      else if (document.fullscreenElement) document.exitFullscreen();
      else document.documentElement.requestFullscreen();
    }));

    // slide the dock away while the on-screen keyboard is open
    document.addEventListener('te-kb-shown', () => dock.classList.add('te-yt-dock-hidden'));
    document.addEventListener('te-kb-hidden', () => dock.classList.remove('te-yt-dock-hidden'));

    // auto-hide after a few idle seconds during playback; any touch wakes it
    const IDLE_MS = 3500;
    let idleTimer = null;
    const wakeDock = () => {
      dock.classList.remove('te-yt-dock-auto-hidden');
      clearTimeout(idleTimer);
      idleTimer = setTimeout(() => {
        const v = getVideo();
        if (v && !v.paused) dock.classList.add('te-yt-dock-auto-hidden');
      }, IDLE_MS);
    };
    for (const evt of ['pointerdown', 'pointermove', 'touchstart', 'wheel', 'keydown']) {
      document.addEventListener(evt, wakeDock, { capture: true, passive: true });
    }
    wakeDock();

    // sync with the video 4x/sec
    setInterval(() => {
      const v = getVideo();
      const hasVideo = !!(v && v.duration);
      dock.classList.toggle('te-yt-no-video', !hasVideo);
      if (!v) return;
      if (v.paused) dock.classList.remove('te-yt-dock-auto-hidden');
      playPath.setAttribute('d', v.paused ? ICONS.play : ICONS.pause);
      const muted = v.muted || v.volume === 0;
      volOnIcon.style.display = muted ? 'none' : '';
      volOffIcon.style.display = muted ? '' : 'none';
      if (!scrubbing && isFinite(v.duration) && v.duration > 0) {
        seekbar.value = Math.round((v.currentTime / v.duration) * 1000);
        setFill(seekbar, (v.currentTime / v.duration) * 100);
        timeCur.textContent = fmtTime(v.currentTime);
        timeDur.textContent = fmtTime(v.duration);
      }
      if (document.activeElement !== volume) {
        volume.value = Math.round(v.volume * 100);
        setFill(volume, volume.value);
      }
    }, 250);
  }

  /* ---------- init ---------- */

  function init() {
    if (!document.body) return;
    buildDock();

    // stay in lockstep with the keyboard's enabled state
    document.addEventListener('te-enabled-changed', (e) => {
      enabled = e.detail.enabled;
      applyEnabled();
    });
    try {
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.onChanged) {
        chrome.storage.onChanged.addListener((changes, area) => {
          if (area === 'local' && changes[STORE_KEY]) {
            enabled = changes[STORE_KEY].newValue === 'on';
            applyEnabled();
          }
        });
      }
    } catch {}
    loadSetting((saved) => {
      enabled = saved === 'on' || (saved !== 'off' && isTouchScreen());
      applyEnabled();
    });

    // YouTube is a SPA — re-inject if the dock is ever removed
    const observer = new MutationObserver(() => {
      if (!document.getElementById('te-yt-dock')) { dock = null; buildDock(); }
    });
    observer.observe(document.body, { childList: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
