// TE Mac — generic on-screen touch keyboard for any web page.
//
// Works as a Chrome MV3 content script or injected into an Electron preload.
// Attaches to any focused text field (input, textarea, contenteditable),
// slides up iPad-style, and types via execCommand so framework-bound inputs
// (React/Vue/etc.) receive proper input events.
//
// Layout adapts to the field: numeric keypad for number/tel, @ and . keys for
// email, / and .com keys for URL fields. Predictive suggestions: full-query
// YouTube autocomplete on youtube.com's search box, word completions
// (Datamuse) everywhere else except passwords. Fetches go through
// background.js, which isn't CORS-restricted.
//
// All DOM is built with createElement (never innerHTML) so it survives pages
// that enforce Trusted Types (e.g. Google properties).

(() => {
  if (window.__teMacLoaded) return;
  window.__teMacLoaded = true;

  /* ---------- persisted state ---------- */

  const STORE_KEY = 'te-mac-enabled'; // 'on' | 'off' | unset (= auto)

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

  function saveSetting(value) {
    try {
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
        chrome.storage.local.set({ [STORE_KEY]: value });
        return;
      }
    } catch {}
    try { localStorage.setItem(STORE_KEY, value); } catch {}
  }

  /* ---------- touch detection ---------- */

  function isTouchScreen() {
    return (navigator.maxTouchPoints || 0) > 0 ||
      window.matchMedia('(any-pointer: coarse)').matches;
  }

  let enabled = false;

  /* ---------- helpers ---------- */

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

  function isEditable(t) {
    if (!t || (t.closest && t.closest('#te-keyboard'))) return false;
    if (t.isContentEditable) return true;
    if (t.tagName === 'TEXTAREA') return !t.readOnly && !t.disabled;
    if (t.tagName === 'INPUT') {
      const type = (t.type || 'text').toLowerCase();
      return !t.readOnly && !t.disabled &&
        ['text', 'search', 'email', 'url', 'tel', 'password', 'number'].includes(type);
    }
    return false;
  }

  let field = null; // the editable element the keyboard is serving

  function fieldType() {
    if (!field) return 'text';
    return ((field.type || '') + '').toLowerCase();
  }

  function fieldText() {
    if (!field) return '';
    return field.value !== undefined ? field.value : field.textContent || '';
  }

  function typeText(text) {
    if (!field) return;
    field.focus();
    if (!document.execCommand('insertText', false, text)) {
      // fallback for fields where execCommand is refused
      if ('setRangeText' in field) {
        const s = field.selectionStart ?? field.value.length;
        field.setRangeText(text, s, field.selectionEnd ?? s, 'end');
        field.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
      }
    }
  }

  function replaceText(text) {
    if (!field) return;
    field.focus();
    if (field.select) field.select();
    else if (field.isContentEditable) {
      window.getSelection().selectAllChildren(field);
    }
    if (!document.execCommand('insertText', false, text)) {
      if (field.value !== undefined) {
        field.value = text;
        field.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
      }
    }
  }

  function backspace() {
    if (!field) return;
    field.focus();
    if (!document.execCommand('delete', false)) {
      if ('setRangeText' in field) {
        let s = field.selectionStart ?? field.value.length;
        let e = field.selectionEnd ?? s;
        if (s === e && s > 0) s -= 1;
        field.setRangeText('', s, e, 'end');
        field.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'deleteContentBackward' }));
      }
    }
  }

  function pressEnter() {
    if (!field) return;
    if (field.tagName === 'TEXTAREA' || field.isContentEditable) {
      typeText('\n');
      return;
    }
    const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    const notCancelled = field.dispatchEvent(new KeyboardEvent('keydown', opts));
    field.dispatchEvent(new KeyboardEvent('keyup', opts));
    if (notCancelled && field.form) {
      if (field.form.requestSubmit) field.form.requestSubmit();
      else field.form.submit();
    }
    hideKeyboard();
  }

  /* ---------- predictive suggestions ---------- */

  const IS_YOUTUBE = /(^|\.)youtube\.com$/.test(location.hostname);
  const YT_SEARCH_SEL = 'input#search, input[name="search_query"], input.ytSearchboxComponentInput';

  // 'yt' = full-query YouTube autocomplete; 'words' = per-word completion
  function suggestProvider() {
    if (!field) return null;
    if (IS_YOUTUBE && field.matches && field.matches(YT_SEARCH_SEL)) return 'yt';
    const ty = fieldType();
    if (ty === 'password' || layout !== 'text') return null;
    return 'words';
  }

  function currentWord() {
    let text, caret;
    if (field && field.selectionStart !== undefined && field.selectionStart !== null) {
      caret = field.selectionStart;
      text = fieldText().slice(0, caret);
    } else {
      text = fieldText();
    }
    const m = /[A-Za-z']+$/.exec(text);
    return m ? m[0] : '';
  }

  function replaceCurrentWord(word) {
    if (!field) return;
    field.focus();
    const prefix = currentWord();
    if (field.setSelectionRange && field.selectionStart !== null) {
      const caret = field.selectionStart;
      field.setSelectionRange(caret - prefix.length, caret);
      if (!document.execCommand('insertText', false, word + ' ')) {
        field.setRangeText(word + ' ', caret - prefix.length, caret, 'end');
        field.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
      }
    } else {
      // contenteditable: delete the prefix chars, then insert
      for (let i = 0; i < prefix.length; i++) document.execCommand('delete', false);
      document.execCommand('insertText', false, word + ' ');
    }
  }

  let suggestTimer = null;
  let suggestSeq = 0;
  let suggestRow = null;

  function fetchSuggestions(type, query, cb) {
    const seq = ++suggestSeq;
    try {
      chrome.runtime.sendMessage({ type, q: query }, (resp) => {
        if (chrome.runtime.lastError || seq !== suggestSeq) return;
        cb((resp && resp.suggestions) || []);
      });
    } catch { cb([]); }
  }

  function updateSuggestions() {
    if (!suggestRow) return;
    const provider = suggestProvider();
    if (!provider) {
      suggestRow.style.display = 'none';
      return;
    }
    suggestRow.style.display = '';
    const q = provider === 'yt' ? fieldText().trim() : currentWord();
    clearTimeout(suggestTimer);
    if (!q) { renderSuggestions([]); return; }
    suggestTimer = setTimeout(() => {
      fetchSuggestions(provider === 'yt' ? 'te-suggest' : 'te-suggest-words', q, renderSuggestions);
    }, 180);
  }

  function renderSuggestions(items) {
    if (!suggestRow) return;
    suggestRow.querySelectorAll('.te-kb-suggestion').forEach((cell, i) => {
      const text = items[i] || '';
      cell.textContent = text;
      cell.dataset.suggest = text;
      cell.classList.toggle('te-kb-suggestion-empty', !text);
    });
  }

  function applySuggestion(text) {
    if (suggestProvider() === 'yt') replaceText(text);
    else replaceCurrentWord(text);
    updateSuggestions();
  }

  /* ---------- keyboard layouts ---------- */

  const LETTER_BASE = [
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['SHIFT', 'z', 'x', 'c', 'v', 'b', 'n', 'm', 'BKSP']
  ];
  const SYMBOL_BASE = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['-', '/', ':', ';', '(', ')', '$', '&', '@', '"'],
    ['#+=', '.', ',', '?', '!', "'", '%', '*', 'BKSP']
  ];
  const EXTRA_BASE = [
    ['[', ']', '{', '}', '#', '%', '^', '*', '+', '='],
    ['_', '\\', '|', '~', '<', '>', '€', '£', '¥', '·'],
    ['123', '.', ',', '?', '!', "'", '`', '·', 'BKSP']
  ];
  const NUM_ROWS = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['-', '0', '.'],
    ['ABC', 'BKSP', 'ENTER', 'HIDE']
  ];
  const BOTTOM_ROWS = {
    text: ['MODE', 'SPACE', 'ENTER', 'HIDE'],
    email: ['MODE', '@', 'SPACE', '.', 'ENTER', 'HIDE'],
    url: ['MODE', '/', '.', 'DOTCOM', 'ENTER', 'HIDE']
  };

  let shiftOn = false;
  let mode = 'letters'; // letters | symbols | extra
  let layout = 'text';  // text | email | url | numeric
  let kb = null;
  let keysBox = null;

  function computeLayout(t) {
    const im = ((t.getAttribute && t.getAttribute('inputmode')) || '').toLowerCase();
    const ty = ((t.type || '') + '').toLowerCase();
    if (ty === 'number' || ty === 'tel' || ['numeric', 'decimal', 'tel'].includes(im)) return 'numeric';
    if (ty === 'email' || im === 'email') return 'email';
    if (ty === 'url' || im === 'url') return 'url';
    return 'text';
  }

  function buildKey(key) {
    switch (key) {
      case 'SHIFT': return el('button', { id: 'te-key-shift', className: 'te-key te-key-special te-key-wide' }, '⇧');
      case 'BKSP': return el('button', { className: 'te-key te-key-special te-key-wide', dataset: { action: 'bksp' } }, '⌫');
      case 'SPACE': return el('button', { className: 'te-key te-key-space', dataset: { action: 'space' } }, 'space');
      case 'ENTER': return el('button', { className: 'te-key te-key-enter', dataset: { action: 'enter' } }, 'return');
      case 'HIDE': return el('button', { className: 'te-key te-key-special te-key-wide', dataset: { action: 'hide' }, title: 'Hide keyboard' }, '⌨▾');
      case 'MODE': {
        const label = mode === 'letters' ? '?123' : 'ABC';
        return el('button', { className: 'te-key te-key-special te-key-wide', dataset: { action: 'mode' } }, label);
      }
      case '#+=': return el('button', { className: 'te-key te-key-special te-key-wide', dataset: { action: 'extra' } }, '#+=');
      case '123': return el('button', { className: 'te-key te-key-special te-key-wide', dataset: { action: 'symbols' } }, '123');
      case 'ABC': return el('button', { className: 'te-key te-key-special te-key-wide', dataset: { action: 'abc' } }, 'ABC');
      case 'DOTCOM': return el('button', { className: 'te-key te-key-special te-key-wide', dataset: { action: 'dotcom' } }, '.com');
      default: return el('button', { className: 'te-key', dataset: { char: key } }, key);
    }
  }

  function currentRows() {
    if (layout === 'numeric') return NUM_ROWS;
    const base = mode === 'letters' ? LETTER_BASE : mode === 'symbols' ? SYMBOL_BASE : EXTRA_BASE;
    return [...base, BOTTOM_ROWS[layout] || BOTTOM_ROWS.text];
  }

  function renderKeys() {
    while (keysBox.firstChild) keysBox.removeChild(keysBox.firstChild);
    const numeric = layout === 'numeric';
    kb.classList.toggle('te-kb-numeric', numeric);
    for (const row of currentRows()) {
      keysBox.appendChild(el('div', { className: 'te-kb-row' }, ...row.map(buildKey)));
    }
    refreshShift();
  }

  function refreshShift() {
    keysBox.querySelectorAll('.te-key[data-char]').forEach((k) => {
      if (mode === 'letters' && layout !== 'numeric') {
        k.textContent = shiftOn ? k.dataset.char.toUpperCase() : k.dataset.char;
      }
    });
    const sk = keysBox.querySelector('#te-key-shift');
    if (sk) sk.classList.toggle('te-key-active', shiftOn);
  }

  function buildKeyboard() {
    kb = el('div', { id: 'te-keyboard' });

    suggestRow = el('div', { id: 'te-kb-suggest' },
      el('button', { className: 'te-kb-suggestion te-kb-suggestion-empty' }),
      el('button', { className: 'te-kb-suggestion te-kb-suggestion-empty' }),
      el('button', { className: 'te-kb-suggestion te-kb-suggestion-empty' })
    );
    suggestRow.style.display = 'none';
    kb.appendChild(suggestRow);

    keysBox = el('div', { id: 'te-kb-keys' });
    kb.appendChild(keysBox);
    renderKeys();

    // pointerdown + preventDefault keeps focus in the target field
    kb.addEventListener('pointerdown', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      e.preventDefault();
      e.stopPropagation();

      if (b.id === 'te-key-shift') { shiftOn = !shiftOn; refreshShift(); return; }

      if (b.dataset.suggest !== undefined) {
        if (b.dataset.suggest) applySuggestion(b.dataset.suggest);
        return;
      }

      switch (b.dataset.action) {
        case 'bksp': backspace(); updateSuggestions(); return;
        case 'space': typeText(' '); updateSuggestions(); return;
        case 'enter': pressEnter(); return;
        case 'hide': hideKeyboard(); return;
        case 'mode': mode = (mode === 'letters') ? 'symbols' : 'letters'; renderKeys(); return;
        case 'extra': mode = 'extra'; renderKeys(); return;
        case 'symbols': mode = 'symbols'; renderKeys(); return;
        case 'abc': layout = 'text'; mode = 'letters'; renderKeys(); return;
        case 'dotcom': typeText('.com'); return;
      }
      if (b.dataset.char) {
        const upper = mode === 'letters' && layout !== 'numeric' && shiftOn;
        typeText(upper ? b.dataset.char.toUpperCase() : b.dataset.char);
        if (shiftOn) { shiftOn = false; refreshShift(); }
        updateSuggestions();
      }
    });

    document.body.appendChild(kb);
  }

  function showKeyboard() {
    if (!kb || !enabled) return;
    kb.classList.add('te-kb-visible');
    document.dispatchEvent(new CustomEvent('te-kb-shown'));
    updateSuggestions();
    // keep the focused field visible above the keyboard
    if (field && field.getBoundingClientRect) {
      const r = field.getBoundingClientRect();
      const kbTop = window.innerHeight - 320;
      if (r.bottom > kbTop) {
        window.scrollBy({ top: r.bottom - kbTop + 20, behavior: 'smooth' });
      }
    }
  }

  function hideKeyboard() {
    if (kb) kb.classList.remove('te-kb-visible');
    document.dispatchEvent(new CustomEvent('te-kb-hidden'));
  }

  function setEnabled(value, fromUser) {
    enabled = value;
    if (fromUser) saveSetting(value ? 'on' : 'off');
    if (!enabled) hideKeyboard();
    else if (field && isEditable(field)) showKeyboard();
    document.dispatchEvent(new CustomEvent('te-enabled-changed', { detail: { enabled } }));
  }

  /* ---------- focus wiring ---------- */

  function wireFocus() {
    document.addEventListener('focusin', (e) => {
      if (isEditable(e.target)) {
        field = e.target;
        const next = computeLayout(field);
        if (next !== layout) {
          layout = next;
          mode = 'letters';
          if (keysBox) renderKeys();
        }
        if (enabled) showKeyboard();
      }
    });
    document.addEventListener('focusout', (e) => {
      if (e.target === field) {
        setTimeout(() => {
          if (!isEditable(document.activeElement) || document.activeElement !== field) {
            hideKeyboard();
          }
        }, 120);
      }
    });
    // physical typing refreshes predictions too
    document.addEventListener('input', (e) => {
      if (e.target === field && kb && kb.classList.contains('te-kb-visible')) {
        updateSuggestions();
      }
    }, true);
    // a real touch anywhere proves a touch screen — auto-enable unless the
    // user explicitly turned the keyboard off
    window.addEventListener('touchstart', function onFirstTouch() {
      window.removeEventListener('touchstart', onFirstTouch, true);
      loadSetting((saved) => {
        if (saved !== 'off' && !enabled) setEnabled(true, false);
      });
    }, { capture: true, passive: true });

    // react when the toolbar button (or another tab) flips the setting
    try {
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.onChanged) {
        chrome.storage.onChanged.addListener((changes, area) => {
          if (area === 'local' && changes[STORE_KEY]) {
            setEnabled(changes[STORE_KEY].newValue === 'on', false);
          }
        });
      }
    } catch {}
  }

  /* ---------- init ---------- */

  function init() {
    if (!document.body) return;
    buildKeyboard();
    wireFocus();
    loadSetting((saved) => {
      if (saved === 'on') setEnabled(true, false);
      else if (saved === 'off') setEnabled(false, false);
      else setEnabled(isTouchScreen(), false); // auto-detect
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
