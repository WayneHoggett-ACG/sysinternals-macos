import ImageIO
import XCTest
@testable import ZoomItCore

final class GIFWriterTests: XCTestCase {
    private func solidImage(gray: CGFloat) -> CGImage {
        let ctx = CGContext(
            data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        return ctx.makeImage()!
    }

    func testWritesAnimatedGIF() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomit-test-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = GIFWriter(url: url, frameDelay: 0.1)
        writer.add(frame: solidImage(gray: 0))
        writer.add(frame: solidImage(gray: 0.5))
        writer.add(frame: solidImage(gray: 1))
        try writer.finalize()

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
        let type = try XCTUnwrap(CGImageSourceGetType(source))
        XCTAssertEqual(type as String, "com.compuserve.gif")
    }

    func testEmptyWriterThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomit-test-\(UUID().uuidString).gif")
        let writer = GIFWriter(url: url, frameDelay: 0.1)
        XCTAssertThrowsError(try writer.finalize())
    }
}
