import XCTest
@testable import ZoomItCore

final class ZoomMathTests: XCTestCase {
    let imageSize = CGSize(width: 1920, height: 1080)

    func testSourceRectAtNoZoomIsFullImage() {
        let rect = ZoomMath.sourceRect(zoom: 1, focus: CGPoint(x: 500, y: 500), imageSize: imageSize)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: imageSize))
    }

    func testSourceRectCentersOnFocus() {
        let rect = ZoomMath.sourceRect(zoom: 2, focus: CGPoint(x: 960, y: 540), imageSize: imageSize)
        XCTAssertEqual(rect.midX, 960, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 540, accuracy: 0.001)
        XCTAssertEqual(rect.width, 960, accuracy: 0.001)
        XCTAssertEqual(rect.height, 540, accuracy: 0.001)
    }

    func testSourceRectClampsAtEdges() {
        let topLeft = ZoomMath.sourceRect(zoom: 4, focus: .zero, imageSize: imageSize)
        XCTAssertEqual(topLeft.origin, .zero)
        let bottomRight = ZoomMath.sourceRect(zoom: 4, focus: CGPoint(x: 1920, y: 1080), imageSize: imageSize)
        XCTAssertEqual(bottomRight.maxX, 1920, accuracy: 0.001)
        XCTAssertEqual(bottomRight.maxY, 1080, accuracy: 0.001)
    }

    func testZoomClamping() {
        XCTAssertEqual(ZoomMath.clampZoom(0.5), 1.0)
        XCTAssertEqual(ZoomMath.clampZoom(100), 32.0)
        XCTAssertEqual(ZoomMath.clampZoom(2), 2.0)
    }

    func testSteppedZoomUpAndDownAreInverse() {
        let up = ZoomMath.steppedZoom(2.0, direction: 1)
        let down = ZoomMath.steppedZoom(up, direction: -1)
        XCTAssertEqual(down, 2.0, accuracy: 0.0001)
        XCTAssertGreaterThan(up, 2.0)
    }

    func testSteppedZoomFourStepsDoubles() {
        var z: CGFloat = 2.0
        for _ in 0..<4 { z = ZoomMath.steppedZoom(z, direction: 1) }
        XCTAssertEqual(z, 4.0, accuracy: 0.001)
    }

    func testImagePointRoundTrip() {
        let src = ZoomMath.sourceRect(zoom: 2, focus: CGPoint(x: 960, y: 540), imageSize: imageSize)
        let viewPoint = CGPoint(x: 960, y: 540) // center of the view
        let imagePoint = ZoomMath.imagePoint(forViewPoint: viewPoint, viewSize: imageSize, sourceRect: src)
        XCTAssertEqual(imagePoint.x, 960, accuracy: 0.001)
        XCTAssertEqual(imagePoint.y, 540, accuracy: 0.001)
    }

    func testInterpolatedZoomEndpointsAndMonotonicity() {
        XCTAssertEqual(ZoomMath.interpolatedZoom(from: 1, to: 4, t: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(ZoomMath.interpolatedZoom(from: 1, to: 4, t: 1), 4, accuracy: 0.0001)
        // Geometric midpoint of 1 and 4 is 2.
        XCTAssertEqual(ZoomMath.interpolatedZoom(from: 1, to: 4, t: 0.5), 2, accuracy: 0.0001)
    }
}
