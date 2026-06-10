import CoreGraphics
import Foundation

/// Stitches a sequence of screen captures of a scrolling region into one tall
/// image (ZoomIt's panorama / scrolling-screenshot feature, Ctrl+8).
///
/// Strategy: convert each frame to a small grayscale "row signature" matrix,
/// then find the vertical offset between the previous and current frame that
/// minimizes mean absolute difference. New rows revealed by scrolling are
/// appended to the composite.
public final class PanoramaStitcher {
    /// One row signature per pixel row: mean luminance of the row, downsampled horizontally.
    struct FrameSignature {
        let rows: [[Float]]   // [row][sampledColumn]
    }

    public private(set) var compositeFrames: [(image: CGImage, appendFromRow: Int)] = []
    private var previousSignature: FrameSignature?
    private var previousImage: CGImage?
    public private(set) var totalHeight: Int = 0
    private let sampleColumns = 48
    /// Minimum scroll (in rows) treated as movement; below this the frame is skipped.
    private let minShift = 2

    public init() {}

    public var frameWidth: Int { compositeFrames.first?.image.width ?? 0 }

    /// Feed the next captured frame. Returns the detected scroll offset in
    /// rows (0 when the frame was skipped as a duplicate).
    @discardableResult
    public func append(_ image: CGImage) -> Int {
        guard let signature = Self.signature(for: image, sampleColumns: sampleColumns) else { return 0 }
        defer {
            previousSignature = signature
            previousImage = image
        }
        guard let prev = previousSignature else {
            // First frame: take it whole.
            compositeFrames.append((image, 0))
            totalHeight = image.height
            return image.height
        }
        let shift = Self.bestVerticalShift(previous: prev, current: signature)
        guard shift >= minShift else { return 0 }
        // The bottom `shift` rows of the current frame are new content.
        let appendFrom = image.height - shift
        compositeFrames.append((image, appendFrom))
        totalHeight += shift
        return shift
    }

    /// Render the stitched panorama.
    public func makePanorama() -> CGImage? {
        guard let first = compositeFrames.first?.image else { return nil }
        let width = first.width
        guard totalHeight > 0,
              let ctx = CGContext(
                data: nil, width: width, height: totalHeight,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // Quartz origin is bottom-left; we accumulate top-down.
        var yTop = 0
        for (image, appendFromRow) in compositeFrames {
            let newRows = image.height - appendFromRow
            // Draw the full frame so its bottom `newRows` land in the slot;
            // clip to just the strip we are appending.
            let stripTop = yTop
            let stripRect = CGRect(
                x: 0, y: CGFloat(totalHeight - stripTop - newRows),
                width: CGFloat(width), height: CGFloat(newRows)
            )
            ctx.saveGState()
            ctx.clip(to: stripRect)
            // The strip is the bottom `newRows` of the frame, so align the
            // frame's bottom edge with the strip's bottom edge.
            let frameRect = CGRect(
                x: 0,
                y: stripRect.minY,
                width: CGFloat(width),
                height: CGFloat(image.height)
            )
            ctx.draw(image, in: frameRect)
            ctx.restoreGState()
            yTop += newRows
        }
        return ctx.makeImage()
    }

    // MARK: - Signatures

    static func signature(for image: CGImage, sampleColumns: Int) -> FrameSignature? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        let cols = min(sampleColumns, width)
        let colStep = max(1, width / cols)
        var rows: [[Float]] = []
        rows.reserveCapacity(height)
        // CGContext rows are top-to-bottom in memory for this configuration.
        for r in 0..<height {
            var row: [Float] = []
            row.reserveCapacity(cols)
            var c = 0
            while c < width {
                row.append(Float(pixels[r * width + c]))
                c += colStep
            }
            rows.append(row)
        }
        return FrameSignature(rows: rows)
    }

    /// How many rows did content move up between `previous` and `current`?
    /// (Positive shift = user scrolled down, new content at the bottom.)
    ///
    /// Two safeguards keep blank page regions from causing false locks
    /// (which duplicate content in the panorama):
    ///   - candidate shifts must keep a substantial overlap, so a tiny
    ///     accidentally-matching strip can't win over the true alignment;
    ///   - only rows with visible structure are scored, because blank rows
    ///     match at every offset and say nothing about the real scroll.
    static func bestVerticalShift(previous: FrameSignature, current: FrameSignature) -> Int {
        let height = min(previous.rows.count, current.rows.count)
        guard height > 16 else { return 0 }
        // Frames sharing less than this can't be aligned reliably; the user
        // scrolled too far between captures and we skip the frame instead of
        // guessing.
        let minOverlap = max(16, height / 5)
        let maxShift = height - minOverlap
        guard maxShift > 0 else { return 0 }

        let informative = previous.rows.map(Self.isInformative)

        var bestShift = 0
        var bestScore = Float.greatestFiniteMagnitude
        // For shift s: previous row (r + s) should match current row r.
        for s in 0...maxShift {
            let overlap = height - s
            var score: Float = 0
            var samples = 0
            var r = 0
            while r < overlap {
                defer { r += 2 }
                guard informative[r + s] else { continue }
                let a = previous.rows[r + s]
                let b = current.rows[r]
                let n = min(a.count, b.count)
                var diff: Float = 0
                for i in 0..<n { diff += abs(a[i] - b[i]) }
                score += diff / Float(max(n, 1))
                samples += 1
            }
            // Without enough structured rows in the overlap the score is
            // meaningless — ignore this candidate entirely.
            guard samples >= 6 else { continue }
            score /= Float(samples)
            // Prefer smaller shifts on ties to avoid runaway matching.
            if score < bestScore - 0.01 {
                bestScore = score
                bestShift = s
            }
        }
        // Reject poor matches (mean abs difference > 10/255): treat as no scroll.
        if bestScore > 10 { return 0 }
        return bestShift
    }

    /// A row carries alignment information only if its luminance varies
    /// across the sampled columns.
    static func isInformative(_ row: [Float]) -> Bool {
        guard let first = row.first else { return false }
        var minValue = first, maxValue = first
        for v in row {
            if v < minValue { minValue = v }
            if v > maxValue { maxValue = v }
        }
        return maxValue - minValue > 6
    }
}
