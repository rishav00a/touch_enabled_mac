# Publishing TE Mac to the Chrome Web Store

Upload file: `dist/te-mac-1.3.0.zip` (manifest at zip root — already verified).

## One-time account setup
1. Go to https://chrome.google.com/webstore/devconsole and sign in with the
   Google account you want to own the listing.
2. Pay the one-time $5 developer registration fee if you haven't already.
3. Under **Account**, fill in the publisher name and a contact email, then
   click **Verify email** (publishing is blocked until it's verified).

## Upload
1. Dashboard → **+ New item** → upload `dist/te-mac-1.3.0.zip`.
2. The draft opens with three tabs to complete: **Store listing**,
   **Privacy**, **Distribution**.

## Store listing tab
- **Title**: TE Mac — Touch Enabled Mac
- **Summary** (132 chars max): iPad-style on-screen keyboard for any input
  field on any site. Made for Macs with touch-screen monitors.
- **Description**: paste from `store-assets/store-description.txt`.
- **Category**: Accessibility. **Language**: English.
- **Store icon**: upload `icons/icon128.png`.
- **Screenshots** (required, at least 1): 1280×800 PNG. Take them with the
  keyboard open on a real site (Cmd+Shift+4 + Space captures a window;
  resize/crop to 1280×800). A YouTube screenshot showing the media footer
  makes a good second one.
- Small promo tile (440×280) is optional — `store-assets/icon512.png` can be
  cropped onto a gradient background if you want one.

## Privacy tab (this is what reviews hinge on)
- **Single purpose**: "Provides an on-screen touch keyboard for typing into
  web pages on touch-screen Macs."
- **Permission justifications**:
  - `storage` — remembers the user's on/off preference for the keyboard.
  - Content script on `<all_urls>` — the on-screen keyboard must attach to
    input fields on whatever site the user is typing into; it cannot know
    the sites in advance.
  - `https://suggestqueries-clients6.youtube.com/*` — fetches live search
    suggestions while typing in the YouTube search box.
  - `https://api.datamuse.com/*` — fetches word predictions/completions
    shown above the keyboard.
- **Remote code**: answer **No** (all code ships in the package; the two
  hosts above are data-only APIs).
- **Data usage**: check "Web browsing activity"? No — the only data leaving
  the browser is the text the user is currently typing, sent to the two
  suggestion APIs. Declare **User activity → Keystrokes/typed text** as
  collected, used only for the extension's core functionality, not sold,
  not transferred for unrelated purposes. Certify the disclosures.
- **Privacy policy URL**:
  https://github.com/rishav00a/touch_enabled_mac/blob/main/PRIVACY.md
- **Homepage URL** (Store listing tab):
  https://github.com/rishav00a/touch_enabled_mac

## Distribution tab
- Visibility: **Public** (or **Unlisted** if you only want link-sharing).
- Distribution: all regions unless you have a reason not to.

## Submit
- Click **Submit for review**. Broad-host-permission extensions get a manual
  review — typically a few days, sometimes longer. You'll get an email on
  approval/rejection; the item then goes live automatically.

## Updating later
1. Bump `"version"` in manifest.json (e.g. 1.3.1).
2. Rebuild the zip:
   `cd te_mac && zip -r dist/te-mac-<version>.zip manifest.json background.js te-keyboard.js te-keyboard.css yt-media.js yt-media.css icons -x "*.DS_Store"`
3. Dashboard → your item → **Package** → **Upload new package** → submit.
