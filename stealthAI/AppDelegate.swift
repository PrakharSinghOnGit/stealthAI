import Cocoa
import WebKit
import Carbon.HIToolbox

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {

    var panel: StealthPanel!
    private var tabContainerView: NSView!
    private var tabsScrollView: NSScrollView!
    private var tabsButtonsContainer: NSView!
    private var settingsButton: NSButton!
    private var blurOverlayView: ClickThroughVisualEffectView!
    private var tabButtons: [NSButton] = []
    private var webViews: [WKWebView] = []
    private var activeWebView: WKWebView?
    private var selectedTabIndex: Int = 0
    private let sharedProcessPool = WKProcessPool()

    private var hotKeyManager = GlobalHotKeyManager()
    private var settingsWindowController: NSWindowController?

    private let settingsStore = AppSettingsStore.shared
    private let titleBarHeight: CGFloat = 42
    private let minWindowAlpha: CGFloat = 0.55
    private let maxWindowAlpha: CGFloat = 1.0
    private let windowAlphaStep: CGFloat = 0.05
    private let minBlurOverlayOpacity: CGFloat = 0.0
    private let maxBlurOverlayOpacity: CGFloat = 0.65
    private let blurOverlayStep: CGFloat = 0.04
    private var blurOverlayOpacity: CGFloat = 0.24
    private var grayscaleEnabled = false
    private var transparentBackgroundEnabled = true

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

        blurOverlayOpacity = settingsStore.loadBlurOverlayOpacity()
        grayscaleEnabled = settingsStore.loadGrayscaleEnabled()
        transparentBackgroundEnabled = settingsStore.loadTransparentBackgroundEnabled()

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

        blurOverlayView = ClickThroughVisualEffectView(frame: tabContainerView.bounds)
        blurOverlayView.autoresizingMask = [.width, .height]
        blurOverlayView.blendingMode = .withinWindow
        blurOverlayView.material = .hudWindow
        blurOverlayView.state = .active
        blurOverlayView.alphaValue = blurOverlayOpacity

        contentView.addSubview(tabContainerView)
        tabContainerView.addSubview(blurOverlayView)
    }

    private func loadTabsFromSettings() {
        webViews.forEach {
            $0.stopLoading()
            $0.removeFromSuperview()
        }
        webViews.removeAll()
        activeWebView = nil

        let tabs = settingsStore.loadTabs()
        rebuildTabButtons(with: tabs.map { $0.title })

        for tab in tabs {
            let webView = makeWebView()
            webView.autoresizingMask = [.width, .height]
            if let url = URL(string: tab.url), !tab.url.isEmpty {
                webView.load(URLRequest(url: url))
            }
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
        hotKeyManager.register(id: .refreshTab, hotKey: hotkeys.refreshTab) { [weak self] in
            self?.refreshCurrentTab()
        }
        hotKeyManager.register(id: .decreaseOpacity, hotKey: hotkeys.decreaseOpacity) { [weak self] in
            guard let self else { return }
            self.adjustTransparency(by: -self.windowAlphaStep)
        }
        hotKeyManager.register(id: .increaseOpacity, hotKey: hotkeys.increaseOpacity) { [weak self] in
            guard let self else { return }
            self.adjustTransparency(by: self.windowAlphaStep)
        }
        hotKeyManager.register(id: .decreaseBlur, hotKey: hotkeys.decreaseBlur) { [weak self] in
            guard let self else { return }
            self.adjustBlur(by: -self.blurOverlayStep)
        }
        hotKeyManager.register(id: .increaseBlur, hotKey: hotkeys.increaseBlur) { [weak self] in
            guard let self else { return }
            self.adjustBlur(by: self.blurOverlayStep)
        }
        hotKeyManager.register(id: .toggleGrayscale, hotKey: hotkeys.toggleGrayscale) { [weak self] in
            self?.toggleGrayscale()
        }
        hotKeyManager.register(id: .toggleTransparentBackground, hotKey: hotkeys.toggleTransparentBackground) { [weak self] in
            self?.toggleTransparentBackground()
        }
    }

    private func adjustTransparency(by delta: CGFloat) {
        let next = min(maxWindowAlpha, max(minWindowAlpha, panel.alphaValue + delta))
        panel.alphaValue = next
        settingsStore.saveWindowOpacity(next)
    }

    private func adjustBlur(by delta: CGFloat) {
        let next = min(maxBlurOverlayOpacity, max(minBlurOverlayOpacity, blurOverlayOpacity + delta))
        blurOverlayOpacity = next
        blurOverlayView.alphaValue = next
        settingsStore.saveBlurOverlayOpacity(next)
    }

    private func toggleGrayscale() {
        grayscaleEnabled.toggle()
        settingsStore.saveGrayscaleEnabled(grayscaleEnabled)
        applyStealthModesToAllWebViews()
    }

    private func toggleTransparentBackground() {
        transparentBackgroundEnabled.toggle()
        settingsStore.saveTransparentBackgroundEnabled(transparentBackgroundEnabled)
        applyStealthModesToAllWebViews()
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

    private func refreshCurrentTab() {
        guard selectedTabIndex >= 0, selectedTabIndex < webViews.count else { return }
        webViews[selectedTabIndex].reload()
    }

    private func selectTab(index: Int) {
        guard index >= 0, index < webViews.count else { return }
        selectedTabIndex = index

        let nextWebView = webViews[index]
        if activeWebView !== nextWebView {
            activeWebView?.removeFromSuperview()
            nextWebView.frame = tabContainerView.bounds
            tabContainerView.addSubview(nextWebView, positioned: .below, relativeTo: blurOverlayView)
            activeWebView = nextWebView
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

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = sharedProcessPool
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(makeStealthUserScript())

        let webView = WKWebView(frame: tabContainerView.bounds, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        return webView
    }

    private func makeStealthUserScript() -> WKUserScript {
        let source = """
        (() => {
            if (window.__stealthAIInjected) return;
            window.__stealthAIInjected = true;

            const style = document.createElement('style');
            style.id = 'stealthai-style';
            style.textContent = `
                *, *::before, *::after {
                    animation: none !important;
                    transition-property: none !important;
                    transition-duration: 0s !important;
                    transition-delay: 0s !important;
                    scroll-behavior: auto !important;
                }
            `;

            const state = {
                grayscale: false,
                transparentBg: true
            };

            const applyState = () => {
                const dynamicStyle = document.createElement('style');
                dynamicStyle.textContent = `
                    html {
                        filter: ${state.grayscale ? 'grayscale(1)' : 'none'} !important;
                    }
                    html, body {
                        background: ${state.transparentBg ? 'transparent' : '#111'} !important;
                        background-color: ${state.transparentBg ? 'transparent' : '#111'} !important;
                    }
                `;

                const existing = document.getElementById('stealthai-dynamic-style');
                if (existing) {
                    existing.remove();
                }

                dynamicStyle.id = 'stealthai-dynamic-style';
                document.documentElement.appendChild(dynamicStyle);
            };

            window.__stealthAISetMode = (grayscale, transparentBg) => {
                state.grayscale = !!grayscale;
                state.transparentBg = !!transparentBg;
                applyState();
            };

            if (document.documentElement) {
                document.documentElement.appendChild(style);
                applyState();
            } else {
                document.addEventListener('DOMContentLoaded', () => {
                    document.documentElement.appendChild(style);
                    applyState();
                }, { once: true });
            }
        })();
        """

        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private func applyStealthModes(to webView: WKWebView) {
        let grayscaleValue = grayscaleEnabled ? "true" : "false"
        let transparentValue = transparentBackgroundEnabled ? "true" : "false"
        let script = "window.__stealthAISetMode && window.__stealthAISetMode(\(grayscaleValue), \(transparentValue));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func applyStealthModesToAllWebViews() {
        for webView in webViews {
            applyStealthModes(to: webView)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyStealthModes(to: webView)
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
        window.setContentSize(NSSize(width: 700, height: 620))
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
    var refreshTab: KeyCombo
    var decreaseOpacity: KeyCombo
    var increaseOpacity: KeyCombo
    var decreaseBlur: KeyCombo
    var increaseBlur: KeyCombo
    var toggleGrayscale: KeyCombo
    var toggleTransparentBackground: KeyCombo
}

final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private let defaults = UserDefaults.standard

    private let tabsKey = "tabs"
    private let toggleHotKeyKey = "toggle_hotkey"
    private let switchHotKeyKey = "switch_hotkey"
    private let refreshHotKeyKey = "refresh_hotkey"
    private let decreaseOpacityHotKeyKey = "decrease_opacity_hotkey"
    private let increaseOpacityHotKeyKey = "increase_opacity_hotkey"
    private let decreaseBlurHotKeyKey = "decrease_blur_hotkey"
    private let increaseBlurHotKeyKey = "increase_blur_hotkey"
    private let grayscaleToggleHotKeyKey = "grayscale_toggle_hotkey"
    private let transparentToggleHotKeyKey = "transparent_toggle_hotkey"
    private let windowOpacityKey = "window_opacity"
    private let blurOverlayOpacityKey = "blur_overlay_opacity"
    private let grayscaleEnabledKey = "grayscale_enabled"
    private let transparentBackgroundEnabledKey = "transparent_background_enabled"

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

        if defaults.string(forKey: refreshHotKeyKey) == nil {
            defaults.set("cmd+shift+r", forKey: refreshHotKeyKey)
        }

        if defaults.string(forKey: decreaseOpacityHotKeyKey) == nil {
            defaults.set("cmd+shift+[", forKey: decreaseOpacityHotKeyKey)
        }

        if defaults.string(forKey: increaseOpacityHotKeyKey) == nil {
            defaults.set("cmd+shift+]", forKey: increaseOpacityHotKeyKey)
        }

        if defaults.string(forKey: decreaseBlurHotKeyKey) == nil {
            defaults.set("cmd+shift+;", forKey: decreaseBlurHotKeyKey)
        }

        if defaults.string(forKey: increaseBlurHotKeyKey) == nil {
            defaults.set("cmd+shift+'", forKey: increaseBlurHotKeyKey)
        }

        if defaults.string(forKey: grayscaleToggleHotKeyKey) == nil {
            defaults.set("cmd+shift+g", forKey: grayscaleToggleHotKeyKey)
        }

        if defaults.string(forKey: transparentToggleHotKeyKey) == nil {
            defaults.set("cmd+shift+t", forKey: transparentToggleHotKeyKey)
        }

        if defaults.object(forKey: windowOpacityKey) == nil {
            defaults.set(0.9, forKey: windowOpacityKey)
        }

        if defaults.object(forKey: blurOverlayOpacityKey) == nil {
            defaults.set(0.24, forKey: blurOverlayOpacityKey)
        }

        if defaults.object(forKey: grayscaleEnabledKey) == nil {
            defaults.set(false, forKey: grayscaleEnabledKey)
        }

        if defaults.object(forKey: transparentBackgroundEnabledKey) == nil {
            defaults.set(true, forKey: transparentBackgroundEnabledKey)
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
        let refreshText = defaults.string(forKey: refreshHotKeyKey) ?? "cmd+shift+r"
        let decreaseText = defaults.string(forKey: decreaseOpacityHotKeyKey) ?? "cmd+shift+["
        let increaseText = defaults.string(forKey: increaseOpacityHotKeyKey) ?? "cmd+shift+]"
        let decreaseBlurText = defaults.string(forKey: decreaseBlurHotKeyKey) ?? "cmd+shift+;"
        let increaseBlurText = defaults.string(forKey: increaseBlurHotKeyKey) ?? "cmd+shift+'"
        let grayscaleToggleText = defaults.string(forKey: grayscaleToggleHotKeyKey) ?? "cmd+shift+g"
        let transparentToggleText = defaults.string(forKey: transparentToggleHotKeyKey) ?? "cmd+shift+t"

        let toggleCombo = KeyComboParser.parse(toggleText) ?? KeyComboParser.defaultToggle
        let switchCombo = KeyComboParser.parse(switchText) ?? KeyComboParser.defaultSwitch
        let refreshCombo = KeyComboParser.parse(refreshText) ?? KeyComboParser.defaultRefreshTab
        let decreaseCombo = KeyComboParser.parse(decreaseText) ?? KeyComboParser.defaultDecreaseOpacity
        let increaseCombo = KeyComboParser.parse(increaseText) ?? KeyComboParser.defaultIncreaseOpacity
        let decreaseBlurCombo = KeyComboParser.parse(decreaseBlurText) ?? KeyComboParser.defaultDecreaseBlur
        let increaseBlurCombo = KeyComboParser.parse(increaseBlurText) ?? KeyComboParser.defaultIncreaseBlur
        let grayscaleToggleCombo = KeyComboParser.parse(grayscaleToggleText) ?? KeyComboParser.defaultToggleGrayscale
        let transparentToggleCombo = KeyComboParser.parse(transparentToggleText) ?? KeyComboParser.defaultToggleTransparent

        return HotKeyConfig(
            togglePanel: toggleCombo,
            switchTab: switchCombo,
            refreshTab: refreshCombo,
            decreaseOpacity: decreaseCombo,
            increaseOpacity: increaseCombo,
            decreaseBlur: decreaseBlurCombo,
            increaseBlur: increaseBlurCombo,
            toggleGrayscale: grayscaleToggleCombo,
            toggleTransparentBackground: transparentToggleCombo
        )
    }

    func loadWindowOpacity() -> CGFloat {
        let saved = defaults.double(forKey: windowOpacityKey)
        let initial = saved == 0 ? 0.9 : saved
        return CGFloat(min(1.0, max(0.55, initial)))
    }

    func saveWindowOpacity(_ opacity: CGFloat) {
        defaults.set(Double(opacity), forKey: windowOpacityKey)
    }

    func loadBlurOverlayOpacity() -> CGFloat {
        let saved = defaults.double(forKey: blurOverlayOpacityKey)
        let initial = saved == 0 ? 0.24 : saved
        return CGFloat(min(0.65, max(0.0, initial)))
    }

    func saveBlurOverlayOpacity(_ opacity: CGFloat) {
        defaults.set(Double(opacity), forKey: blurOverlayOpacityKey)
    }

    func loadGrayscaleEnabled() -> Bool {
        defaults.bool(forKey: grayscaleEnabledKey)
    }

    func saveGrayscaleEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: grayscaleEnabledKey)
    }

    func loadTransparentBackgroundEnabled() -> Bool {
        defaults.bool(forKey: transparentBackgroundEnabledKey)
    }

    func saveTransparentBackgroundEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: transparentBackgroundEnabledKey)
    }

    func saveHotKeys(
        toggle: String,
        switchTab: String,
        refreshTab: String,
        decreaseOpacity: String,
        increaseOpacity: String,
        decreaseBlur: String,
        increaseBlur: String,
        toggleGrayscale: String,
        toggleTransparentBackground: String
    ) {
        defaults.set(toggle, forKey: toggleHotKeyKey)
        defaults.set(switchTab, forKey: switchHotKeyKey)
        defaults.set(refreshTab, forKey: refreshHotKeyKey)
        defaults.set(decreaseOpacity, forKey: decreaseOpacityHotKeyKey)
        defaults.set(increaseOpacity, forKey: increaseOpacityHotKeyKey)
        defaults.set(decreaseBlur, forKey: decreaseBlurHotKeyKey)
        defaults.set(increaseBlur, forKey: increaseBlurHotKeyKey)
        defaults.set(toggleGrayscale, forKey: grayscaleToggleHotKeyKey)
        defaults.set(toggleTransparentBackground, forKey: transparentToggleHotKeyKey)
    }

    func loadHotKeyTextValues() -> (
        toggle: String,
        switchTab: String,
        refreshTab: String,
        decreaseOpacity: String,
        increaseOpacity: String,
        decreaseBlur: String,
        increaseBlur: String,
        toggleGrayscale: String,
        toggleTransparentBackground: String
    ) {
        (
            defaults.string(forKey: toggleHotKeyKey) ?? "cmd+shift+space",
            defaults.string(forKey: switchHotKeyKey) ?? "cmd+shift+tab",
            defaults.string(forKey: refreshHotKeyKey) ?? "cmd+shift+r",
            defaults.string(forKey: decreaseOpacityHotKeyKey) ?? "cmd+shift+[",
            defaults.string(forKey: increaseOpacityHotKeyKey) ?? "cmd+shift+]",
            defaults.string(forKey: decreaseBlurHotKeyKey) ?? "cmd+shift+;",
            defaults.string(forKey: increaseBlurHotKeyKey) ?? "cmd+shift+'",
            defaults.string(forKey: grayscaleToggleHotKeyKey) ?? "cmd+shift+g",
            defaults.string(forKey: transparentToggleHotKeyKey) ?? "cmd+shift+t"
        )
    }
}

enum HotKeyActionID: UInt32 {
    case togglePanel = 1
    case switchTab = 2
    case decreaseOpacity = 3
    case increaseOpacity = 4
    case decreaseBlur = 5
    case increaseBlur = 6
    case toggleGrayscale = 7
    case toggleTransparentBackground = 8
    case refreshTab = 9
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
    static let defaultRefreshTab = KeyCombo(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+r")
    static let defaultDecreaseOpacity = KeyCombo(keyCode: UInt32(kVK_ANSI_LeftBracket), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+[")
    static let defaultIncreaseOpacity = KeyCombo(keyCode: UInt32(kVK_ANSI_RightBracket), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+]")
    static let defaultDecreaseBlur = KeyCombo(keyCode: UInt32(kVK_ANSI_Semicolon), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+;")
    static let defaultIncreaseBlur = KeyCombo(keyCode: UInt32(kVK_ANSI_Quote), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+'")
    static let defaultToggleGrayscale = KeyCombo(keyCode: UInt32(kVK_ANSI_G), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+g")
    static let defaultToggleTransparent = KeyCombo(keyCode: UInt32(kVK_ANSI_T), carbonModifiers: UInt32(cmdKey | shiftKey), displayValue: "cmd+shift+t")

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
        "]": UInt32(kVK_ANSI_RightBracket),
        ";": UInt32(kVK_ANSI_Semicolon),
        ":": UInt32(kVK_ANSI_Semicolon),
        "'": UInt32(kVK_ANSI_Quote)
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
    private let refreshTabHotkeyField = NSTextField(string: "")
    private let decreaseOpacityHotkeyField = NSTextField(string: "")
    private let increaseOpacityHotkeyField = NSTextField(string: "")
    private let decreaseBlurHotkeyField = NSTextField(string: "")
    private let increaseBlurHotkeyField = NSTextField(string: "")
    private let grayscaleToggleHotkeyField = NSTextField(string: "")
    private let transparentToggleHotkeyField = NSTextField(string: "")
    private let errorLabel = NSTextField(labelWithString: "")

    private let maxTabs = 10

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 620))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildForm()
        loadValues()
    }

    private func buildForm() {
        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.frame = NSRect(x: 20, y: 544, width: 200, height: 28)
        view.addSubview(title)

        let tabsHeader = NSTextField(labelWithString: "Tabs (up to 10)")
        tabsHeader.font = .systemFont(ofSize: 13, weight: .medium)
        tabsHeader.frame = NSRect(x: 20, y: 516, width: 200, height: 20)
        view.addSubview(tabsHeader)

        tabsScrollView.frame = NSRect(x: 20, y: 336, width: 660, height: 180)
        tabsScrollView.borderType = .bezelBorder
        tabsScrollView.hasVerticalScroller = true
        tabsScrollView.hasHorizontalScroller = false
        tabsScrollView.autohidesScrollers = true
        tabsScrollView.documentView = tabsRowsContainer
        view.addSubview(tabsScrollView)

        addTabButton.target = self
        addTabButton.action = #selector(addTabRow)
        addTabButton.bezelStyle = .rounded
        addTabButton.frame = NSRect(x: 20, y: 304, width: 84, height: 26)
        view.addSubview(addTabButton)

        let keyHeader = NSTextField(labelWithString: "Hotkeys (format: cmd+shift+space)")
        keyHeader.font = .systemFont(ofSize: 13, weight: .medium)
        keyHeader.frame = NSRect(x: 20, y: 270, width: 360, height: 18)
        view.addSubview(keyHeader)

        let toggleLabel = NSTextField(labelWithString: "Toggle hide/show")
        toggleLabel.frame = NSRect(x: 20, y: 242, width: 190, height: 20)
        view.addSubview(toggleLabel)

        configureEditableField(toggleHotkeyField)
        toggleHotkeyField.frame = NSRect(x: 220, y: 238, width: 280, height: 24)
        view.addSubview(toggleHotkeyField)

        let switchLabel = NSTextField(labelWithString: "Switch tabs")
        switchLabel.frame = NSRect(x: 20, y: 214, width: 190, height: 20)
        view.addSubview(switchLabel)

        configureEditableField(switchTabHotkeyField)
        switchTabHotkeyField.frame = NSRect(x: 220, y: 210, width: 280, height: 24)
        view.addSubview(switchTabHotkeyField)

        let refreshLabel = NSTextField(labelWithString: "Refresh current tab")
        refreshLabel.frame = NSRect(x: 520, y: 214, width: 160, height: 20)
        view.addSubview(refreshLabel)

        configureEditableField(refreshTabHotkeyField)
        refreshTabHotkeyField.frame = NSRect(x: 520, y: 186, width: 160, height: 24)
        view.addSubview(refreshTabHotkeyField)

        let decreaseOpacityLabel = NSTextField(labelWithString: "Decrease opacity")
        decreaseOpacityLabel.frame = NSRect(x: 20, y: 186, width: 190, height: 20)
        view.addSubview(decreaseOpacityLabel)

        configureEditableField(decreaseOpacityHotkeyField)
        decreaseOpacityHotkeyField.frame = NSRect(x: 220, y: 182, width: 280, height: 24)
        view.addSubview(decreaseOpacityHotkeyField)

        let increaseOpacityLabel = NSTextField(labelWithString: "Increase opacity")
        increaseOpacityLabel.frame = NSRect(x: 20, y: 158, width: 190, height: 20)
        view.addSubview(increaseOpacityLabel)

        configureEditableField(increaseOpacityHotkeyField)
        increaseOpacityHotkeyField.frame = NSRect(x: 220, y: 154, width: 280, height: 24)
        view.addSubview(increaseOpacityHotkeyField)

        let decreaseBlurLabel = NSTextField(labelWithString: "Decrease blur")
        decreaseBlurLabel.frame = NSRect(x: 20, y: 130, width: 190, height: 20)
        view.addSubview(decreaseBlurLabel)

        configureEditableField(decreaseBlurHotkeyField)
        decreaseBlurHotkeyField.frame = NSRect(x: 220, y: 126, width: 280, height: 24)
        view.addSubview(decreaseBlurHotkeyField)

        let increaseBlurLabel = NSTextField(labelWithString: "Increase blur")
        increaseBlurLabel.frame = NSRect(x: 20, y: 102, width: 190, height: 20)
        view.addSubview(increaseBlurLabel)

        configureEditableField(increaseBlurHotkeyField)
        increaseBlurHotkeyField.frame = NSRect(x: 220, y: 98, width: 280, height: 24)
        view.addSubview(increaseBlurHotkeyField)

        let grayscaleToggleLabel = NSTextField(labelWithString: "Toggle grayscale")
        grayscaleToggleLabel.frame = NSRect(x: 20, y: 74, width: 190, height: 20)
        view.addSubview(grayscaleToggleLabel)

        configureEditableField(grayscaleToggleHotkeyField)
        grayscaleToggleHotkeyField.frame = NSRect(x: 220, y: 70, width: 280, height: 24)
        view.addSubview(grayscaleToggleHotkeyField)

        let transparentToggleLabel = NSTextField(labelWithString: "Toggle transparent background")
        transparentToggleLabel.frame = NSRect(x: 20, y: 46, width: 190, height: 20)
        view.addSubview(transparentToggleLabel)

        configureEditableField(transparentToggleHotkeyField)
        transparentToggleHotkeyField.frame = NSRect(x: 220, y: 42, width: 280, height: 24)
        view.addSubview(transparentToggleHotkeyField)

        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 20, y: 12, width: 560, height: 20)
        view.addSubview(errorLabel)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 610, y: 8, width: 70, height: 28)
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
        refreshTabHotkeyField.stringValue = hotkeys.refreshTab
        decreaseOpacityHotkeyField.stringValue = hotkeys.decreaseOpacity
        increaseOpacityHotkeyField.stringValue = hotkeys.increaseOpacity
        decreaseBlurHotkeyField.stringValue = hotkeys.decreaseBlur
        increaseBlurHotkeyField.stringValue = hotkeys.increaseBlur
        grayscaleToggleHotkeyField.stringValue = hotkeys.toggleGrayscale
        transparentToggleHotkeyField.stringValue = hotkeys.toggleTransparentBackground

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
            row.container.frame = NSRect(x: 0, y: y, width: 660, height: rowHeight)
            row.removeButton.tag = idx
            row.removeButton.isEnabled = tabRows.count > 1
        }

        let totalHeight = max(180, CGFloat(tabRows.count) * (rowHeight + spacing))
        tabsRowsContainer.frame = NSRect(x: 0, y: 0, width: 660, height: totalHeight)
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
        let refreshText = refreshTabHotkeyField.stringValue
        let decreaseOpacityText = decreaseOpacityHotkeyField.stringValue
        let increaseOpacityText = increaseOpacityHotkeyField.stringValue
        let decreaseBlurText = decreaseBlurHotkeyField.stringValue
        let increaseBlurText = increaseBlurHotkeyField.stringValue
        let grayscaleToggleText = grayscaleToggleHotkeyField.stringValue
        let transparentToggleText = transparentToggleHotkeyField.stringValue

        guard KeyComboParser.parse(toggleText) != nil else {
            errorLabel.stringValue = "Invalid toggle hotkey format."
            return
        }

        guard KeyComboParser.parse(switchText) != nil else {
            errorLabel.stringValue = "Invalid switch hotkey format."
            return
        }

        guard KeyComboParser.parse(refreshText) != nil else {
            errorLabel.stringValue = "Invalid refresh hotkey format."
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

        guard KeyComboParser.parse(decreaseBlurText) != nil else {
            errorLabel.stringValue = "Invalid decrease blur hotkey format."
            return
        }

        guard KeyComboParser.parse(increaseBlurText) != nil else {
            errorLabel.stringValue = "Invalid increase blur hotkey format."
            return
        }

        guard KeyComboParser.parse(grayscaleToggleText) != nil else {
            errorLabel.stringValue = "Invalid grayscale toggle hotkey format."
            return
        }

        guard KeyComboParser.parse(transparentToggleText) != nil else {
            errorLabel.stringValue = "Invalid transparent toggle hotkey format."
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
            refreshTab: refreshText,
            decreaseOpacity: decreaseOpacityText,
            increaseOpacity: increaseOpacityText,
            decreaseBlur: decreaseBlurText,
            increaseBlur: increaseBlurText,
            toggleGrayscale: grayscaleToggleText,
            toggleTransparentBackground: transparentToggleText
        )
        delegate?.settingsViewControllerDidSave(self)
        view.window?.close()
    }
}
