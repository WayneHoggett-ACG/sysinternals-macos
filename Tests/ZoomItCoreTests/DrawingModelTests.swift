import XCTest
@testable import ZoomItCore

final class DrawingModelTests: XCTestCase {
    func makeStroke() -> Annotation {
        .stroke(StrokeAnnotation(points: [.zero, CGPoint(x: 10, y: 10)], color: .red, width: 5))
    }

    func testAddAndUndo() {
        let model = DrawingModel()
        model.add(makeStroke())
        model.add(.shape(ShapeAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 50, y: 50), color: .blue, width: 3)))
        XCTAssertEqual(model.annotations.count, 2)
        XCTAssertTrue(model.undo())
        XCTAssertEqual(model.annotations.count, 1)
        XCTAssertTrue(model.undo())
        XCTAssertTrue(model.isEmpty)
        XCTAssertFalse(model.undo(), "undo on empty model should report failure")
    }

    func testClear() {
        let model = DrawingModel()
        for _ in 0..<5 { model.add(makeStroke()) }
        model.clear()
        XCTAssertTrue(model.isEmpty)
    }

    func testBoardToggle() {
        let model = DrawingModel()
        XCTAssertEqual(model.background, .screen)
        model.toggleBoard(.whiteboard)
        XCTAssertEqual(model.background, .whiteboard)
        model.toggleBoard(.whiteboard)
        XCTAssertEqual(model.background, .screen, "same key toggles back to screen")
        model.toggleBoard(.whiteboard)
        model.toggleBoard(.blackboard)
        XCTAssertEqual(model.background, .blackboard, "other board switches directly")
    }

    func testShapeRectNormalizesNegativeDrag() {
        let shape = ShapeAnnotation(kind: .rectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 20, y: 40), color: .red, width: 2)
        XCTAssertEqual(shape.rect, CGRect(x: 20, y: 40, width: 80, height: 60))
    }

    func testArrowHeadGeometry() {
        let head = AnnotationRenderer.arrowHeadPoints(from: .zero, to: CGPoint(x: 100, y: 0), width: 5)
        XCTAssertEqual(head.tip, CGPoint(x: 100, y: 0))
        XCTAssertLessThan(head.shaftEnd.x, 100, "shaft ends before the tip")
        XCTAssertEqual(head.left.y, -head.right.y, accuracy: 0.001, "head is symmetric about the shaft")
    }

    func testRendererSmokeTest() throws {
        // Render every annotation type into a bitmap and make sure pixels changed.
        let size = CGSize(width: 200, height: 200)
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let annotations: [Annotation] = [
            .stroke(StrokeAnnotation(points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 60)], color: .red, width: 5)),
            .stroke(StrokeAnnotation(points: [CGPoint(x: 20, y: 150), CGPoint(x: 120, y: 150)], color: .yellow, width: 5, style: .highlight)),
            .shape(ShapeAnnotation(kind: .rectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 90, y: 80), color: .blue, width: 3)),
            .shape(ShapeAnnotation(kind: .ellipse, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 180, y: 160), color: .green, width: 3)),
            .shape(ShapeAnnotation(kind: .arrow, start: CGPoint(x: 10, y: 180), end: CGPoint(x: 180, y: 20), color: .orange, width: 4)),
            .text(TextAnnotation(origin: CGPoint(x: 40, y: 40), text: "Hi\nthere", color: .pink, fontSize: 20)),
        ]
        AnnotationRenderer.render(model: annotations, background: .whiteboard, in: ctx, canvasSize: size)
        let image = try XCTUnwrap(ctx.makeImage())
        XCTAssertEqual(image.width, 200)
        // Verify the canvas is not uniformly white anymore.
        let data = try XCTUnwrap(ctx.data)
        let pixels = data.bindMemory(to: UInt8.self, capacity: 200 * ctx.bytesPerRow)
        var foundNonWhite = false
        for i in stride(from: 0, to: 200 * ctx.bytesPerRow, by: 4) where pixels[i] < 240 {
            foundNonWhite = true
            break
        }
        XCTAssertTrue(foundNonWhite, "rendering should have drawn non-white pixels")
    }

    func testBlurStrokeUsesBlurredBackground() throws {
        let size = CGSize(width: 100, height: 100)
        // Background: black. Blurred background: white. A blur stroke should
        // paint white pixels through the clip.
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let whiteCtx = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        whiteCtx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        whiteCtx.fill(CGRect(origin: .zero, size: size))
        let white = try XCTUnwrap(whiteCtx.makeImage())

        let blurStroke = Annotation.stroke(StrokeAnnotation(
            points: [CGPoint(x: 50, y: 50), CGPoint(x: 60, y: 50)],
            color: .red, width: 10, style: .blur
        ))
        AnnotationRenderer.draw(blurStroke, in: ctx, canvasSize: size, blurredBackground: white)

        let data = try XCTUnwrap(ctx.data)
        let pixels = data.bindMemory(to: UInt8.self, capacity: 100 * ctx.bytesPerRow)
        // Sample the stroke center (row 50 → bitmap row 49 from top in CG bottom-left space: row index = 100-1-50).
        let row = 100 - 1 - 50
        let offset = row * ctx.bytesPerRow + 55 * 4
        XCTAssertGreaterThan(pixels[offset], 200, "blur stroke should reveal the blurred (white) background")
    }
}
