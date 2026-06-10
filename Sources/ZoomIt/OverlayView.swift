import AppKit
import CoreImage
import ZoomItCore

/// The fullscreen interactive surface implementing ZoomIt's zoom, draw, and
/// type modes. Annotation coordinates live in "image space" = the overlay's
/// bounds in points with a bottom-left origin; the zoom transform maps image
/// space to the view.
final class OverlayView: NSView {
    enum Mode {
        case zoomPan          // panning/zooming the static screenshot
        case draw             // pen and shapes
        case typing           // type-in-text
        case cropSelect(CropAction)
    }

    enum CropAction {
        case copy, save
    }

    let sessionKind: OverlaySessionKind
    private let screen: NSScreen
    private let settingsStore: SettingsStore
    var requestClose: (() -> Void)?

    // Screenshot state
    private var snapshot: CGImage?
    private var blurredSnapshot: CGImage?

    // Zoom state
    private(set) var zoom: CGFloat = 1.0
    private var focus: CGPoint = .zero            // image-space point the zoom centers on
    private var frozenSourceRect: CGRect?         // pan frozen while drawing zoomed
    private var animationTimer: Timer?

    // Drawing state
    private(set) var mode: Mode = .draw
    let model = DrawingModel()
    private var penColor: PenColor = .red
    private var penStyle: PenStyle = .solid
    private var penWidth: CGFloat = 5
    private var activeStroke: [CGPoint] = []
    private var activeShape: ShapeAnnotation?
    private var dragStart: CGPoint?
    private var tabHeld = false

    // Typing state
    private var typingAnnotation: TextAnnotation?
    private var fontSize: CGFloat = 36

    // Crop state
    private var cropStart: CGPoint?
    private var cropRect: CGRect?

