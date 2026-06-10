import CoreGraphics
import Foundation

/// Pure geometry for ZoomIt's static zoom mode: which part of the captured
/// screen is visible at a given zoom level, centered on the cursor.
public enum ZoomMath {
    public static let minZoom: CGFloat = 1.0
    public static let maxZoom: CGFloat = 32.0

    /// The source rectangle (in snapshot coordinates) shown when zoomed by
    /// `zoom` and focused on `focus` (also snapshot coordinates). The rect is
    /// centered on the focus point and clamped so it never leaves the image.
    public static func sourceRect(zoom: CGFloat, focus: CGPoint, imageSize: CGSize) -> CGRect {
        let z = clampZoom(zoom)
        let w = imageSize.width / z
        let h = imageSize.height / z
        var x = focus.x - w / 2
        var y = focus.y - h / 2
        x = min(max(x, 0), imageSize.width - w)
        y = min(max(y, 0), imageSize.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    public static func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, minZoom), maxZoom)
    }

    /// Next zoom level for one scroll/arrow step. ZoomIt zooms geometrically.
    public static func steppedZoom(_ zoom: CGFloat, direction: Int, step: CGFloat = 1.18920712) -> CGFloat {
        // Default step is 2^(1/4): four steps per doubling.
        let factor = direction >= 0 ? step : 1 / step
        return clampZoom(zoom * factor)
    }

    /// Convert a point in view/screen coordinates to snapshot coordinates,
    /// given the currently displayed source rect.
    public static func imagePoint(forViewPoint p: CGPoint, viewSize: CGSize, sourceRect: CGRect) -> CGPoint {
        CGPoint(
            x: sourceRect.origin.x + p.x / viewSize.width * sourceRect.width,
            y: sourceRect.origin.y + p.y / viewSize.height * sourceRect.height
        )
    }

    /// Exponential interpolation between zoom levels for the zoom-in animation.
    /// `t` in 0...1. Geometric interpolation keeps the animation perceptually linear.
    public static func interpolatedZoom(from: CGFloat, to: CGFloat, t: CGFloat) -> CGFloat {
        let tt = min(max(t, 0), 1)
        guard from > 0, to > 0 else { return to }
        let lf = log(from), lt = log(to)
        return exp(lf + (lt - lf) * tt)
    }
}
