import AppKit
import ScreenCaptureKit
import ZoomItCore

/// LiveZoom (Ctrl+4): magnifies the live screen using a ScreenCaptureKit
/// stream of the display (excluding this app's windows), so animation and
/// video keep playing while zoomed.
final class LiveZoomController: NSObject, SCStreamOutput, SCStreamDelegate {
    private var window: OverlayWindow?
    private var view: LiveZoomView?
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "zoomit.livezoom.samples")
    private let ciContext = CIContext()
    var onClose: (() -> Void)?
    let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var isActive: Bool { window != nil }

    func begin() {
        guard !isActive, Permissions.ensureScreenCapture() else { return }
        let screen = ScreenSnapshotter.screenUnderMouse()

        let win = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = true
        win.backgroundColor = .black
        win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.acceptsMouseMovedEvents = true
        win.hasShadow = false

        let zoomView = LiveZoomView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            initialZoom: ZoomMath.clampZoom(settingsStore.settings.zoomLevel)
        )
        zoomView.requestClose = { [weak self] in self?.dismiss() }
        win.contentView = zoomView
        win.makeFirstResponder(zoomView)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        window = win
        view = zoomView

        Task { @MainActor in
            await self.startStream(screen: screen)
        }
    }

    func dismiss() {
        let streamToStop = stream
        stream = nil
        Task {
            try? await streamToStop?.stopCapture()
        }
        window?.orderOut(nil)
        window = nil
        view = nil
        onClose?()
    }

    @MainActor
    private func startStream(screen: NSScreen) async {
        do {
            let displayID = ScreenSnapshotter.displayID(for: screen)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
            let ourApp = content.applications.first {
                $0.processID == pid_t(ProcessInfo.processInfo.processIdentifier)
            }
            let filter: SCContentFilter
            if let ourApp {
                filter = SCContentFilter(display: display, excludingApplications: [ourApp], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = true
            config.queueDepth = 5
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
            self.stream = stream
        } catch {
            NSLog("ZoomIt: LiveZoom stream failed: \(error)")
            dismiss()
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.view?.currentFrame = cgImage
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.dismiss()
        }
    }
}

final class LiveZoomView: NSView {
    var requestClose: (() -> Void)?
    var currentFrame: CGImage? {
        didSet { needsDisplay = true }
    }

    private let screen: NSScreen
    private var zoom: CGFloat
    private var focus: CGPoint
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, screen: NSScreen, initialZoom: CGFloat) {
        self.screen = screen
        self.zoom = initialZoom
        self.focus = CGPoint(x: frame.midX, y: frame.midY)
        super.init(frame: frame)
        wantsLayer = true
        let mouse = NSEvent.mouseLocation
        focus = CGPoint(x: mouse.x - screen.frame.minX, y: mouse.y - screen.frame.minY)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(bounds)
        guard let frame = currentFrame else { return }
        let src = ZoomMath.sourceRect(zoom: zoom, focus: focus, imageSize: bounds.size)
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: bounds.width / src.width, y: bounds.height / src.height)
        ctx.translateBy(x: -src.minX, y: -src.minY)
        ctx.draw(frame, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }

    override func mouseMoved(with event: NSEvent) {
        focus = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let direction = event.scrollingDeltaY > 0 ? 1 : (event.scrollingDeltaY < 0 ? -1 : 0)
        guard direction != 0 else { return }
        zoom = ZoomMath.steppedZoom(zoom, direction: direction)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            requestClose?()
        case 126: // Up
            zoom = ZoomMath.steppedZoom(zoom, direction: 1)
            needsDisplay = true
        case 125: // Down
            zoom = ZoomMath.steppedZoom(zoom, direction: -1)
            needsDisplay = true
        default:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        requestClose?()
    }
}
