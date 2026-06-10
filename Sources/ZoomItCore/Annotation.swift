import CoreGraphics
import Foundation

/// RGBA color independent of AppKit so the model is unit-testable.
public struct PenColor: Codable, Equatable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public func withAlpha(_ a: CGFloat) -> PenColor {
        PenColor(red: red, green: green, blue: blue, alpha: a)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    // ZoomIt's palette.
    public static let red = PenColor(red: 1, green: 0, blue: 0)
    public static let green = PenColor(red: 0, green: 0.78, blue: 0)
    public static let blue = PenColor(red: 0, green: 0.4, blue: 1)
    public static let yellow = PenColor(red: 1, green: 0.9, blue: 0)
    public static let orange = PenColor(red: 1, green: 0.55, blue: 0)
    public static let pink = PenColor(red: 1, green: 0.35, blue: 0.7)
    public static let white = PenColor(red: 1, green: 1, blue: 1)
    public static let black = PenColor(red: 0, green: 0, blue: 0)
}

public enum PenStyle: String, Codable, Sendable {
    case solid
    /// Translucent wide marker (Shift+color key in ZoomIt).
    case highlight
    /// Blur pen (X in ZoomIt): blurs the screenshot underneath the stroke.
    case blur
}

public enum ShapeKind: String, Codable, Sendable {
    case line, rectangle, ellipse, arrow
}

/// Freehand stroke.
public struct StrokeAnnotation: Codable, Equatable, Sendable {
    public var points: [CGPoint]
    public var color: PenColor
    public var width: CGFloat
    public var style: PenStyle

    public init(points: [CGPoint], color: PenColor, width: CGFloat, style: PenStyle = .solid) {
        self.points = points
        self.color = color
        self.width = width
        self.style = style
    }
}

/// Shape drawn with a modifier held (Shift=line, Ctrl=rect, Tab=ellipse, Ctrl+Shift=arrow).
public struct ShapeAnnotation: Codable, Equatable, Sendable {
    public var kind: ShapeKind
    public var start: CGPoint
    public var end: CGPoint
    public var color: PenColor
    public var width: CGFloat
    public var style: PenStyle

    public init(kind: ShapeKind, start: CGPoint, end: CGPoint, color: PenColor, width: CGFloat, style: PenStyle = .solid) {
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.width = width
        self.style = style
    }

    public var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

/// Text typed in type mode (T / Shift+T).
public struct TextAnnotation: Codable, Equatable, Sendable {
    public var origin: CGPoint           // baseline-left (or baseline-right when rightAligned)
    public var text: String
    public var color: PenColor
    public var fontSize: CGFloat
    public var fontName: String
    public var rightAligned: Bool

    public init(origin: CGPoint, text: String, color: PenColor, fontSize: CGFloat,
                fontName: String = "Helvetica-Bold", rightAligned: Bool = false) {
        self.origin = origin
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.fontName = fontName
        self.rightAligned = rightAligned
    }
}

public enum Annotation: Equatable, Sendable {
    case stroke(StrokeAnnotation)
    case shape(ShapeAnnotation)
    case text(TextAnnotation)
}

/// Board background for draw mode.
public enum BoardBackground: String, Codable, Sendable {
    case screen      // annotate over the captured screen
    case whiteboard  // W
    case blackboard  // K
}

/// The annotation document for one draw-mode session, with undo support.
public final class DrawingModel {
    public private(set) var annotations: [Annotation] = []
    public var background: BoardBackground = .screen

    public init() {}

    public func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    /// Ctrl+Z: erase last drawing.
    @discardableResult
    public func undo() -> Bool {
        guard !annotations.isEmpty else { return false }
        annotations.removeLast()
        return true
    }

    /// E: erase all drawings.
    public func clear() {
        annotations.removeAll()
    }

    public var isEmpty: Bool { annotations.isEmpty }

    /// Toggle whiteboard/blackboard the way ZoomIt does: pressing the same
    /// board key again returns to the screen.
    public func toggleBoard(_ board: BoardBackground) {
        background = (background == board) ? .screen : board
    }
}
