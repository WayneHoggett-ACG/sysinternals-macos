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

    // MARK: - Sparse pages (regression: blank regions caused duplicated content)

    /// A document that is mostly uniform background with one textured content
    /// band, like a web page with a heading and an image on a plain backdrop.
    private func makeSparseFrame(width: Int, height: Int, contentOffset: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height)
        for row in 0..<height {
            let contentRow = row + contentOffset
            let inBand = (contentRow % 160) < 50
            for col in 0..<width {
                if inBand {
                    let v = (contentRow * 37 + (contentRow % 7) * 31 + (col / 4) * 13) % 251
                    pixels[row * width + col] = UInt8(v)
                } else {
                    pixels[row * width + col] = 230 // blank background
                }
            }
        }
        return ctx.makeImage()!
    }

    /// The reported bug: scrolling a sparse page duplicated whole sections,
    /// because a tiny all-blank overlap at a huge shift outscored the true
    /// alignment. The detected shift must be the real scroll distance.
    func testSparsePageScrollDoesNotDuplicate() {
        let stitcher = PanoramaStitcher()
        stitcher.append(makeSparseFrame(width: 200, height: 100, contentOffset: 0))
        let shift = stitcher.append(makeSparseFrame(width: 200, height: 100, contentOffset: 30))
        XCTAssertEqual(shift, 30, "must lock onto the content band, not the blank background")
        XCTAssertEqual(stitcher.totalHeight, 130, "panorama must grow by the scroll distance only")
    }

    func testSparsePageDuplicateFrameSkipped() {
        let stitcher = PanoramaStitcher()
        stitcher.append(makeSparseFrame(width: 200, height: 100, contentOffset: 0))
        let shift = stitcher.append(makeSparseFrame(width: 200, height: 100, contentOffset: 0))
        XCTAssertEqual(shift, 0)
        XCTAssertEqual(stitcher.totalHeight, 100)
    }

    /// Frames with no structure at all (fully blank) carry no alignment
    /// information; they must be skipped rather than appended.
    func testFullyBlankFrameSkipped() {
        let stitcher = PanoramaStitcher()
        stitcher.append(makeSparseFrame(width: 200, height: 100, contentOffset: 0))
        let blankA = PanoramaStitcher.signature(for: makeSparseFrame(width: 200, height: 100, contentOffset: 60), sampleColumns: 48)!
        let blankB = PanoramaStitcher.signature(for: makeSparseFrame(width: 200, height: 100, contentOffset: 70), sampleColumns: 48)!
        // Offsets 60/70 put both frames fully in the blank gap (rows 50..159).
        XCTAssertEqual(PanoramaStitcher.bestVerticalShift(previous: blankA, current: blankB), 0)
    }

    /// Scrolling farther than the safe overlap between captures must skip the
    /// frame instead of guessing a bogus alignment.
    func testExcessiveScrollRejected() {
        let a = PanoramaStitcher.signature(for: makeFrame(width: 200, height: 100, contentOffset: 0), sampleColumns: 48)!
        let b = PanoramaStitcher.signature(for: makeFrame(width: 200, height: 100, contentOffset: 95), sampleColumns: 48)!
        XCTAssertEqual(PanoramaStitcher.bestVerticalShift(previous: a, current: b), 0)
    }
}