    private var mouseLocation: CGPoint = .zero    // view points
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, sessionKind: OverlaySessionKind, snapshot: CGImage?, screen: NSScreen, settingsStore: SettingsStore) {
        self.sessionKind = sessionKind
        self.snapshot = snapshot
        self.screen = screen
        self.settingsStore = settingsStore
        super.init(frame: frame)
        wantsLayer = true
        let s = settingsStore.settings
        penColor = s.penColor.color
        penWidth = s.penWidth
        fontSize = s.fontSize
        mouseLocation = convertFromScreen(NSEvent.mouseLocation)
        focus = mouseLocation
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    func start() {
        switch sessionKind {
        case .zoom:
            mode = .zoomPan
            let target = ZoomMath.clampZoom(settingsStore.settings.zoomLevel)
            if settingsStore.settings.animateZoom {
                animateZoom(to: target)
            } else {
                zoom = target
            }
        case .draw, .liveDraw:
            mode = .draw
        }
        NSCursor.hide()
        needsDisplay = true
    }

    func tearDown() {
        animationTimer?.invalidate()
        animationTimer = nil
        persistPenSettings()
    }

    private func persistPenSettings() {
        let width = penWidth
        let size = fontSize
        settingsStore.update { s in
            s.penWidth = width
            s.fontSize = size
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func convertFromScreen(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x - screen.frame.minX, y: p.y - screen.frame.minY)
    }

    // MARK: - Zoom geometry

    private var imageSize: CGSize { bounds.size }

    private var sourceRect: CGRect {
        if let frozen = frozenSourceRect { return frozen }
        return ZoomMath.sourceRect(zoom: zoom, focus: focus, imageSize: imageSize)
    }

    private func imagePoint(forViewPoint p: CGPoint) -> CGPoint {
        ZoomMath.imagePoint(forViewPoint: p, viewSize: bounds.size, sourceRect: sourceRect)
    }

    private func animateZoom(to target: CGFloat, then completion: (() -> Void)? = nil) {
        animationTimer?.invalidate()
        let start = zoom
        let duration: TimeInterval = 0.2
        let startTime = CACurrentMediaTime()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = CGFloat(min(1, (CACurrentMediaTime() - startTime) / duration))
            self.zoom = ZoomMath.interpolatedZoom(from: start, to: target, t: t)
            self.needsDisplay = true
            if t >= 1 {
                timer.invalidate()
                self.animationTimer = nil
                completion?()
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if sessionKind == .liveDraw && model.background == .screen {
            ctx.clear(bounds)
        }

        ctx.saveGState()
        applyZoomTransform(ctx)
        drawBackground(in: ctx)
        AnnotationRenderer.render(
            model: model.annotations,
            background: model.background,
            in: ctx,
            canvasSize: imageSize,
            blurredBackground: blurredBackgroundIfNeeded()
        )
        drawActiveAnnotation(in: ctx)
        drawTypingAnnotation(in: ctx)
        ctx.restoreGState()

        drawCropSelection(in: ctx)
        drawCursor(in: ctx)
    }

    private func applyZoomTransform(_ ctx: CGContext) {
        let src = sourceRect
        guard src.width > 0, src.height > 0 else { return }
        ctx.scaleBy(x: bounds.width / src.width, y: bounds.height / src.height)
        ctx.translateBy(x: -src.minX, y: -src.minY)
    }

    private func drawBackground(in ctx: CGContext) {
        guard model.background == .screen else { return }  // boards filled by renderer
        if let snapshot {
            ctx.interpolationQuality = zoom > 1.5 ? .none : .high
            ctx.draw(snapshot, in: CGRect(origin: .zero, size: imageSize))
        }
    }

    private func blurredBackgroundIfNeeded() -> CGImage? {
        let hasBlur = model.annotations.contains {
            if case .stroke(let s) = $0, s.style == .blur { return true }
            return false
        } || penStyle == .blur
        guard hasBlur, blurredSnapshot == nil, let snapshot else { return blurredSnapshot }
        let ciImage = CIImage(cgImage: snapshot)
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(14.0, forKey: kCIInputRadiusKey)
        if let output = filter.outputImage {
            let context = CIContext()
            blurredSnapshot = context.createCGImage(output.clampedToExtent(), from: ciImage.extent)
        }
        return blurredSnapshot
    }

    private func drawActiveAnnotation(in ctx: CGContext) {
        if activeStroke.count > 1 {
            let stroke = StrokeAnnotation(points: activeStroke, color: penColor, width: penWidth, style: penStyle)
            AnnotationRenderer.draw(.stroke(stroke), in: ctx, canvasSize: imageSize, blurredBackground: blurredBackgroundIfNeeded())
        }
        if let shape = activeShape {
            AnnotationRenderer.draw(.shape(shape), in: ctx, canvasSize: imageSize)
        }
    }

    private func drawTypingAnnotation(in ctx: CGContext) {
        guard case .typing = mode, let t = typingAnnotation else { return }
        AnnotationRenderer.draw(.text(t), in: ctx, canvasSize: imageSize)
        // Caret at the end of the last line.
        let lines = t.text.components(separatedBy: "\n")
        let lastLine = lines.last ?? ""
        var single = t
        single.text = lastLine
        let width = lastLine.isEmpty ? 0 : AnnotationRenderer.textSize(single).width
        let lineHeight = t.fontSize * 1.25
        let y = t.origin.y - CGFloat(lines.count - 1) * lineHeight
        let caretX = t.rightAligned ? t.origin.x : t.origin.x + width
        ctx.setStrokeColor(t.color.cgColor)
        ctx.setLineWidth(max(2, t.fontSize / 16))
        ctx.move(to: CGPoint(x: caretX, y: y - t.fontSize * 0.2))
        ctx.addLine(to: CGPoint(x: caretX, y: y + t.fontSize * 0.85))
        ctx.strokePath()
    }

    private func drawCropSelection(in ctx: CGContext) {
        guard case .cropSelect = mode else { return }
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
        if let rect = cropRect {
            ctx.addRect(bounds)
            ctx.addRect(rect)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setLineWidth(1.5)
            ctx.stroke(rect)
        } else {
            ctx.fill(bounds)
        }
        ctx.restoreGState()
    }

    private func drawCursor(in ctx: CGContext) {
        switch mode {
        case .draw:
            let displayWidth = max(penWidth * zoomDisplayScale, 3)
            let rect = CGRect(
                x: mouseLocation.x - displayWidth / 2,
                y: mouseLocation.y - displayWidth / 2,
                width: displayWidth,
                height: displayWidth
            )
            ctx.setFillColor(penStyle == .blur
                ? CGColor(gray: 0.6, alpha: 0.7)
                : penColor.withAlpha(penStyle == .highlight ? 0.6 : 1).cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.8))
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: rect.insetBy(dx: -1, dy: -1))
        case .cropSelect:
            // Crosshair
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: mouseLocation.x - 12, y: mouseLocation.y))
            ctx.addLine(to: CGPoint(x: mouseLocation.x + 12, y: mouseLocation.y))
            ctx.move(to: CGPoint(x: mouseLocation.x, y: mouseLocation.y - 12))
            ctx.addLine(to: CGPoint(x: mouseLocation.x, y: mouseLocation.y + 12))
            ctx.strokePath()
        case .zoomPan, .typing:
            break
        }
    }

    private var zoomDisplayScale: CGFloat {
        bounds.width / sourceRect.width
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        if case .zoomPan = mode {
            focus = mouseLocation
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseLocation = p
        switch mode {
        case .zoomPan:
            // Left-click while zoomed: freeze the pan and start drawing.
            frozenSourceRect = sourceRect
            mode = .draw
            beginDrag(at: p, event: event)
        case .draw:
            beginDrag(at: p, event: event)
        case .typing:
            commitTyping()
            startTyping(at: p, rightAligned: false)
        case .cropSelect:
            cropStart = p
            cropRect = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseLocation = p
        switch mode {
        case .draw:
            continueDrag(at: p)
        case .cropSelect:
            if let start = cropStart {
                cropRect = CGRect(
                    x: min(start.x, p.x), y: min(start.y, p.y),
                    width: abs(p.x - start.x), height: abs(p.y - start.y)
                )
            }
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .draw:
            endDrag()
        case .cropSelect(let action):
            if let rect = cropRect, rect.width > 4, rect.height > 4 {
                finishCrop(action: action, rect: rect)
            } else {
                mode = previousModeAfterCrop()
            }
            cropStart = nil
            cropRect = nil
        default:
            break
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        switch mode {
        case .typing:
            commitTyping()
            mode = .draw
        case .draw where sessionKind == .zoom && zoom > 1.01:
            // Stop drawing: back to pan/zoom.
            activeStroke = []
            activeShape = nil
            frozenSourceRect = nil
            mode = .zoomPan
            focus = imagePoint(forViewPoint: mouseLocation)
        case .cropSelect:
            mode = previousModeAfterCrop()
        default:
            exitOverlay()
        }
        needsDisplay = true
    }

    private func beginDrag(at viewPoint: CGPoint, event: NSEvent) {
        let p = imagePoint(forViewPoint: viewPoint)
        dragStart = p
        let flags = event.modifierFlags
        let shift = flags.contains(.shift)
        let ctrl = flags.contains(.control)
        if ctrl && shift {
            activeShape = ShapeAnnotation(kind: .arrow, start: p, end: p, color: penColor, width: penWidth, style: penStyle == .highlight ? .highlight : .solid)
        } else if ctrl {
            activeShape = ShapeAnnotation(kind: .rectangle, start: p, end: p, color: penColor, width: penWidth, style: penStyle == .highlight ? .highlight : .solid)
        } else if shift {
            activeShape = ShapeAnnotation(kind: .line, start: p, end: p, color: penColor, width: penWidth, style: penStyle == .highlight ? .highlight : .solid)
        } else if tabHeld {
            activeShape = ShapeAnnotation(kind: .ellipse, start: p, end: p, color: penColor, width: penWidth, style: penStyle == .highlight ? .highlight : .solid)
        } else {
            activeStroke = [p]
        }
    }

    private func continueDrag(at viewPoint: CGPoint) {
        let p = imagePoint(forViewPoint: viewPoint)
        if activeShape != nil {
            activeShape?.end = p
        } else if !activeStroke.isEmpty {
            activeStroke.append(p)
        }
    }

    private func endDrag() {
        if let shape = activeShape {
            model.add(.shape(shape))
        } else if activeStroke.count > 1 {
            model.add(.stroke(StrokeAnnotation(points: activeStroke, color: penColor, width: penWidth, style: penStyle)))
        }
        activeShape = nil
        activeStroke = []
        dragStart = nil
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        let direction = event.scrollingDeltaY > 0 ? 1 : (event.scrollingDeltaY < 0 ? -1 : 0)
        guard direction != 0 else { return }
        let ctrl = event.modifierFlags.contains(.control)
        switch mode {
        case .zoomPan:
            zoom = ZoomMath.steppedZoom(zoom, direction: direction)
        case .draw where ctrl:
            adjustPenWidth(by: direction)
        case .typing where ctrl:
            adjustFontSize(by: direction)
        default:
            return
        }
        needsDisplay = true
    }

    private func adjustPenWidth(by direction: Int) {
        penWidth = min(max(penWidth + CGFloat(direction), 1), 40)
    }

    private func adjustFontSize(by direction: Int) {
        fontSize = min(max(fontSize + CGFloat(direction) * 2, 8), 160)
        typingAnnotation?.fontSize = fontSize
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if case .typing = mode {
            handleTypingKey(event)
            return
        }

        let flags = event.modifierFlags
        let ctrlOrCmd = flags.contains(.control) || flags.contains(.command)
        let shift = flags.contains(.shift)

        switch event.keyCode {
        case 53: // Esc
            if case .cropSelect = mode {
                mode = previousModeAfterCrop()
                needsDisplay = true
            } else {
                exitOverlay()
            }
            return
        case 48: // Tab held → ellipse modifier
            tabHeld = true
            return
        case 126: // Up
            handleVerticalArrow(direction: 1)
            return
        case 125: // Down
            handleVerticalArrow(direction: -1)
            return
        case 49: // Space: center the cursor
            centerCursor()
            return
        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(), let ch = chars.first else { return }

        if ctrlOrCmd {
            switch ch {
            case "z":
                model.undo()
                needsDisplay = true
            case "c":
                if shift { beginCrop(.copy) } else { copyComposite() }
            case "s":
                if shift { beginCrop(.save) } else { saveComposite() }
            default:
                break
            }
            return
        }

        switch ch {
        case "r": setPen(.red, highlight: shift)
        case "g": setPen(.green, highlight: shift)
        case "b": setPen(.blue, highlight: shift)
        case "y": setPen(.yellow, highlight: shift)
        case "o": setPen(.orange, highlight: shift)
        case "p": setPen(.pink, highlight: shift)
        case "x":
            guard snapshot != nil else { break }   // blur needs a screenshot
            penStyle = .blur
            enterDrawIfPanning()
        case "w":
            model.toggleBoard(.whiteboard)
            enterDrawIfPanning()
        case "k":
            model.toggleBoard(.blackboard)
            enterDrawIfPanning()
        case "e":
            model.clear()
        case "t":
            enterDrawIfPanning()
            startTyping(at: mouseLocation, rightAligned: shift)
        default:
            return
        }
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 48 {
            tabHeld = false
        }
    }

    private func handleVerticalArrow(direction: Int) {
        switch mode {
        case .zoomPan:
            zoom = ZoomMath.steppedZoom(zoom, direction: direction)
        case .draw:
            adjustPenWidth(by: direction)
        default:
            break
        }
        needsDisplay = true
    }

    private func setPen(_ color: PenColor, highlight: Bool) {
        penColor = color
        penStyle = highlight ? .highlight : .solid
        enterDrawIfPanning()
        if case .typing = mode {
            typingAnnotation?.color = color
        }
    }

    /// Color/board/type keys pressed during zoom-pan enter drawing mode, like ZoomIt.
    private func enterDrawIfPanning() {
        if case .zoomPan = mode {
            frozenSourceRect = sourceRect
            mode = .draw
        }
    }

    private func centerCursor() {
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        // CGWarpMouseCursorPosition uses top-left-origin global coordinates.
        let primaryHeight = NSScreen.screens[0].frame.maxY
        CGWarpMouseCursorPosition(CGPoint(x: center.x, y: primaryHeight - center.y))
        mouseLocation = convertFromScreen(center)
        if case .zoomPan = mode {
            focus = mouseLocation
        }
        needsDisplay = true
    }

    private func exitOverlay() {
        if sessionKind == .zoom && settingsStore.settings.animateZoom && zoom > 1.01 && frozenSourceRect == nil {
            animateZoom(to: 1.0) { [weak self] in
                self?.requestClose?()
            }
        } else {
            requestClose?()
        }
    }

    // MARK: - Typing mode

    private func startTyping(at viewPoint: CGPoint, rightAligned: Bool) {
        let p = imagePoint(forViewPoint: viewPoint)
        typingAnnotation = TextAnnotation(
            origin: p,
            text: "",
            color: penColor,
            fontSize: fontSize,
            fontName: settingsStore.settings.fontName,
            rightAligned: rightAligned
        )
        mode = .typing
        needsDisplay = true
    }

    private func commitTyping() {
        if let t = typingAnnotation, !t.text.isEmpty {
            model.add(.text(t))
        }
        typingAnnotation = nil
    }

    private func handleTypingKey(_ event: NSEvent) {
        let ctrl = event.modifierFlags.contains(.control)
        switch event.keyCode {
        case 53: // Esc ends typing
            commitTyping()
            mode = .draw
            needsDisplay = true
            return
        case 126: // Up
            adjustFontSize(by: 1)
            needsDisplay = true
            return
        case 125: // Down
            adjustFontSize(by: -1)
            needsDisplay = true
            return
        case 36: // Return: newline
            typingAnnotation?.text.append("\n")
            needsDisplay = true
            return
        case 51: // Backspace
            if var t = typingAnnotation, !t.text.isEmpty {
                t.text.removeLast()
                typingAnnotation = t
            }
            needsDisplay = true
            return
        default:
            break
        }
        if let chars = event.characters, !chars.isEmpty,
           !event.modifierFlags.contains(.command), !ctrl {
            typingAnnotation?.text.append(chars)
            needsDisplay = true
        }
    }

    // MARK: - Copy / Save

    private func previousModeAfterCrop() -> Mode {
        sessionKind == .zoom && frozenSourceRect == nil ? .zoomPan : .draw
    }

    private func beginCrop(_ action: CropAction) {
        mode = .cropSelect(action)
        cropStart = nil
        cropRect = nil
        needsDisplay = true
    }

    private func finishCrop(action: CropAction, rect: CGRect) {
        mode = previousModeAfterCrop()
        produceComposite { [weak self] image in
            guard let self, let image else { return }
            let scale = CGFloat(image.width) / self.bounds.width
            let pixelRect = CGRect(
                x: rect.minX * scale,
                y: (self.bounds.height - rect.maxY) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            guard let cropped = image.cropping(to: pixelRect) else { return }
            switch action {
            case .copy:
                cropped.copyToPasteboard()
                self.flash()
            case .save:
                self.promptSave(image: cropped)
            }
        }
    }

    private func copyComposite() {
        produceComposite { [weak self] image in
            guard let image else { return }
            image.copyToPasteboard()
            self?.flash()
        }
    }

    private func saveComposite() {
        produceComposite { [weak self] image in
            guard let self, let image else { return }
            self.promptSave(image: image)
        }
    }

    private func promptSave(image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = SaveNamer.timestampedURL(
            in: settingsStore.settings.saveFolderURL, prefix: "ZoomIt", ext: "png"
        ).lastPathComponent
        panel.directoryURL = settingsStore.settings.saveFolderURL
        // The overlay sits at shielding level; lift the panel above it.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            if response == .OK, let url = panel.url {
                image.savePNG(to: url)
            }
        }
    }

    /// Brief white flash as copy feedback.
    private func flash() {
        guard let layer else { return }
        let flashLayer = CALayer()
        flashLayer.frame = layer.bounds
        flashLayer.backgroundColor = CGColor(gray: 1, alpha: 0.35)
        layer.addSublayer(flashLayer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            flashLayer.removeFromSuperlayer()
        }
    }

    /// Render what is currently displayed (zoom, boards, annotations) into a
    /// bitmap at native pixel resolution. For LiveDraw, captures a fresh
    /// screenshot to composite under the annotations.
    private func produceComposite(_ completion: @escaping (CGImage?) -> Void) {
        if sessionKind == .liveDraw && model.background == .screen {
            // Hide our window briefly out of the capture (it is excluded by
            // the snapshotter via window filtering anyway).
            Task { @MainActor in
                let background = try? await ScreenSnapshotter.capture(screen: self.screen)
                completion(self.renderComposite(background: background))
            }
        } else {
            completion(renderComposite(background: snapshot))
        }
    }

    private func renderComposite(background: CGImage?) -> CGImage? {
        let scale = screen.backingScaleFactor
        let pixelWidth = Int(bounds.width * scale)
        let pixelHeight = Int(bounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0,
              let ctx = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        applyZoomTransform(ctx)
        if model.background == .screen, let background {
            ctx.draw(background, in: CGRect(origin: .zero, size: imageSize))
        }
        AnnotationRenderer.render(
            model: model.annotations,
            background: model.background,
            in: ctx,
            canvasSize: imageSize,
            blurredBackground: blurredBackgroundIfNeeded()
        )
        if case .typing = mode, let t = typingAnnotation, !t.text.isEmpty {
            AnnotationRenderer.draw(.text(t), in: ctx, canvasSize: imageSize)
        }
        return ctx.makeImage()
    }
}
