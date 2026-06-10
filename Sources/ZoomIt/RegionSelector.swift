import AppKit

/// Fullscreen rubber-band region picker used by snip, cropped recording, and
/// panorama. Calls back with the selected rect in global (Cocoa) screen
/// coordinates, or nil if cancelled.
final class RegionSelector {
    private var window: OverlayWindow?
    private var completion: ((NSRect?) -> Void)?
    static var current: RegionSelector?

    func begin(on screen: NSScreen, completion: @escaping (NSRect?) -> Void) {
        self.completion = completion
        let win = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.acceptsMouseMovedEvents = true
        win.hasShadow = false

        let view = RegionSelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] localRect in
            guard let self else { return }
            let globalRect = localRect.map { rect in
                NSRect(
                    x: rect.minX + screen.frame.minX,
                    y: rect.minY + screen.frame.minY,
                    width: rect.width,
                    height: rect.height
                )
            }
            self.dismiss()
            self.completion?(globalRect)
            self.completion = nil
            RegionSelector.current = nil
        }
        win.contentView = view
        win.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        window = win
        RegionSelector.current = self
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
        NSCursor.unhide()
    }
}

final class RegionSelectorView: NSView {
    var onFinish: ((NSRect?) -> Void)?
    private var start: CGPoint?
    private var rect: CGRect?
    private var mouse: CGPoint = .zero
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NSCursor.crosshair.set()
        mouse = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.25))
        if let rect {
            ctx.addRect(bounds)
            ctx.addRect(rect)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.setLineWidth(1.5)
            ctx.stroke(rect)
            // Size readout
            let label = "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            let labelOrigin = CGPoint(x: rect.maxX - size.width, y: max(rect.minY - size.height - 6, 4))
            let bg = CGRect(x: labelOrigin.x - 6, y: labelOrigin.y - 3, width: size.width + 12, height: size.height + 6)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.7))
            ctx.fill(bg)
            label.draw(at: labelOrigin, withAttributes: attrs)
        } else {
            ctx.fill(bounds)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        rect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = start {
            rect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let rect, rect.width > 4, rect.height > 4 {
            onFinish?(rect)
        } else {
            onFinish?(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish?(nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }
}
