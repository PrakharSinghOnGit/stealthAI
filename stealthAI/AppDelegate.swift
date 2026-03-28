import Cocoa
import WebKit
import Carbon.HIToolbox

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    var panel: StealthPanel!
    private var tabContainerView: NSView!
    private var tabsScrollView: NSScrollView!
    private var tabsButtonsContainer: NSView!
    private var settingsButton: NSButton!
    private var tabButtons: [NSButton] = []
    private var webViews: [WKWebView] = []
    private var selectedTabIndex: Int = 0

    private var hotKeyManager = GlobalHotKeyManager()
    private var settingsWindowController: NSWindowController?

    private let settingsStore = AppSettingsStore.shared
    private let titleBarHeight: CGFloat = 42
    private let minWindowAlpha: CGFloat = 0.25
    private let maxWindowAlpha: CGFloat = 1.0
    private let windowAlphaStep: CGFloat = 0.05

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        settingsStore.ensureDefaults()

        panel = StealthPanel(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 650),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Keep stealth behavior while removing visible title/chrome.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .none
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = ""
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = settingsStore.loadWindowOpacity()
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        buildUI()
        loadTabsFromSettings()
        configureHotKeys()

        panel.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        hotKeyManager.unregisterAll()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindowController?.window {
            settingsWindowController = nil
        }
    }

    private func buildUI() {
        guard let contentView = panel.contentView else { return }

        let titleBar = StealthTitleBarView(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - titleBarHeight,
            width: contentView.bounds.width,
            height: titleBarHeight
        ))
        titleBar.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(titleBar)

        settingsButton = NSButton(title: "Settings", target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.frame = NSRect(x: titleBar.bounds.width - 92, y: 8, width: 80, height: 26)
        settingsButton.autoresizingMask = [.minXMargin]
        titleBar.addSubview(settingsButton)

        tabsScrollView = NSScrollView(frame: NSRect(x: 12, y: 8, width: titleBar.bounds.width - 112, height: 26))
        tabsScrollView.autoresizingMask = [.width]
        tabsScrollView.borderType = .noBorder
        tabsScrollView.drawsBackground = false
        tabsScrollView.hasVerticalScroller = false
        tabsScrollView.hasHorizontalScroller = true
        tabsScrollView.autohidesScrollers = true

        tabsButtonsContainer = NSView(frame: NSRect(x: 0, y: 0, width: tabsScrollView.bounds.width, height: 26))
        tabsScrollView.documentView = tabsButtonsContainer
        titleBar.addSubview(tabsScrollView)

        tabContainerView = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - titleBarHeight
        ))
        tabContainerView.autoresizingMask = [.width, .height]
        contentView.addSubview(tabContainerView)
    }

    private func loadTabsFromSettings() {
        webViews.forEach { $0.removeFromSuperview() }
        webViews.removeAll()

        let tabs = settingsStore.loadTabs()
        rebuildTabButtons(with: tabs.map { $0.title })

        for tab in tabs {
            let webView = WKWebView(frame: tabContainerView.bounds)
            webView.autoresizingMask = [.width, .height]
            webView.isHidden = true
            webView.setValue(false, forKey: "drawsBackground")
            if let url = URL(string: tab.url), !tab.url.isEmpty {
                webView.load(URLRequest(url: url))
            }
            tabContainerView.addSubview(webView)
            webViews.append(webView)
        }

        if webViews.isEmpty {
            selectedTabIndex = 0
            return
        }

        selectedTabIndex = min(selectedTabIndex, webViews.count - 1)
        selectTab(index: selectedTabIndex)
    }

    private func rebuildTabButtons(with labels: [String]) {
        tabsButtonsContainer.subviews.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()

        var x: CGFloat = 0
        let spacing: CGFloat = 8
        let height: CGFloat = 24

        for (idx, label) in labels.enumerated() {
            let button = NSButton(title: label, target: self, action: #selector(didTapTabButton(_:)))
            button.setButtonType(.toggle)
            button.bezelStyle = .texturedRounded
            button.tag = idx
            let width = max(96, button.intrinsicContentSize.width + 24)
            button.frame = NSRect(x: x, y: 1, width: width, height: height)
            tabsButtonsContainer.addSubview(button)
            tabButtons.append(button)
            x += width + spacing
        }

        let contentWidth = max(x, tabsScrollView.contentSize.width)
        tabsButtonsContainer.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 26)
    }

    private func configureHotKeys() {
        hotKeyManager.unregisterAll()
        let hotkeys = settingsStore.loadHotKeys()

        hotKeyManager.register(id: .togglePanel, hotKey: hotkeys.togglePanel) { [weak self] in
            self?.togglePanelVisibility()
        }
        hotKeyManager.register(id: .switchTab, hotKey: hotkeys.switchTab) { [weak self] in
            self?.switchToNextTab()
        }
        hotKeyManager.register(id: .decreaseOpacity, hotKey: hotkeys.decreaseOpacity) { [weak self] in
            guard let self else { return }
            self.adjustTransparency(by: -self.windowAlphaStep)
        }
        hotKeyManager.register(id: .increaseOpacity, hotKey: hotkeys.increaseOpacity) { [weak self] in
            guard let self else { return }
            self.adjustTransparency(by: self.windowAlphaStep)
        }
    }

    private func adjustTransparency(by delta: CGFloat) {
        let next = min(maxWindowAlpha, max(minWindowAlpha, panel.alphaValue + delta))
        panel.alphaValue = next
        settingsStore.saveWindowOpacity(next)
    }

    private func togglePanelVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func switchToNextTab() {
        guard !webViews.isEmpty else { return }
        let next = (selectedTabIndex + 1) % webViews.count
        selectTab(index: next)
    }

    private func selectTab(index: Int) {
        guard index >= 0, index < webViews.count else { return }
        selectedTabIndex = index

        for (idx, webView) in webViews.enumerated() {
            webView.isHidden = idx != index
        }
        for (idx, button) in tabButtons.enumerated() {
            button.state = (idx == index) ? .on : .off
        }

        if index < tabButtons.count {
            tabsButtonsContainer.scrollToVisible(tabButtons[index].frame.insetBy(dx: -8, dy: 0))
        }
    }

    @objc private func didTapTabButton(_ sender: NSButton) {
        selectTab(index: sender.tag)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let existing = settingsWindowController {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let vc = SettingsViewController()
        vc.delegate = self
        let window = NSWindow(contentViewController: vc)
        window.title = "Stealth AI Settings"
        window.styleMask = [.titled, .closable]
        window.level = .normal
        window.setContentSize(NSSize(width: 660, height: 470))
        window.center()
        window.delegate = self

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: SettingsViewControllerDelegate {
    func settingsViewControllerDidSave(_ controller: SettingsViewController) {
        loadTabsFromSettings()
        configureHotKeys()
    }
}

struct TabConfig {
    var title: String
    var url: String
}

struct KeyCombo {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var displayValue: String
}

struct HotKeyConfig {
    var togglePanel: KeyCombo
    var switchTab: KeyCombo
    var decreaseOpacity: KeyCombo
    var increaseOpacity: KeyCombo
}

final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private let defaults = UserDefaults.standard

    private let tabsKey = "tabs"
    private let toggleHotKeyKey = "toggle_hotkey"
    private let switchHotKeyKey = "switch_hotkey"
    private let decreaseOpacityHotKeyKey = "decrease_opacity_hotkey"
    private let increaseOpacityHotKeyKey = "increase_opacity_hotkey"
    private let windowOpacityKey = "window_opacity"

    private init() {}

    func ensureDefaults() {
        if defaults.array(forKey: tabsKey) == nil {
            let defaultTabs: [[String: String]] = [
                ["title": "ChatGPT", "url": "https://chatgpt.com"],
                ["title": "Claude", "url": "https://claude.ai"],
                ["title": "Gemini", "url": "https://gemini.google.com"]
            ]
            defaults.set(defaultTabs, forKey: tabsKey)
        }

        if defaults.string(forKey: toggleHotKeyKey) == nil {
            defaults.set("cmd+shift+space", forKey: toggleHotKeyKey)
        }

        if defaults.string(forKey: switchHotKeyKey) == nil {
            defaults.set("cmd+shift+tab", forKey: switchHotKeyKey)
        }

        if defaults.string(forKey: decreaseOpacityHotKeyKey) == nil {
            defaults.set("cmd+shift+[", forKey: decreaseOpacityHotKeyKey)
        }

        if defaults.string(forKey: increaseOpacityHotKeyKey) == nil {
            defaults.set("cmd+shift+]", forKey: increaseOpacityHotKeyKey)
        }

        if defaults.object(forKey: windowOpacityKey) == nil {
            defaults.set(0.9, forKey: windowOpacityKey)
        }
    }

    func loadTabs() -> [TabConfig] {
        guard let array = defaults.array(forKey: tabsKey) as? [[String: String]] else {
            return [TabConfig(title: "ChatGPT", url: "https://chatgpt.com")]
        }

        let loaded = array.prefix(10).enumerated().map { idx, item in
            let fallback = ["ChatGPT", "Claude", "Gemini"]
            let fallbackTitle = idx < fallback.count ? fallback[idx] : "Tab \(idx + 1)"
            let rawTitle = item["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return TabConfig(
                title: rawTitle.isEmpty ? fallbackTitle : rawTitle,
                url: item["url"] ?? ""
            )
        }

        if loaded.isEmpty {
            return [TabConfig(title: "ChatGPT", url: "https://chatgpt.com")]
        }

        return Array(loaded)
    }

    func saveTabs(_ tabs: [TabConfig]) {
        let clamped = Array(tabs.prefix(10))
        let encoded = clamped.map { ["title": $0.title, "url": $0.url] }
        defaults.set(encoded, forKey: tabsKey)
    }

    func loadHotKeys() -> HotKeyConfig {
        let toggleText = defaults.string(forKey: toggleHotKeyKey) ?? "cmd+shift+space"
        let switchText = defaults.string(forKey: switchHotKeyKey) ?? "cmd+shift+tab"
        let decreaseText = defaults.string(forKey: decreaseOpacityHotKeyKey) ?? "cmd+shift+["
        let increaseText = defaults.string(forKey: increaseOpacityHotKeyKey) ?? "cmd+shift+]"

        let toggleCombo = KeyComboParser.parse(toggleText) ?? KeyComboParser.defaultToggle
        let switchCombo = KeyComboParser.parse(switchText) ?? KeyComboParser.defaultSwitch
        let decreaseCombo = KeyComboParser.parse(decreaseText) ?? KeyComboParser.defaultDecreaseOpacity
        let increaseCombo = KeyComboParser.parse(increaseText) ?? KeyComboParser.defaultIncreaseOpacity

        return HotKeyConfig(
            togglePanel: toggleCombo,
            switchTab: switchCombo,
            decreaseOpacity: decreaseCombo,
            increaseOpacity: increaseCombo
        )
    }

    func loadWindowOpacity() -> CGFloat {
        let saved = defaults.double(forKey: windowOpacityKey)
        let initial = saved == 0 ? 0.9 : saved
        return CGFloat(min(1.0, max(0.25, initial)))
    }

    func saveWindowOpacity(_ opacity: CGFloat) {
        defaults.set(Double(opacity), forKey: windowOpacityKey)
    }

    func saveHotKeys(toggle: String, switchTab: String, decreaseOpacity: String, increaseOpacity: String) {
        defaults.set(toggle, forKey: toggleHotKeyKey)
        defaults.set(switchTab, forKey: switchHotKeyKey)
        defaults.set(decreaseOpacity, forKey: decreaseOpacityHotKeyKey)
        defaults.set(increaseOpacity, forKey: increaseOpacityHotKeyKey)
    }

    func loadHotKeyTextValues() -> (toggle: String, switchTab: String, decreaseOpacity: String, increaseOpacity: String) {
        (
            defaults.string(forKey: toggleHotKeyKey) ?? "cmd+shift+space",
            defaults.string(forKey: switchHotKeyKey) ?? "cmd+shift+tab",
            defaults.string(forKey: decreaseOpacityHotKeyKey) ?? "cmd+shift+[",
            defaults.string(forKey: increaseOpacityHotKeyKey) ?? "cmd+shift+]"
        )
    }
}

enum HotKeyActionID: UInt32 {
    case togglePanel = 1
    case switchTab = 2
    case decreaseOpacity = 3
    case increaseOpacity = 4
}

final class GlobalHotKeyManager {
    private var hotKeyRefs: [HotKeyActionID: EventHotKeyRef] = [:]
    private var handlers: [HotKeyActionID: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        installHandlerIfNeeded()
    }

    func register(id: HotKeyActionID, hotKey: KeyCombo, handler: @escaping () -> Void) {
        unregister(id: id)

        let hotKeyID = EventHotKeyID(signature: OSType(0x53544149), id: id.rawValue)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { return }
        hotKeyRefs[id] = ref
        handlers[id] = handler
    }

    func unregister(id: HotKeyActionID) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs[id] = nil
        }
        handlers[id] = nil
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleEvent(eventRef)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            eventHandler = nil
        }
    }

    private func handleEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == OSType(0x53544149),
              let action = HotKeyActionID(rawValue: hotKeyID.id) else {
            return OSStatus(eventNotHandledErr)
        }

        handlers[action]?()
        return noErr
    }
}

