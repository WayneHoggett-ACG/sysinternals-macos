import AppKit
import ZoomItCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!

    let settingsStore = SettingsStore()
    private lazy var settingsViewModel = SettingsViewModel(store: settingsStore)
    private lazy var optionsWindow = OptionsWindowController(viewModel: settingsViewModel)

    private lazy var overlay = OverlayController(settingsStore: settingsStore)
    private lazy var liveZoom = LiveZoomController(settingsStore: settingsStore)
    private lazy var breakTimer = BreakTimerController(settingsStore: settingsStore)
    private lazy var snip = SnipController(settingsStore: settingsStore)
    private lazy var recorder = RecordController(settingsStore: settingsStore)
    private lazy var panorama = PanoramaController(settingsStore: settingsStore)
    private lazy var demoType = DemoTypeController(settingsStore: settingsStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        hotkeyManager = HotkeyManager { [weak self] action in
            self?.handle(action)
        }
        hotkeyManager.registerAll(settings: settingsStore.settings)

        settingsViewModel.onHotkeysChanged = { [weak self] in
            guard let self else { return }
            self.hotkeyManager.registerAll(settings: self.settingsStore.settings)
        }

        recorder.onStateChange = { [weak self] _ in self?.updateStatusIcon() }
        panorama.onStateChange = { [weak self] _ in self?.updateStatusIcon() }

        if CommandLine.arguments.contains("--selftest") {
            runSelfTest()
            return
        }

        // Like ZoomIt on Windows: show the options dialog on first run.
        if UserDefaults.standard.data(forKey: SettingsStore.defaultsKey) == nil {
            settingsStore.update { _ in }  // persist defaults so this only happens once
            optionsWindow.show()
        }
    }

    // MARK: - Self-test hooks

    var selfTestHotkeyCount: Int { hotkeyManager.registeredCount }
    var selfTestHasStatusItem: Bool { statusItem?.button != nil }
    var selfTestOverlay: OverlayController { overlay }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "plus.magnifyingglass",
                accessibilityDescription: "ZoomIt"
            )
        }
        statusItem.menu = buildMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let busy = recorder.isRecording || panorama.isCapturing
        button.image = NSImage(
            systemSymbolName: busy ? "record.circle.fill" : "plus.magnifyingglass",
            accessibilityDescription: "ZoomIt"
        )
        button.contentTintColor = busy ? .systemRed : nil
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        func add(_ title: String, _ action: Selector, hotkey: HotkeyAction? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let hotkey {
                item.title = "\(title)  (\(settingsStore.settings.chord(for: hotkey).displayString))"
            }
            menu.addItem(item)
        }

        add("Zoom", #selector(menuZoom), hotkey: .zoom)
        add("Draw", #selector(menuDraw), hotkey: .draw)
        add("Break Timer", #selector(menuBreak), hotkey: .breakTimer)
        add("LiveZoom", #selector(menuLiveZoom), hotkey: .liveZoom)
        add("LiveDraw", #selector(menuLiveDraw), hotkey: .liveDraw)
        menu.addItem(.separator())
        add(recorder.isRecording ? "Stop Recording" : "Record Screen", #selector(menuRecord), hotkey: .record)
        add("Record Region", #selector(menuRecordRegion), hotkey: .recordCrop)
        add("Record Window", #selector(menuRecordWindow), hotkey: .recordWindow)
        menu.addItem(.separator())
        add("Snip to Clipboard", #selector(menuSnipCopy), hotkey: .snipCopy)
        add("Snip to File", #selector(menuSnipSave), hotkey: .snipSave)
        add("Copy Text (OCR)", #selector(menuSnipOCR), hotkey: .snipOCR)
        menu.addItem(.separator())
        add("DemoType", #selector(menuDemoType), hotkey: .demoType)
        add(panorama.isCapturing ? "Stop Panorama" : "Panorama", #selector(menuPanorama), hotkey: .panorama)
        menu.addItem(.separator())
        if breakTimer.isActive {
            add("Show Break Timer", #selector(menuShowTimer))
        }
        add("Options…", #selector(menuOptions))
        add("About ZoomIt", #selector(menuAbout))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ZoomIt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    // MARK: - Menu actions

    @objc private func menuZoom() { handle(.zoom) }
    @objc private func menuDraw() { handle(.draw) }
    @objc private func menuBreak() { handle(.breakTimer) }
    @objc private func menuLiveZoom() { handle(.liveZoom) }
    @objc private func menuLiveDraw() { handle(.liveDraw) }
    @objc private func menuRecord() { handle(.record) }
    @objc private func menuRecordRegion() { handle(.recordCrop) }
    @objc private func menuRecordWindow() { handle(.recordWindow) }
    @objc private func menuSnipCopy() { handle(.snipCopy) }
    @objc private func menuSnipSave() { handle(.snipSave) }
    @objc private func menuSnipOCR() { handle(.snipOCR) }
    @objc private func menuDemoType() { handle(.demoType) }
    @objc private func menuPanorama() { handle(.panorama) }
    @objc private func menuShowTimer() { breakTimer.showWindow() }
    @objc private func menuOptions() { optionsWindow.show() }

    /// Marketing version stamped into the bundle at build time; "dev" when run
    /// unbundled via `swift run`.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    @objc private func menuAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ZoomIt for macOS \(appVersion)"
        alert.informativeText = "A native macOS port of Mark Russinovich's Sysinternals ZoomIt: screen zoom, annotation, break timer, screen recording, snipping, OCR, DemoType, and panorama capture.\n\nOriginal Windows version: Sysinternals / Microsoft."
        alert.runModal()
    }

    // MARK: - Hotkey dispatch

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .zoom:
            toggleOverlay(.zoom)
        case .draw:
            toggleOverlay(.draw)
        case .liveDraw:
            toggleOverlay(.liveDraw)
        case .liveZoom:
            if liveZoom.isActive {
                liveZoom.dismiss()
            } else {
                overlay.dismissIfActive()
                liveZoom.begin()
            }
        case .breakTimer:
            if breakTimer.isMinimized {
                breakTimer.showWindow()
            } else if breakTimer.isActive {
                breakTimer.stop()
            } else {
                breakTimer.begin()
            }
            updateStatusIcon()
        case .record:
            recorder.toggleFullScreen()
        case .recordCrop:
            recorder.toggleRegion()
        case .recordWindow:
            recorder.toggleWindow()
        case .snipCopy:
            snip.begin(.copy)
        case .snipSave:
            snip.begin(.save)
        case .snipOCR:
            snip.begin(.ocr)
        case .demoType:
            demoType.trigger()
        case .demoTypePrevious:
            demoType.moveBack()
        case .panorama:
            panorama.toggle()
        }
    }

    private func toggleOverlay(_ kind: OverlaySessionKind) {
        if overlay.isActive {
            let wasSame = overlay.sessionKind == kind
            overlay.dismiss()
            if wasSame { return }
        }
        if liveZoom.isActive {
            liveZoom.dismiss()
        }
        overlay.begin(kind)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Rebuild lazily so hotkey labels and recording state stay fresh.
    }
}

extension OverlayController {
    func dismissIfActive() {
        if isActive { dismiss() }
    }
}
