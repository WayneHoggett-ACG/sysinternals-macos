import AppKit
import CoreImage
import ZoomItCore

/// Which top-level overlay experience is running.
enum OverlaySessionKind {
    case zoom       // Ctrl+1: static zoom; click to draw
    case draw       // Ctrl+2: draw on a static screenshot at 1x
    case liveDraw   // Ctrl+Shift+4: draw on a transparent overlay over the live screen
}

/// Owns the fullscreen overlay window for zoom/draw/type modes.
final class OverlayController {
    private(set) var window: OverlayWindow?
    private(set) var view: OverlayView?
    var onClose: (() -> Void)?
    let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var isActive: Bool { window != nil }
    var sessionKind: OverlaySessionKind? { view?.sessionKind }

    func begin(_ kind: OverlaySessionKind) {
        guard !isActive else { return }
        let screen = ScreenSnapshotter.screenUnderMouse()
        if kind == .liveDraw {
            Task { @MainActor in
                self.presentOverlay(kind: kind, snapshot: nil, screen: screen)
            }
            return
        }
        guard Permissions.ensureScreenCapture() else { return }
        Task { @MainActor in
            do {
                let snapshot = try await ScreenSnapshotter.capture(screen: screen)
                self.presentOverlay(kind: kind, snapshot: snapshot, screen: screen)
            } catch {
                NSLog("ZoomIt: screen capture failed: \(error)")
            }
        }
    }

    func dismiss() {
        view?.tearDown()
        window?.orderOut(nil)
        window = nil
        view = nil
        NSCursor.unhide()
        onClose?()
    }

    @MainActor
    private func presentOverlay(kind: OverlaySessionKind, snapshot: CGImage?, screen: NSScreen) {
        let win = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = kind != .liveDraw
        win.backgroundColor = kind == .liveDraw ? .clear : .black
        win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.acceptsMouseMovedEvents = true
        win.hasShadow = false

        let overlayView = OverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            sessionKind: kind,
            snapshot: snapshot,
            screen: screen,
            settingsStore: settingsStore
        )
        overlayView.requestClose = { [weak self] in self?.dismiss() }
        win.contentView = overlayView
        win.makeFirstResponder(overlayView)
        window = win
        view = overlayView

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        overlayView.start()
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
