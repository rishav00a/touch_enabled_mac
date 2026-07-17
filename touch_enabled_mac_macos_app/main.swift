// Touch Enabled Mac — system-wide on-screen touch keyboard for macOS.
//
// A menu-bar app showing a floating, NON-ACTIVATING panel: tapping its keys
// never steals focus, so keystrokes go to whatever app/field is focused.
// Typing is posted via CGEvent (keyboardSetUnicodeString for characters,
// virtual keycodes for return/backspace/tab/arrows), which requires the
// Accessibility permission — the app prompts for it on first run.
//
// The keyboard has an ENABLED state separate from visibility: it enables
// itself automatically when a touch-screen monitor is attached (HID digitizer
// touch-screen device), and can be enabled/disabled manually from the menu
// bar on any monitor. While enabled, the same Accessibility permission powers
// touch-OS behavior: the app polls the system-wide focused UI element and
// slides the keyboard in whenever a text field is focused in ANY app (Finder,
// browsers, anything), and away when focus leaves it. "Launch OSK" in the
// menu (or ⌥⌘K) brings the keyboard up on demand.
//
// Visuals follow the iPadOS on-screen keyboard: adaptive light/dark key
// colors over a blurred background, three planes (letters / .?123 / #+=),
// delete at the end of the top row, return on the home row, paired shifts.

import Cocoa
import Carbon
import ApplicationServices
import IOKit.hid

// MARK: - key event posting

func postText(_ text: String) {
    let utf16 = Array(text.utf16)
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func postKey(_ keyCode: CGKeyCode) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

let KEY_RETURN: CGKeyCode = 36
let KEY_DELETE: CGKeyCode = 51
let KEY_TAB: CGKeyCode = 48
let KEY_LEFT: CGKeyCode = 123
let KEY_RIGHT: CGKeyCode = 124

// MARK: - system-wide focus detection

func focusedTextElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
          let focused = focusedRef else { return nil }
    let element = focused as! AXUIElement

    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    let role = (roleRef as? String) ?? ""
    if ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role) { return element }

    // web content and custom controls: editable if the value is settable and
    // the element exposes selected text
    var settable = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
    var selRef: CFTypeRef?
    let hasSelection = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selRef) == .success
    return (settable.boolValue && hasSelection) ? element : nil
}

// which monitor the focused element sits on. AX positions are in global
// display coordinates with a TOP-left origin on the primary display;
// NSScreen frames use a bottom-left origin, so flip Y before hit-testing.
func screenOfElement(_ element: AXUIElement) -> NSScreen? {
    var posRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
          let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero
    AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)

    var center = origin
    var sizeRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
       let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
        var size = CGSize.zero
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        center.x += size.width / 2
        center.y += size.height / 2
    }

    guard let primary = NSScreen.screens.first else { return nil }
    let cocoaPoint = NSPoint(x: center.x, y: primary.frame.maxY - center.y)
    return NSScreen.screens.first { NSMouseInRect(cocoaPoint, $0.frame, false) }
}

// MARK: - touch screen detection

// A touch-screen monitor shows up as a HID digitizer device with the
// Touch Screen usage (page 0x0D, usage 0x04). Enumerating matching devices
// needs no special permission; presence is re-checked on a timer to catch
// monitors being plugged in or removed.
final class TouchScreenDetector {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    init() {
        let match = [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 0x04] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, match)
    }

    var present: Bool {
        guard let devices = IOHIDManagerCopyDevices(manager) else { return false }
        return CFSetGetCount(devices) > 0
    }
}

// MARK: - two-finger scroll gestures

// macOS only tracks the first contact of a HID touch screen (cursor + click);
// multi-touch gestures don't exist. This engine listens to the digitizer's
// raw HID reports (Input Monitoring permission), detects two simultaneous
// contacts, and converts the primary contact's movement into pixel scroll
// events — natural-direction two-finger scrolling, vertical and horizontal.
// It never seizes the device, so normal single-finger touch keeps working.
final class TwoFingerScrollEngine {
    var isActive: () -> Bool = { false }
    var isMonitorAllowed: (NSScreen) -> Bool = { _ in false }

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private(set) var opened = false

