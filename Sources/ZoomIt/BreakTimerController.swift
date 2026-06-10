import AppKit
import ZoomItCore

/// Break timer (Ctrl+3): a fullscreen countdown that keeps running when
/// minimized, restorable by clicking the menu-bar icon.
final class BreakTimerController {
    private var window: OverlayWindow?
    private var view: BreakTimerView?
    private(set) var timerModel: BreakTimerModel?
    private var tick: Timer?
    private var playedExpirySound = false
    var onClose: (() -> Void)?
    /// Self-test support: keep the timer window invisible.
    var hiddenForTesting = false
    let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var isActive: Bool { timerModel != nil }
    var isMinimized: Bool { isActive && window == nil }

    func begin() {
        guard !isActive else {
            showWindow()
            return
        }
        let s = settingsStore.settings
        timerModel = BreakTimerModel(minutes: s.timerMinutes, showElapsedAfterExpiry: s.showTimeElapsed)
        playedExpirySound = false
        showWindow()
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func showWindow() {
        guard let timerModel else { return }
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let screen = ScreenSnapshotter.screenUnderMouse()
        let win = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hasShadow = false
        win.alphaValue = hiddenForTesting ? 0 : max(0.2, settingsStore.settings.timerOpacity)

        let view = BreakTimerView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            timerModel: timerModel,
            settings: settingsStore.settings
        )
        view.onAdjust = { [weak self] delta in
            self?.timerModel?.adjust(byMinutes: delta)
            self?.playedExpirySound = false
            self?.update()
        }
        view.onExit = { [weak self] in self?.stop() }
        view.onMinimize = { [weak self] in self?.minimize() }
        win.contentView = view
        win.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        window = win
        self.view = view
        update()
    }

    /// Hide the window without pausing the countdown.
    func minimize() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }

    func stop() {
        tick?.invalidate()
        tick = nil
        timerModel = nil
        window?.orderOut(nil)
        window = nil
        view = nil
        onClose?()
    }

    private func update() {
        guard let timerModel else { return }
        if timerModel.isExpired() && !playedExpirySound {
            playedExpirySound = true
            if settingsStore.settings.playSoundOnExpiration {
                NSSound(named: "Glass")?.play()
            }
            if !settingsStore.settings.showTimeElapsed {
                stop()
                return
            }
        }
        view?.refresh()
    }
}

final class BreakTimerView: NSView {
    var onAdjust: ((Int) -> Void)?
    var onExit: (() -> Void)?
    var onMinimize: (() -> Void)?

    private let timerModel: BreakTimerModel
    private let settings: ZoomItSettings
    private var backgroundImage: NSImage?

    init(frame: NSRect, timerModel: BreakTimerModel, settings: ZoomItSettings) {
        self.timerModel = timerModel
        self.settings = settings
        super.init(frame: frame)
        wantsLayer = true
        if !settings.timerBackgroundImagePath.isEmpty {
            backgroundImage = NSImage(contentsOfFile: (settings.timerBackgroundImagePath as NSString).expandingTildeInPath)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    func refresh() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let backgroundImage {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(bounds)
            backgroundImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 0.85))
            ctx.fill(bounds)
        }

        let expired = timerModel.isExpired()
        let text = timerModel.displayString()
        let fontSize = min(bounds.width, bounds.height) / 5
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: expired ? NSColor.systemRed : NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let origin = textOrigin(for: size)
        text.draw(at: origin, withAttributes: attrs)

        let hint = "↑/↓ adjust   esc dismiss   ⌘M hide (keeps running)"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        hint.draw(at: CGPoint(x: bounds.midX - hintSize.width / 2, y: 24), withAttributes: hintAttrs)
    }

    private func textOrigin(for size: CGSize) -> CGPoint {
        let margin: CGFloat = 60
        let x: CGFloat
        let y: CGFloat
        switch settings.timerPosition {
        case .topLeft, .centerLeft, .bottomLeft: x = margin
        case .topCenter, .center, .bottomCenter: x = bounds.midX - size.width / 2
        case .topRight, .centerRight, .bottomRight: x = bounds.maxX - size.width - margin
        }
        switch settings.timerPosition {
        case .topLeft, .topCenter, .topRight: y = bounds.maxY - size.height - margin
        case .centerLeft, .center, .centerRight: y = bounds.midY - size.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight: y = margin
        }
        return CGPoint(x: x, y: y)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onExit?()
        case 126: // Up
            onAdjust?(1)
        case 125: // Down
            onAdjust?(-1)
        case 46 where event.modifierFlags.contains(.command): // Cmd+M
            onMinimize?()
        default:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else { return }
        let direction = event.scrollingDeltaY > 0 ? 1 : (event.scrollingDeltaY < 0 ? -1 : 0)
        if direction != 0 {
            onAdjust?(direction)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onExit?()
    }
}
