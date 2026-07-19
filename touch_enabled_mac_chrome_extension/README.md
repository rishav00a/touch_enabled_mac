# TE Mac — Touch Enabled Mac

A generic browser plugin that adds an iPadOS-style on-screen touch keyboard to
**any input field on any website**. Built for Macs connected to touch-screen
monitors.

## Features

- **Works everywhere** — attaches to any `input`, `textarea`, or
  `contenteditable` element on any site. Focus a field and the keyboard
  slides up from the bottom, iPad style; blur it and the keyboard slides away.
- **Framework-safe typing** — keys type through browser editing commands, so
  React/Vue/Angular-bound inputs receive real `input` events and update state
  correctly. Works on Trusted-Types-enforcing sites (Google, YouTube).
- **Three layouts** — letters (with shift), numbers/symbols (`?123`), and
  extended symbols (`#+=`). The blue **return** key inserts a newline in
  multi-line fields and submits forms from single-line fields.
- **Touch-screen auto-detection** — enables itself automatically when the
  browser reports a touch-capable screen (`maxTouchPoints` / coarse pointer),
  and also arms itself on the first real touch event it sees (some macOS
  touch-monitor drivers deliver touches without advertising touch capability).
- **Toolbar toggle** — click the TE Mac icon in Chrome's toolbar to
  enable/disable everywhere (a green ON badge shows the state). Your manual
  choice is remembered and overrides auto-detection.
- **YouTube extras** — on youtube.com the plugin also adds the floating media
  control footer (play/pause, prev/next, ±10s, volume, seek bar, auto-hide)
  and live YouTube search predictions above the keyboard.

## Install as a browser extension (Chrome / Edge / Brave / Arc)

**Easiest:** install from the
[Chrome Web Store](https://chromewebstore.google.com/detail/te-mac-%E2%80%94-touch-enabled-ma/iggpbelenecgchleaodllbfplfjiabdo).

Or manually (any Chromium browser):

1. Open `chrome://extensions`
2. Enable **Developer mode** (top right)
3. Click **Load unpacked** and select this folder (or the unzipped
   [release zip](https://github.com/rishav00a/touch_enabled_mac/releases))

## Load into an Electron app

```js
const { app, session } = require('electron');
const path = require('path');

app.whenReady().then(async () => {
  await session.defaultSession.loadExtension(path.join(__dirname, 'te_mac'));
  // ...create windows
});
```

Or inject `te-keyboard.js` from a preload script and `te-keyboard.css` via
`webContents.insertCSS()`.

## State model

| Stored value | Behavior |
| --- | --- |
| _(unset)_ | Auto: on if a touch screen is detected, off otherwise |
| `on` | Always on (user enabled) |
| `off` | Always off (user disabled) — auto-detection won't re-enable |

State is stored in `chrome.storage.local` when running as an extension
(shared across sites), falling back to per-site `localStorage` otherwise.

## Note on macOS touch monitors

Many third-party touch displays connect to macOS through drivers (e.g. UPDD)
that translate touches into mouse clicks, so the browser may not report a
touch screen at all. The first-touch listener catches some of these, but if
auto-detection misses your setup, just click the TE Mac toolbar icon once —
the choice sticks.