    // primary contact, normalized 0…1 in digitizer space
    private var primaryXCookie: IOHIDElementCookie?
    private var primaryYCookie: IOHIDElementCookie?
    private var xNorm: CGFloat = 0
    private var yNorm: CGFloat = 0
    private var reportedContacts = 0
    private var tipsOn = Set<IOHIDElementCookie>()

    private var gestureScreen: NSScreen?
    private var lastPoint: CGPoint?

    var accessGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func requestAccess() {
        guard !accessGranted else { return }
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) // prompts once
    }

    func openIfPossible() {
        guard !opened, accessGranted else { return }
        let match = [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 0x04] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, match)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<TwoFingerScrollEngine>.fromOpaque(ctx).takeUnretainedValue().handle(value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let cookie = IOHIDElementGetCookie(element)
        let intVal = IOHIDValueGetIntegerValue(value)

        switch (IOHIDElementGetUsagePage(element), IOHIDElementGetUsage(element)) {
        case (0x0D, 0x54): // digitizer Contact Count
            reportedContacts = intVal
        case (0x0D, 0x42): // digitizer Tip Switch (fallback contact counting)
            if intVal != 0 { tipsOn.insert(cookie) } else { tipsOn.remove(cookie) }
        case (0x01, 0x30): // generic desktop X — first X element = primary contact
            if primaryXCookie == nil { primaryXCookie = cookie }
            guard cookie == primaryXCookie else { return }
            let lo = IOHIDElementGetLogicalMin(element), hi = IOHIDElementGetLogicalMax(element)
            if hi > lo { xNorm = CGFloat(intVal - lo) / CGFloat(hi - lo) }
        case (0x01, 0x31): // generic desktop Y
            if primaryYCookie == nil { primaryYCookie = cookie }
            guard cookie == primaryYCookie else { return }
            let lo = IOHIDElementGetLogicalMin(element), hi = IOHIDElementGetLogicalMax(element)
            if hi > lo { yNorm = CGFloat(intVal - lo) / CGFloat(hi - lo) }
        default:
            return
        }
        evaluate()
    }

    private func evaluate() {
        guard isActive() else { endGesture(); return }
        let contacts = max(reportedContacts, tipsOn.count)
        guard contacts >= 2 else { endGesture(); return }

        if gestureScreen == nil {
            // gesture starts under the cursor (the OS warps it to the touch);
            // only on monitors where touch mode is switched on
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
                  isMonitorAllowed(screen) else { return }
            gestureScreen = screen
            lastPoint = point(on: screen)
            // release the click-drag the system started for the first finger
            // so the two-finger swipe scrolls instead of selecting
            if let primary = NSScreen.screens.first {
                let loc = CGPoint(x: mouse.x, y: primary.frame.maxY - mouse.y)
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                        mouseCursorPosition: loc, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        } else if let screen = gestureScreen {
            let p = point(on: screen)
            guard let last = lastPoint else { lastPoint = p; return }
            let dx = p.x - last.x
            let dy = p.y - last.y
            // natural direction: content follows the fingers
            if abs(dx) >= 1 || abs(dy) >= 1 {
                let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                 wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)
                ev?.post(tap: .cghidEventTap)
                lastPoint = p
            }
        }
    }

    private func endGesture() {
        gestureScreen = nil
        lastPoint = nil
    }

    // digitizer coords are top-left origin, like AX — convert to pixels on
    // the gesture's screen (only deltas are used, so origin doesn't matter)
    private func point(on screen: NSScreen) -> CGPoint {
        CGPoint(x: xNorm * screen.frame.width, y: yNorm * screen.frame.height)
    }
}

// MARK: - key button

final class KeyButton: NSButton {
    enum Style { case normal, special }

    let style: Style
    var toggledOn = false { didSet { applyColors() } } // shift held state
    private var pressed = false

