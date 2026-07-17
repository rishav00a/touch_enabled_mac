# Touch Enabled Mac

**macOS doesn't support touch screens — this project fixes that.**

Plug a touch monitor into a Mac and you can tap to click, but that's where it
ends: no on-screen keyboard, no touch-friendly media controls, nothing that
makes touch browsing actually usable. Touch Enabled Mac turns a Mac + touch
monitor into an efficient touch setup with an iPad-style on-screen keyboard
and easy media control.

## What's in this repo

| Folder | What it is |
| --- | --- |
| [`touch_enabled_mac_chrome_extension/`](touch_enabled_mac_chrome_extension/) | Chrome extension (Manifest V3): iPadOS-style on-screen keyboard for any input field on any site, plus touch media controls and live search predictions on YouTube. |
| [`touch_enabled_mac_macos_app/`](touch_enabled_mac_macos_app/) | Native macOS app (Swift): system-wide on-screen touch keyboard that works in every application, not just the browser. Ships as a DMG/PKG. |

Use the Chrome extension if you mostly browse; use the macOS app if you want
the keyboard everywhere on the system. They work independently and together.

## Features

- **iPad-style on-screen keyboard** — slides up when you focus a text field,
  slides away when you're done. Letters, numbers/symbols (`?123`), and
  extended symbols (`#+=`) layouts.
- **Works on every site** — types through browser editing commands so
  React/Vue/Angular inputs and strict sites (Google, YouTube) update
  correctly.
- **Touch media control** — on YouTube, a floating control bar with big touch
  targets: play/pause, previous/next, ±10 s, volume, and seeking.
- **Word & search predictions** — word completions above the keyboard, live
  YouTube search suggestions while typing in the search box.
- **Touch-screen auto-detection** — enables itself when a touch screen is
  detected (including monitors whose drivers don't advertise touch); one tap
  on the toolbar icon overrides it any time.

## Screenshots

<!-- Add screenshots to the screenshots/ folder and reference them here. -->
_Screenshots coming soon — see [`screenshots/`](screenshots/)._

## Install

**Chrome extension** — from the Chrome Web Store (link coming after review),
or manually: `chrome://extensions` → Developer mode → **Load unpacked** →
select `touch_enabled_mac_chrome_extension/`.

**macOS app** — build DMG + PKG installers with:

```sh
cd touch_enabled_mac_macos_app && ./build.sh
```

## Privacy

No accounts, no analytics, no tracking. The only data that ever leaves the
browser is the text you're currently typing, sent to two suggestion APIs
(word predictions and YouTube search suggestions). Full policy:
[PRIVACY.md](PRIVACY.md).

## Support this project

If Touch Enabled Mac makes your touch-screen Mac nicer to use, you can

<a href="https://buymeacoffee.com/rishav00a"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-☕-FFDD00?style=for-the-badge" alt="Buy me a coffee"></a>

## License

MIT © [rishav00a](https://github.com/rishav00a)
