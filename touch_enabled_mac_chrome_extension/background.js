// Toolbar icon: click to toggle the on-screen keyboard globally.
// Content scripts in every tab react via chrome.storage.onChanged.

const STORE_KEY = 'te-mac-enabled';

async function refreshBadge() {
  const r = await chrome.storage.local.get(STORE_KEY);
  const on = r[STORE_KEY] === 'on';
  await chrome.action.setBadgeText({ text: on ? 'ON' : '' });
  await chrome.action.setBadgeBackgroundColor({ color: '#34c759' });
}

chrome.action.onClicked.addListener(async () => {
  const r = await chrome.storage.local.get(STORE_KEY);
  const next = r[STORE_KEY] === 'on' ? 'off' : 'on';
  await chrome.storage.local.set({ [STORE_KEY]: next });
  await refreshBadge();
});

chrome.runtime.onInstalled.addListener(refreshBadge);
chrome.runtime.onStartup.addListener(refreshBadge);
chrome.storage.onChanged.addListener(refreshBadge);

// Predictive suggestions for YouTube search. Content scripts are subject to
// page CORS, so the fetch happens here (host_permissions grants access).
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg && msg.type === 'te-suggest') {
    const url = 'https://suggestqueries-clients6.youtube.com/complete/search?client=firefox&ds=yt&q='
      + encodeURIComponent(msg.q || '');
    fetch(url)
      .then((r) => r.json())
      .then((j) => sendResponse({ suggestions: Array.isArray(j[1]) ? j[1].slice(0, 3) : [] }))
      .catch(() => sendResponse({ suggestions: [] }));
    return true; // keep the channel open for the async response
  }
  if (msg && msg.type === 'te-suggest-words') {
    const url = 'https://api.datamuse.com/sug?max=3&s=' + encodeURIComponent(msg.q || '');
    fetch(url)
      .then((r) => r.json())
      .then((j) => sendResponse({ suggestions: (Array.isArray(j) ? j : []).map((w) => w.word).slice(0, 3) }))
      .catch(() => sendResponse({ suggestions: [] }));
    return true;
  }
});