    init(title: String, style: Style) {
        self.style = style
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryChange)
        layer?.cornerRadius = 6
        // iPadOS keys sit on a crisp 1px bottom shadow, no blur
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.30
        layer?.shadowRadius = 0
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        translatesAutoresizingMaskIntoConstraints = false
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // iPadOS palette: light — white keys / gray function keys over a light
    // blur; dark — translucent white fills over a dark blur. Pressing a key
    // swaps the two shades, exactly like iOS.
    private var normalShade: NSColor {
        if toggledOn { return .white }
        switch style {
        case .normal:  return isDark ? NSColor(white: 1.0, alpha: 0.30) : .white
        case .special: return isDark ? NSColor(white: 1.0, alpha: 0.13)
                                     : NSColor(red: 0.673, green: 0.698, blue: 0.741, alpha: 1.0)
        }
    }
    private var pressShade: NSColor {
        switch style {
        case .normal:  return isDark ? NSColor(white: 1.0, alpha: 0.13)
                                     : NSColor(red: 0.673, green: 0.698, blue: 0.741, alpha: 1.0)
        case .special: return isDark ? NSColor(white: 1.0, alpha: 0.30) : .white
        }
    }

    func applyColors() {
        layer?.backgroundColor = (pressed ? pressShade : normalShade).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func highlight(_ flag: Bool) {
        pressed = flag
        applyColors()
    }

    func setTitleText(_ text: String, size: CGFloat, color: NSColor = .labelColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: size),
            .paragraphStyle: style
        ])
    }

    // allow clicks while the panel is not (and never becomes) key
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - non-activating panel

final class KeyboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - key layout

// weight is in letter-key units; nil = flexible, absorbs the row's remainder
struct KeyDef {
    let name: String
    let weight: CGFloat?
}
func K(_ name: String, _ weight: CGFloat? = 1) -> KeyDef { KeyDef(name: name, weight: weight) }

