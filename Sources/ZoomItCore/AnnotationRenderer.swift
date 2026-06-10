import CoreGraphics
import CoreText
import Foundation

/// Renders a DrawingModel into a CGContext. Coordinates are in the snapshot's
/// point space with a bottom-left origin (standard Quartz).
public enum AnnotationRenderer {
    /// Width multiplier for highlight pens relative to the solid pen width.
    public static let highlightWidthFactor: CGFloat = 3.5
    public static let highlightAlpha: CGFloat = 0.45

    /// Draw everything: optional board fill, then annotations in order.
    /// - Parameters:
    ///   - blurredBackground: pre-blurred copy of the screenshot, used by blur strokes.
    ///   - canvasSize: drawing canvas size in the context's coordinate space.
    public static func render(model annotations: [Annotation],
                              background: BoardBackground,
                              in ctx: CGContext,
                              canvasSize: CGSize,
                              blurredBackground: CGImage? = nil) {
        switch background {
        case .screen:
            break
        case .whiteboard:
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
        case .blackboard:
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
        }
        for annotation in annotations {
            draw(annotation, in: ctx, canvasSize: canvasSize, blurredBackground: blurredBackground)
        }
    }

    public static func draw(_ annotation: Annotation,
                            in ctx: CGContext,
                            canvasSize: CGSize,
                            blurredBackground: CGImage? = nil) {
        switch annotation {
        case .stroke(let s): drawStroke(s, in: ctx, canvasSize: canvasSize, blurredBackground: blurredBackground)
        case .shape(let s): drawShape(s, in: ctx)
        case .text(let t): drawText(t, in: ctx)
        }
    }

    // MARK: - Strokes

    public static func strokePath(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
        } else if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            // Smooth with quadratic segments through midpoints.
            for i in 1..<points.count - 1 {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                                  y: (points[i].y + points[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: points[i])
            }
            path.addLine(to: points[points.count - 1])
        }
        return path
    }

    private static func drawStroke(_ s: StrokeAnnotation, in ctx: CGContext,
                                   canvasSize: CGSize, blurredBackground: CGImage?) {
        guard !s.points.isEmpty else { return }
        let path = strokePath(for: s.points)
        switch s.style {
        case .solid, .highlight:
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if s.style == .highlight {
                ctx.setLineWidth(s.width * highlightWidthFactor)
                ctx.setStrokeColor(s.color.withAlpha(highlightAlpha).cgColor)
                ctx.setBlendMode(.multiply)
            } else {
                ctx.setLineWidth(s.width)
                ctx.setStrokeColor(s.color.cgColor)
            }
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        case .blur:
            guard let blurred = blurredBackground else { return }
            ctx.saveGState()
            // Clip to the stroke outline, then paint the blurred screenshot inside it.
            let wide = path.copy(strokingWithWidth: max(s.width * highlightWidthFactor, 24),
                                 lineCap: .round, lineJoin: .round, miterLimit: 10)
            ctx.addPath(wide)
            ctx.clip()
            ctx.draw(blurred, in: CGRect(origin: .zero, size: canvasSize))
            ctx.restoreGState()
        }
    }

    // MARK: - Shapes

    private static func drawShape(_ s: ShapeAnnotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        var width = s.width
        var color = s.color
        if s.style == .highlight {
            width = s.width * highlightWidthFactor
            color = s.color.withAlpha(highlightAlpha)
            ctx.setBlendMode(.multiply)
        }
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)

        switch s.kind {
        case .line:
            ctx.move(to: s.start)
            ctx.addLine(to: s.end)
            ctx.strokePath()
        case .rectangle:
            ctx.stroke(s.rect)
        case .ellipse:
            ctx.strokeEllipse(in: s.rect)
        case .arrow:
            drawArrow(from: s.start, to: s.end, width: width, in: ctx)
        }
    }

    /// Arrow geometry: shaft plus a filled triangular head at `end`.
    public static func arrowHeadPoints(from start: CGPoint, to end: CGPoint, width: CGFloat)
        -> (tip: CGPoint, left: CGPoint, right: CGPoint, shaftEnd: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = max(sqrt(dx * dx + dy * dy), 0.0001)
        let ux = dx / len, uy = dy / len
        let headLength = max(width * 4, 14)
        let headHalfWidth = headLength * 0.55
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let px = -uy, py = ux  // perpendicular
        let left = CGPoint(x: base.x + px * headHalfWidth, y: base.y + py * headHalfWidth)
        let right = CGPoint(x: base.x - px * headHalfWidth, y: base.y - py * headHalfWidth)
        return (end, left, right, base)
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, in ctx: CGContext) {
        let head = arrowHeadPoints(from: start, to: end, width: width)
        ctx.move(to: start)
        ctx.addLine(to: head.shaftEnd)
        ctx.strokePath()
        ctx.beginPath()
        ctx.move(to: head.tip)
        ctx.addLine(to: head.left)
        ctx.addLine(to: head.right)
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Text

    public static func font(for annotation: TextAnnotation) -> CTFont {
        CTFontCreateWithName(annotation.fontName as CFString, annotation.fontSize, nil)
    }

    public static func textSize(_ annotation: TextAnnotation) -> CGSize {
        let line = makeLine(annotation)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return CGSize(width: width, height: ascent + descent)
    }

    private static func makeLine(_ annotation: TextAnnotation) -> CTLine {
        let font = font(for: annotation)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: annotation.color.cgColor,
        ]
        let attributed = CFAttributedStringCreate(nil, annotation.text as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(attributed)
    }

    private static func drawText(_ t: TextAnnotation, in ctx: CGContext) {
        guard !t.text.isEmpty else { return }
        // Draw each line of a multi-line annotation stacked downward.
        let lines = t.text.components(separatedBy: "\n")
        let lineHeight = t.fontSize * 1.25
        for (i, lineText) in lines.enumerated() {
            guard !lineText.isEmpty else { continue }
            var single = t
            single.text = lineText
            let line = makeLine(single)
            let width = textSize(single).width
            ctx.saveGState()
            ctx.textMatrix = .identity
            let y = t.origin.y - CGFloat(i) * lineHeight
            let x = t.rightAligned ? t.origin.x - width : t.origin.x
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }
}
