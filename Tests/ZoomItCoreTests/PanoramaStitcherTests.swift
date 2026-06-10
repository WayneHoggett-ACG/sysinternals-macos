import XCTest
@testable import ZoomItCore

final class PanoramaStitcherTests: XCTestCase {
    /// Render a window into tall synthetic "content" at a given scroll offset,
    /// like a screenshot of a scrolling document.
    private func makeFrame(width: Int, height: Int, contentOffset: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height)
        for row in 0..<height {
            // Content row in the synthetic document; vary with strong structure.
            let contentRow = row + contentOffset
            for col in 0..<width {
                let v = (contentRow * 37 + (contentRow % 7) * 31 + col / 8) % 251
                pixels[row * width + col] = UInt8(v)
            }
        }
        return ctx.makeImage()!
    }

    func testFirstFrameTakenWhole() {
        let stitcher = PanoramaStitcher()
        let shift = stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 0))
        XCTAssertEqual(shift, 100)
        XCTAssertEqual(stitcher.totalHeight, 100)
    }

    func testDuplicateFrameSkipped() {
        let stitcher = PanoramaStitcher()
        stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 0))
        let shift = stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 0))
        XCTAssertEqual(shift, 0, "identical frame means no scroll")
        XCTAssertEqual(stitcher.totalHeight, 100)
    }

    func testScrollDetected() {
        let stitcher = PanoramaStitcher()
        stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 0))
        let shift = stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 30))
        XCTAssertEqual(shift, 30, "30-row scroll should be detected")
        XCTAssertEqual(stitcher.totalHeight, 130)
    }

    func testPanoramaAssembly() throws {
        let stitcher = PanoramaStitcher()
        stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 0))
        stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 40))
        stitcher.append(makeFrame(width: 200, height: 100, contentOffset: 80))
        XCTAssertEqual(stitcher.totalHeight, 180)
        let panorama = try XCTUnwrap(stitcher.makePanorama())
        XCTAssertEqual(panorama.width, 200)
        XCTAssertEqual(panorama.height, 180)
    }

    func testBestVerticalShiftExactMatch() {
        let a = PanoramaStitcher.signature(for: makeFrame(width: 200, height: 100, contentOffset: 0), sampleColumns: 48)!
        let b = PanoramaStitcher.signature(for: makeFrame(width: 200, height: 100, contentOffset: 25), sampleColumns: 48)!
        XCTAssertEqual(PanoramaStitcher.bestVerticalShift(previous: a, current: b), 25)
    }
}