// MARK: - app delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    enum Override { case none, hidden, shown }
    enum Plane { case letters, numbers, symbols }

    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var launchItem: NSMenuItem!
    var touchStatusItem: NSMenuItem!
    var permissionsItem: NSMenuItem!
    var axPermItem: NSMenuItem!
    var inputMonitorPermItem: NSMenuItem!
    var touchSwitch: NSSwitch!

    // two-finger scroll gestures ride on touch mode automatically
    let gestureEngine = TwoFingerScrollEngine()
    var panel: KeyboardPanel!
    var lettersView: NSStackView!
    var numbersView: NSStackView!
    var symbolsView: NSStackView!
    var shiftOn = false
    var letterKeys: [KeyButton] = []
    var shiftKeys: [KeyButton] = []
    var override: Override = .none
    var axTrusted = false

    // enabled state — separate from visibility: while enabled the keyboard
    // only appears when a text input is focused (or via Launch OSK).
    // Auto-follows touch-screen presence unless the user overrides it from
    // the menu bar.
    let touchDetector = TouchScreenDetector()
    var touchScreenPresent = false
    // nil = automatic (follow touch screen); persisted across launches
    var manualEnable: Bool? = UserDefaults.standard.object(forKey: "ManualEnable") as? Bool {
        didSet {
            if let v = manualEnable { UserDefaults.standard.set(v, forKey: "ManualEnable") }
            else { UserDefaults.standard.removeObject(forKey: "ManualEnable") }
        }
    }
    var enabled: Bool { manualEnable ?? touchScreenPresent }

    // per-monitor touch mode: the keyboard only auto-shows for inputs on
    // monitors the user has switched on (persisted across launches)
    var enabledDisplays: Set<UInt32> =
        Set(((UserDefaults.standard.array(forKey: "EnabledTouchDisplays") as? [Int]) ?? []).map { UInt32($0) })
    var monitorItems: [NSMenuItem] = []
    var monitorsSeparator: NSMenuItem!
    var placedDisplay: UInt32 = 0 // display the panel was last positioned on

    func displayID(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    func isDisplayEnabled(_ screen: NSScreen) -> Bool { enabledDisplays.contains(displayID(of: screen)) }
    func saveEnabledDisplays() {
        UserDefaults.standard.set(enabledDisplays.map { Int($0) }, forKey: "EnabledTouchDisplays")
    }

    // layout metrics — iPadOS proportions: keys slightly wider than tall
    let panelWidth: CGFloat = 720
    let panelHeight: CGFloat = 252
    let panelPadding: CGFloat = 14
    let keySpacing: CGFloat = 8

    // letter-key unit derived from the top row: 10 letters + a 1.2u delete
    var keyUnit: CGFloat {
        (panelWidth - 2 * panelPadding - 10 * keySpacing) / 11.2
    }

    // iPadOS planes: delete ends the top row, return ends the home row,
    // shifts bookend the bottom letter row
    var letterRows: [[KeyDef]] {
        [
            [K("q"), K("w"), K("e"), K("r"), K("t"), K("y"), K("u"), K("i"), K("o"), K("p"), K("⌫", nil)],
            [K("a"), K("s"), K("d"), K("f"), K("g"), K("h"), K("j"), K("k"), K("l"), K("return", nil)],
            [K("⇧", 1.1), K("z"), K("x"), K("c"), K("v"), K("b"), K("n"), K("m"), K(","), K("."), K("⇧", nil)],
            bottomRow(planeSwitch: ".?123")
        ]
    }
    var numberRows: [[KeyDef]] {
        [
            [K("1"), K("2"), K("3"), K("4"), K("5"), K("6"), K("7"), K("8"), K("9"), K("0"), K("⌫", nil)],
            [K("-"), K("/"), K(":"), K(";"), K("("), K(")"), K("$"), K("&"), K("@"), K("return", nil)],
            [K("#+=", 1.6), K(".", 1.35), K(",", 1.35), K("?", 1.35), K("!", 1.35), K("'", 1.35), K("\"", 1.35), K("#+=", nil)],
            bottomRow(planeSwitch: "ABC")
        ]
    }
    var symbolRows: [[KeyDef]] {
        [
            [K("["), K("]"), K("{"), K("}"), K("#"), K("%"), K("^"), K("*"), K("+"), K("="), K("⌫", nil)],
            [K("_"), K("\\"), K("|"), K("~"), K("<"), K(">"), K("€"), K("£"), K("¥"), K("return", nil)],
            [K("123", 1.6), K(".", 1.35), K(",", 1.35), K("?", 1.35), K("!", 1.35), K("'", 1.35), K("·", 1.35), K("123", nil)],
            bottomRow(planeSwitch: "ABC")
        ]
    }
    func bottomRow(planeSwitch: String) -> [KeyDef] {
        [K(planeSwitch, 1.5), K("⇥", 1.2), K("space", nil), K("←", 1.2), K("→", 1.2), K("⌨▾", 1.5)]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // prompt for the Accessibility permission needed to post keystrokes
        // and to detect focused text fields system-wide
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        axTrusted = AXIsProcessTrustedWithOptions(opts)

        buildStatusItem()
        buildPanel()
        registerHotkey()

        touchScreenPresent = touchDetector.present

        gestureEngine.isActive = { [weak self] in self?.enabled ?? false }
        gestureEngine.isMonitorAllowed = { [weak self] screen in
            self?.isDisplayEnabled(screen) ?? false
        }
        // register with Input Monitoring right away so the app is listed in
        // that Settings pane even before touch mode is first enabled
        gestureEngine.requestAccess()
        gestureEngine.openIfPossible()

        refreshEnabledUI()

        // touch-OS mode: appear only when a text field is focused. Always
        // poll — the Accessibility grant is re-checked live so focus
        // detection starts working the moment the user approves it, without
        // relaunching (the grant resets whenever the app is re-signed).
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.pollFocus()
        }
        // watch for touch-screen monitors being plugged in or removed
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollTouchScreen()
        }
    }

    func pollFocus() {
        guard enabled else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !axTrusted {
            axTrusted = AXIsProcessTrusted()
            guard axTrusted else { return }
            refreshEnabledUI() // clear the permission hint in the menu
        }
        // auto-show only for inputs on monitors with touch mode switched on,
        // and show the keyboard on that same monitor
        let element = focusedTextElement()
        let targetScreen = element.flatMap { screenOfElement($0) }
        if let screen = targetScreen, isDisplayEnabled(screen) {
            if override != .hidden {
                if !panel.isVisible {
                    place(on: screen)
                    panel.orderFrontRegardless()
                } else if placedDisplay != displayID(of: screen) {
                    place(on: screen) // focus moved to another enabled monitor
                }
            }
        } else {
            if override == .hidden { override = .none } // re-arm after focus leaves
            if override != .shown && panel.isVisible { panel.orderOut(nil) }
        }
    }

    // bottom-center of the given monitor
    func place(on screen: NSScreen) {
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.midX - panelWidth / 2, y: vf.minY + 18))
        placedDisplay = displayID(of: screen)
    }

    func pollTouchScreen() {
        // pick up an Input Monitoring grant given after launch
        if enabled && !gestureEngine.opened {
            gestureEngine.openIfPossible()
        }
        let present = touchDetector.present
        guard present != touchScreenPresent else { return }
        touchScreenPresent = present
        refreshEnabledUI() // auto-enables on attach / auto-disables on detach
    }

    // apply the enabled state everywhere: menu checkmarks, menu-bar icon,
    // and panel visibility
    func refreshEnabledUI() {
        touchSwitch.state = enabled ? .on : .off
        launchItem.isEnabled = enabled
        touchStatusItem.title = touchScreenPresent
            ? "Touch screen detected — auto-enabled"
            : "No touch screen detected"
        // register with Input Monitoring as soon as touch mode is armed so
        // the app shows up in that Settings pane
        if enabled {
            gestureEngine.requestAccess()
            gestureEngine.openIfPossible()
        }

        // permissions submenu: checkmark = granted; hidden entirely once
        // everything is in place
        axPermItem.state = axTrusted ? .on : .off
        inputMonitorPermItem.state = gestureEngine.accessGranted ? .on : .off
        permissionsItem.isHidden = axTrusted && gestureEngine.accessGranted

        statusItem.button?.appearsDisabled = !enabled

        rebuildMonitorItems()

        // enabling touch mode never shows the keyboard by itself — it only
        // arms the focus watcher; the keyboard appears when a text input is
        // focused on an enabled monitor (or via Launch OSK / ⌥⌘K)
        if !enabled {
            override = .none
            panel.orderOut(nil)
        }
    }

    @objc func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc func openInputMonitoringSettings() {
        gestureEngine.requestAccess() // make sure the app is listed in the pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: menu bar

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "Touch Enabled Mac")
            ?? NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Touch Enabled Mac") {
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "☝"
        }
        statusMenu = NSMenu()
        statusMenu.autoenablesItems = false

        let (touchItem, touchSw) = makeSwitchItem(symbols: ["hand.tap", "hand.point.up.left"],
                                                  label: "Touch Mode",
                                                  action: #selector(touchSwitchToggled(_:)))
        touchSwitch = touchSw
        statusMenu.addItem(touchItem)

        launchItem = NSMenuItem(title: "Launch OSK  ⌥⌘K", action: #selector(launchOSK), keyEquivalent: "")
        launchItem.target = self
        statusMenu.addItem(launchItem)

        // monitor rows are inserted after this separator while touch mode is on
        monitorsSeparator = NSMenuItem.separator()
        statusMenu.addItem(monitorsSeparator)
        touchStatusItem = NSMenuItem(title: "No touch screen detected", action: nil, keyEquivalent: "")
        touchStatusItem.isEnabled = false
        statusMenu.addItem(touchStatusItem)

        // permissions live in a submenu, shown only while something is
        // missing, to keep the main menu clean
        permissionsItem = NSMenuItem(title: "Permissions Required", action: nil, keyEquivalent: "")
        let permMenu = NSMenu()
        permMenu.autoenablesItems = false
        axPermItem = NSMenuItem(title: "Accessibility (keyboard & auto-show)…",
                                action: #selector(openAccessibilitySettings), keyEquivalent: "")
        axPermItem.target = self
        permMenu.addItem(axPermItem)
        inputMonitorPermItem = NSMenuItem(title: "Input Monitoring (touch gestures)…",
                                          action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        inputMonitorPermItem.target = self
        permMenu.addItem(inputMonitorPermItem)
        permissionsItem.submenu = permMenu
        statusMenu.addItem(permissionsItem)

        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit Touch Enabled Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusMenu.delegate = self // refresh monitor rows on every open
        statusItem.menu = statusMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshEnabledUI() // fresh monitors, switch states, permission status
    }

    // Control-Center-style row: icon + label + a switch on the right, like
    // the Wi-Fi toggle
    func makeSwitchItem(symbols: [String], label text: String, action: Selector) -> (NSMenuItem, NSSwitch) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 40))

        let icon = NSImageView()
        icon.image = symbols.lazy
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: text) }.first
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        let sw = NSSwitch()
        sw.controlSize = .small
        sw.target = self
        sw.action = action
        sw.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(icon)
        view.addSubview(label)
        view.addSubview(sw)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sw.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            sw.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let item = NSMenuItem()
        item.view = view
        return (item, sw)
    }

    @objc func touchSwitchToggled(_ sender: NSSwitch) {
        manualEnable = sender.state == .on
        refreshEnabledUI()
    }


    // MARK: per-monitor rows

    // while touch mode is on, list every detected monitor with its own
    // switch; the keyboard only auto-shows for inputs on switched-on monitors
    func rebuildMonitorItems() {
        for item in monitorItems { statusMenu.removeItem(item) }
        monitorItems.removeAll()
        guard enabled else { return }

        var idx = statusMenu.index(of: monitorsSeparator) + 1
        let header = NSMenuItem(title: "Touch Mode on Monitors", action: nil, keyEquivalent: "")
        header.isEnabled = false
        statusMenu.insertItem(header, at: idx)
        monitorItems.append(header)
        idx += 1
        for screen in NSScreen.screens {
            let item = NSMenuItem()
            item.view = makeMonitorRow(screen)
            statusMenu.insertItem(item, at: idx)
            monitorItems.append(item)
            idx += 1
        }
        let trailing = NSMenuItem.separator()
        statusMenu.insertItem(trailing, at: idx)
        monitorItems.append(trailing)
    }

    func makeMonitorRow(_ screen: NSScreen) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 34))

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Monitor")
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: screen.localizedName)
        label.font = NSFont.systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let sw = NSSwitch()
        sw.controlSize = .small
        sw.state = isDisplayEnabled(screen) ? .on : .off
        sw.tag = Int(displayID(of: screen))
        sw.target = self
        sw.action = #selector(monitorSwitchToggled(_:))
        sw.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(icon)
        view.addSubview(label)
        view.addSubview(sw)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: sw.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sw.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            sw.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    @objc func monitorSwitchToggled(_ sender: NSSwitch) {
        let id = UInt32(sender.tag)
        if sender.state == .on { enabledDisplays.insert(id) } else { enabledDisplays.remove(id) }
        saveEnabledDisplays()
    }

    // explicit launches appear on the monitor the mouse is on
    func showOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen { place(on: screen) }
        override = .shown
        panel.orderFrontRegardless()
    }

    @objc func launchOSK() {
        guard enabled else { return }
        showOnMouseScreen()
    }

    // ⌥⌘K: show/hide the keyboard; enables the plugin first if needed
    @objc func toggleKeyboard() {
        if !enabled {
            manualEnable = true
            refreshEnabledUI()
            showOnMouseScreen()
            return
        }
        if panel.isVisible {
            override = .hidden
            panel.orderOut(nil)
        } else {
            showOnMouseScreen()
        }
    }

    // MARK: global hotkey (⌥⌘K)

    func registerHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { globalDelegate?.toggleKeyboard() }
            return noErr
        }, 1, &eventType, nil, nil)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x54454B42), id: 1) // 'TEKB'
        RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(cmdKey | optionKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: panel construction

    func buildPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screen.midX - panelWidth / 2, y: screen.minY + 18,
                           width: panelWidth, height: panelHeight)

        panel = KeyboardPanel(contentRect: frame,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true

        // adaptive blur like the iPadOS keyboard background: light gray in
        // light mode, dark translucent in dark mode
        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        panel.contentView = blur

        lettersView = buildRows(letterRows, collectLetters: true)
        numbersView = buildRows(numberRows, collectLetters: false)
        symbolsView = buildRows(symbolRows, collectLetters: false)
        numbersView.isHidden = true
        symbolsView.isHidden = true

        for stack in [lettersView!, numbersView!, symbolsView!] {
            blur.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: panelPadding),
                stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -panelPadding),
                stack.topAnchor.constraint(equalTo: blur.topAnchor, constant: panelPadding),
                stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -panelPadding)
            ])
        }
    }

    func buildRows(_ rows: [[KeyDef]], collectLetters: Bool) -> NSStackView {
        let vstack = NSStackView()
        vstack.orientation = .vertical
        vstack.distribution = .fillEqually
        vstack.spacing = keySpacing
        vstack.translatesAutoresizingMaskIntoConstraints = false

        for row in rows {
            let hstack = NSStackView()
            hstack.orientation = .horizontal
            hstack.alignment = .centerY
            hstack.spacing = keySpacing
            hstack.distribution = .fill

            for def in row {
                let key = makeKey(def.name, collectLetters: collectLetters)
                hstack.addArrangedSubview(key)
                key.heightAnchor.constraint(equalTo: hstack.heightAnchor).isActive = true
                if let w = def.weight {
                    key.widthAnchor.constraint(equalToConstant: (w * keyUnit).rounded()).isActive = true
                } else {
                    // flexible key (delete / return / right shift / space)
                    // absorbs the remaining row width
                    key.setContentHuggingPriority(.defaultLow, for: .horizontal)
                }
            }
            vstack.addArrangedSubview(hstack)
            // pin each row to the panel's full width so the flexible key
            // actually absorbs the remainder (stack alignment alone centers)
            hstack.leadingAnchor.constraint(equalTo: vstack.leadingAnchor).isActive = true
            hstack.trailingAnchor.constraint(equalTo: vstack.trailingAnchor).isActive = true
        }
        return vstack
    }

    func makeKey(_ name: String, collectLetters: Bool) -> KeyButton {
        let functionKeys: Set<String> = ["⇧", "⌫", "⇥", "←", "→", ".?123", "#+=", "123", "ABC", "⌨▾", "return"]
        let key = KeyButton(title: name, style: functionKeys.contains(name) ? .special : .normal)

        // iPadOS type scale: big glyphs for characters, small labels for
        // function keys, a blank spacebar
        if name == "space" {
            key.setTitleText("", size: 14)
        } else if name.count == 1 && !["⇧", "⌫", "⇥", "←", "→"].contains(name) {
            key.setTitleText(name, size: 20)
        } else if [".?123", "#+=", "123", "ABC", "return"].contains(name) {
            key.setTitleText(name, size: 14)
        } else {
            key.setTitleText(name, size: 17)
        }

        key.target = self
        key.action = #selector(keyPressed(_:))
        key.identifier = NSUserInterfaceItemIdentifier(name)
        if collectLetters && name.count == 1 && name >= "a" && name <= "z" {
            letterKeys.append(key)
        }
        if collectLetters && name == "⇧" { shiftKeys.append(key) }
        return key
    }

    func show(_ plane: Plane) {
        lettersView.isHidden = plane != .letters
        numbersView.isHidden = plane != .numbers
        symbolsView.isHidden = plane != .symbols
    }

    @objc func keyPressed(_ sender: KeyButton) {
        let name = sender.identifier?.rawValue ?? ""
        switch name {
        case "⇧":
            shiftOn.toggle()
            refreshShift()
        case "⌫": postKey(KEY_DELETE)
        case "return": postKey(KEY_RETURN)
        case "⇥": postKey(KEY_TAB)
        case "←": postKey(KEY_LEFT)
        case "→": postKey(KEY_RIGHT)
        case "space": postText(" ")
        case ".?123", "123": show(.numbers)
        case "#+=": show(.symbols)
        case "ABC": show(.letters)
        case "⌨▾":
            override = .hidden
            panel.orderOut(nil)
        default:
            postText(shiftOn ? name.uppercased() : name)
            if shiftOn { shiftOn = false; refreshShift() }
        }
    }

    func refreshShift() {
        for key in letterKeys {
            let base = key.identifier?.rawValue ?? ""
            key.setTitleText(shiftOn ? base.uppercased() : base, size: 20)
        }
        // active shift is a white key with a black arrow, like iPadOS
        for sk in shiftKeys {
            sk.toggledOn = shiftOn
            sk.setTitleText("⇧", size: 17, color: shiftOn ? .black : .labelColor)
        }
    }
}

var globalDelegate: AppDelegate?

let app = NSApplication.shared
let delegate = AppDelegate()
globalDelegate = delegate
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar app, no Dock icon
app.run()