enum KeyComboParser {
    static let defaultToggle = KeyCombo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+space")
    static let defaultSwitch = KeyCombo(keyCode: UInt32(kVK_Tab), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+tab")
    static let defaultDecreaseOpacity = KeyCombo(keyCode: UInt32(kVK_ANSI_LeftBracket), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+[")
    static let defaultIncreaseOpacity = KeyCombo(keyCode: UInt32(kVK_ANSI_RightBracket), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+]")

    private static let keyMap: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space),
        "tab": UInt32(kVK_Tab),
        "return": UInt32(kVK_Return),
        "enter": UInt32(kVK_Return),
        "escape": UInt32(kVK_Escape),
        "esc": UInt32(kVK_Escape),
        "[": UInt32(kVK_ANSI_LeftBracket),
        "]": UInt32(kVK_ANSI_RightBracket)
    ]

    static func parse(_ input: String) -> KeyCombo? {
        let cleaned = input.lowercased().replacingOccurrences(of: " ", with: "")
        let tokens = cleaned.split(separator: "+").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for token in tokens {
            switch token {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "alt", "option": modifiers |= UInt32(optionKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            default:
                if keyCode == nil, let mapped = keyMap[token] {
                    keyCode = mapped
                }
            }
        }

        guard modifiers != 0, let keyCode else { return nil }
        return KeyCombo(keyCode: keyCode, carbonModifiers: modifiers, displayValue: cleaned)
    }
}

protocol SettingsViewControllerDelegate: AnyObject {
    func settingsViewControllerDidSave(_ controller: SettingsViewController)
}

final class SettingsViewController: NSViewController {
    weak var delegate: SettingsViewControllerDelegate?

    private struct TabRow {
        let container: NSView
        let nameField: NSTextField
        let urlField: NSTextField
        let removeButton: NSButton
    }

    private var tabRows: [TabRow] = []

    private let tabsScrollView = NSScrollView(frame: .zero)
    private let tabsRowsContainer = NSView(frame: .zero)
    private let addTabButton = NSButton(title: "Add Tab", target: nil, action: nil)

    private let toggleHotkeyField = NSTextField(string: "")
    private let switchTabHotkeyField = NSTextField(string: "")
    private let decreaseOpacityHotkeyField = NSTextField(string: "")
    private let increaseOpacityHotkeyField = NSTextField(string: "")
    private let errorLabel = NSTextField(labelWithString: "")

    private let maxTabs = 10

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 470))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildForm()
        loadValues()
    }

    private func buildForm() {
        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.frame = NSRect(x: 20, y: 392, width: 200, height: 28)
        view.addSubview(title)

        let tabsHeader = NSTextField(labelWithString: "Tabs (up to 10)")
        tabsHeader.font = .systemFont(ofSize: 13, weight: .medium)
        tabsHeader.frame = NSRect(x: 20, y: 365, width: 200, height: 20)
        view.addSubview(tabsHeader)

        tabsScrollView.frame = NSRect(x: 20, y: 216, width: 620, height: 180)
        tabsScrollView.borderType = .bezelBorder
        tabsScrollView.hasVerticalScroller = true
        tabsScrollView.hasHorizontalScroller = false
        tabsScrollView.autohidesScrollers = true
        tabsScrollView.documentView = tabsRowsContainer
        view.addSubview(tabsScrollView)

        addTabButton.target = self
        addTabButton.action = #selector(addTabRow)
        addTabButton.bezelStyle = .rounded
        addTabButton.frame = NSRect(x: 20, y: 184, width: 84, height: 26)
        view.addSubview(addTabButton)

        let keyHeader = NSTextField(labelWithString: "Hotkeys (format: cmd+shift+space)")
        keyHeader.font = .systemFont(ofSize: 13, weight: .medium)
        keyHeader.frame = NSRect(x: 20, y: 150, width: 300, height: 18)
        view.addSubview(keyHeader)

        let toggleLabel = NSTextField(labelWithString: "Toggle hide/show")
        toggleLabel.frame = NSRect(x: 20, y: 122, width: 130, height: 20)
        view.addSubview(toggleLabel)

        configureEditableField(toggleHotkeyField)
        toggleHotkeyField.frame = NSRect(x: 190, y: 118, width: 230, height: 24)
        view.addSubview(toggleHotkeyField)

        let switchLabel = NSTextField(labelWithString: "Switch tabs")
        switchLabel.frame = NSRect(x: 20, y: 92, width: 130, height: 20)
        view.addSubview(switchLabel)

        configureEditableField(switchTabHotkeyField)
        switchTabHotkeyField.frame = NSRect(x: 190, y: 88, width: 230, height: 24)
        view.addSubview(switchTabHotkeyField)

        let decreaseOpacityLabel = NSTextField(labelWithString: "Decrease opacity")
        decreaseOpacityLabel.frame = NSRect(x: 20, y: 62, width: 130, height: 20)
        view.addSubview(decreaseOpacityLabel)

        configureEditableField(decreaseOpacityHotkeyField)
        decreaseOpacityHotkeyField.frame = NSRect(x: 190, y: 58, width: 230, height: 24)
        view.addSubview(decreaseOpacityHotkeyField)

        let increaseOpacityLabel = NSTextField(labelWithString: "Increase opacity")
        increaseOpacityLabel.frame = NSRect(x: 20, y: 32, width: 130, height: 20)
        view.addSubview(increaseOpacityLabel)

        configureEditableField(increaseOpacityHotkeyField)
        increaseOpacityHotkeyField.frame = NSRect(x: 190, y: 28, width: 230, height: 24)
        view.addSubview(increaseOpacityHotkeyField)

        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 20, y: 6, width: 460, height: 20)
        view.addSubview(errorLabel)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 570, y: 8, width: 70, height: 28)
        view.addSubview(saveButton)
    }

    private func configureEditableField(_ field: NSTextField) {
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.isBordered = true
        field.focusRingType = .default
    }

    private func loadValues() {
        tabRows.removeAll()
        tabsRowsContainer.subviews.forEach { $0.removeFromSuperview() }

        let tabs = AppSettingsStore.shared.loadTabs()
        for tab in tabs {
            appendTabRow(tab)
        }

        if tabRows.isEmpty {
            appendTabRow(TabConfig(title: "ChatGPT", url: "https://chatgpt.com"))
        }

        let hotkeys = AppSettingsStore.shared.loadHotKeyTextValues()
        toggleHotkeyField.stringValue = hotkeys.toggle
        switchTabHotkeyField.stringValue = hotkeys.switchTab
        decreaseOpacityHotkeyField.stringValue = hotkeys.decreaseOpacity
        increaseOpacityHotkeyField.stringValue = hotkeys.increaseOpacity

        updateRowsLayout()
        updateAddButtonState()
    }

    private func appendTabRow(_ config: TabConfig) {
        guard tabRows.count < maxTabs else { return }

        let rowView = NSView(frame: .zero)

        let nameField = NSTextField(string: config.title)
        configureEditableField(nameField)
        nameField.placeholderString = "Tab name"
        nameField.frame = NSRect(x: 0, y: 2, width: 150, height: 24)
        rowView.addSubview(nameField)

        let urlField = NSTextField(string: config.url)
        configureEditableField(urlField)
        urlField.placeholderString = "https://..."
        urlField.frame = NSRect(x: 160, y: 2, width: 390, height: 24)
        rowView.addSubview(urlField)

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeTabRow(_:)))
        removeButton.bezelStyle = .rounded
        removeButton.frame = NSRect(x: 558, y: 0, width: 62, height: 28)
        rowView.addSubview(removeButton)

        tabsRowsContainer.addSubview(rowView)
        tabRows.append(TabRow(container: rowView, nameField: nameField, urlField: urlField, removeButton: removeButton))
    }

    private func updateRowsLayout() {
        let rowHeight: CGFloat = 32
        let spacing: CGFloat = 8

        for (idx, row) in tabRows.enumerated() {
            let y = CGFloat(tabRows.count - 1 - idx) * (rowHeight + spacing)
            row.container.frame = NSRect(x: 0, y: y, width: 620, height: rowHeight)
            row.removeButton.tag = idx
            row.removeButton.isEnabled = tabRows.count > 1
        }

        let totalHeight = max(180, CGFloat(tabRows.count) * (rowHeight + spacing))
        tabsRowsContainer.frame = NSRect(x: 0, y: 0, width: 620, height: totalHeight)
    }

    private func updateAddButtonState() {
        addTabButton.isEnabled = tabRows.count < maxTabs
    }

    @objc private func addTabRow() {
        guard tabRows.count < maxTabs else { return }
        let nextIndex = tabRows.count + 1
        appendTabRow(TabConfig(title: "Tab \(nextIndex)", url: ""))
        updateRowsLayout()
        updateAddButtonState()
    }

    @objc private func removeTabRow(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < tabRows.count, tabRows.count > 1 else { return }

        let row = tabRows.remove(at: idx)
        row.container.removeFromSuperview()

        updateRowsLayout()
        updateAddButtonState()
    }

    @objc private func save() {
        errorLabel.stringValue = ""

        let toggleText = toggleHotkeyField.stringValue
        let switchText = switchTabHotkeyField.stringValue
        let decreaseOpacityText = decreaseOpacityHotkeyField.stringValue
        let increaseOpacityText = increaseOpacityHotkeyField.stringValue

        guard KeyComboParser.parse(toggleText) != nil else {
            errorLabel.stringValue = "Invalid toggle hotkey format."
            return
        }

        guard KeyComboParser.parse(switchText) != nil else {
            errorLabel.stringValue = "Invalid switch hotkey format."
            return
        }

        guard KeyComboParser.parse(decreaseOpacityText) != nil else {
            errorLabel.stringValue = "Invalid decrease opacity hotkey format."
            return
        }

        guard KeyComboParser.parse(increaseOpacityText) != nil else {
            errorLabel.stringValue = "Invalid increase opacity hotkey format."
            return
        }

        let tabs: [TabConfig] = tabRows.enumerated().map { idx, row in
            let name = row.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = row.urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return TabConfig(title: name.isEmpty ? "Tab \(idx + 1)" : name, url: url)
        }

        AppSettingsStore.shared.saveTabs(tabs)
        AppSettingsStore.shared.saveHotKeys(
            toggle: toggleText,
            switchTab: switchText,
            decreaseOpacity: decreaseOpacityText,
            increaseOpacity: increaseOpacityText
        )
        delegate?.settingsViewControllerDidSave(self)
        view.window?.close()
    }
}
