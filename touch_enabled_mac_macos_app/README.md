# Touch Enabled Mac — system-wide on-screen keyboard for macOS

A native Swift/AppKit menu-bar app that shows a floating, iPad-style on-screen
keyboard which types into **any app and any input field on your Mac** —
browsers, TextEdit, Terminal, Slack, anything.

## How it works

- The keyboard is a **non-activating floating panel**: tapping its keys never
  steals focus, so whatever field you were typing in stays focused and
  receives the keystrokes.
- Keys are posted as real system keyboard events via `CGEvent` — characters
  through `keyboardSetUnicodeString` (works with any character, independent of
  the active keyboard layout) and special keys (return, backspace, tab,
  arrows) through virtual keycodes.
- **Enabled ≠ visible**: **Enable Touch Mode** (menu-bar toggle) arms the
  keyboard without showing it. Touch mode **enables itself automatically
  when a touch-screen monitor is detected** (HID digitizer device), and can
  be toggled manually on any monitor from the menu-bar icon. The menu-bar
  icon fills in while enabled and dims while disabled; the keyboard itself
  only appears when an input is focused or launched explicitly.
- **Two-finger scroll gestures**: macOS only tracks a touch screen's first
  finger. While touch mode is on, the app listens to the digitizer's raw HID
  reports (needs the **Input Monitoring** permission), detects two
  simultaneous contacts on a touch-enabled monitor, and turns the swipe into
  natural-direction pixel scrolling — vertical and horizontal. No separate
  setting; gestures are part of touch mode.
- **Permissions Required submenu**: missing permissions appear in a single
  submenu with shortcuts into System Settings; it disappears once
  everything is granted. Touch mode (manual on/off) persists across
  launches.
- **Per-monitor touch mode**: while touch mode is on, the menu lists every
  detected monitor with its own switch (persisted across launches). The
  keyboard only auto-shows for inputs on monitors you've switched on.
- **Touch-OS behavior**: while enabled, the app watches the system-wide
  focused UI element (Accessibility API) and slides the keyboard in
  automatically whenever a text input is focused in any app — Finder,
  browsers, anything — on a touch-enabled monitor, appearing on **that
  monitor**, and away when focus leaves it, like iPadOS. Keys always type
  into whatever input is focused.
- **Launch OSK** in the menu (or **⌥⌘K** anywhere) brings the keyboard up on
  demand while enabled; ⌥⌘K also enables the keyboard first if it was off.
  A manual show pins it open; **⌨▾** or ⌥⌘K hides it again.
- Lives in the **menu bar** (keyboard icon, no Dock icon). The panel floats
  above normal windows, joins all Spaces, and can be dragged anywhere by its
  background.

## Layout (iPadOS style)

- Letters with one-shot paired **⇧ shifts**, `,` and `.` on the letter plane
- **.?123** page with numbers and punctuation, **#+=** page with symbols
- **space · return · tab (⇥) · arrow keys (← →) · ⌫ delete**
- **⌨▾** hides the panel (bring it back with Launch OSK / ⌥⌘K)
- Adaptive light/dark appearance matching the system

## Permission (required once)

Posting keystrokes and watching the focused input require the macOS
**Accessibility** permission. On first launch the app prompts you; approve it
in **System Settings → Privacy & Security → Accessibility** (enable
"Touch Enabled Mac"). The app picks the grant up live — no relaunch needed — and
the menu shows a shortcut to the Settings pane until it's granted. Without
it, the keyboard can't auto-show on focus and keys click but nothing types.

> Note: every rebuild re-signs the app, which invalidates the previous grant
> — remove and re-add (or toggle) "Touch Enabled Mac" in the Accessibility list
> after rebuilding.

## Build

```sh
./build.sh    # produces build/Touch Enabled Mac.app plus, in dist/:
              #   Touch Enabled Mac-1.0.0.dmg  (drag-to-Applications image)
              #   Touch Enabled Mac-1.0.0.pkg  (standard installer package)
```

Requires only the Xcode Command Line Tools (`swiftc`). The binary is universal
(Apple Silicon + Intel) and ad-hoc signed.

## Install

Either double-click `dist/Touch Enabled Mac-1.0.0.pkg` and follow the
installer (installs to /Applications), or open the `.dmg` and drag
**Touch Enabled Mac** to Applications. The app and package are unsigned by an
identified developer, so on first open Gatekeeper may object:
right-click → **Open** → **Open**, then grant the permissions as above.
