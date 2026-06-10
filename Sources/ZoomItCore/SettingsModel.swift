import CoreGraphics
import Foundation

public enum RecordingFormat: String, Codable, CaseIterable, Sendable {
    case mp4, gif
}

public enum TimerPosition: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    public var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .centerLeft: return "Center Left"
        case .center: return "Center"
        case .centerRight: return "Center Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// All persisted options. A plain Codable struct so it round-trips through
/// UserDefaults as JSON and is testable without AppKit.
public struct ZoomItSettings: Codable, Equatable, Sendable {
    // Zoom
    public var zoomLevel: CGFloat = 2.0          // initial zoom factor
    public var animateZoom: Bool = true

    // Draw / Type
    public var penWidth: CGFloat = 5.0
    public var penColor: PenColorChoice = .red
    public var fontSize: CGFloat = 36.0
    public var fontName: String = "Helvetica-Bold"

    // Break timer
    public var timerMinutes: Int = 10
    public var timerOpacity: CGFloat = 1.0
    public var timerPosition: TimerPosition = .center
    public var showTimeElapsed: Bool = true       // show elapsed time after expiration
    public var playSoundOnExpiration: Bool = false
    public var timerBackgroundImagePath: String = ""

    // Recording
    public var recordingFrameRate: Int = 30
    public var recordingScale: CGFloat = 1.0      // 1.0 = native resolution
    public var recordingFormat: RecordingFormat = .mp4
    public var captureMicrophone: Bool = false
    public var saveFolderPath: String = ""        // empty = ~/Desktop

    // DemoType
    public var demoTypeFilePath: String = ""
    public var demoTypeUserDriven: Bool = false
    public var demoTypeSpeed: Int = 50            // 1...100, higher is faster

    // Hotkeys
    public var hotkeys: [String: KeyChord] = [:]  // HotkeyAction.rawValue -> chord

    public init() {}

    public func chord(for action: HotkeyAction) -> KeyChord {
        hotkeys[action.rawValue] ?? action.defaultChord
    }

    public mutating func setChord(_ chord: KeyChord, for action: HotkeyAction) {
        hotkeys[action.rawValue] = chord
    }

    /// Delay between typed characters for the current DemoType speed.
    public var demoTypeCharacterDelay: TimeInterval {
        let speed = max(1, min(100, demoTypeSpeed))
        // speed 100 -> 5 ms/char, speed 1 -> ~200 ms/char
        return 0.005 + (1.0 - Double(speed) / 100.0) * 0.2
    }

    public var saveFolderURL: URL {
        if !saveFolderPath.isEmpty {
            return URL(fileURLWithPath: (saveFolderPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}

/// Named pen colors mapped to ZoomIt's keyboard palette.
public enum PenColorChoice: String, Codable, CaseIterable, Sendable {
    case red, green, blue, yellow, orange, pink

    public var color: PenColor {
        switch self {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .yellow: return .yellow
        case .orange: return .orange
        case .pink: return .pink
        }
    }

    public var title: String { rawValue.capitalized }
}

/// UserDefaults-backed store.
public final class SettingsStore {
    public static let defaultsKey = "ZoomItSettings"
    private let defaults: UserDefaults

    public private(set) var settings: ZoomItSettings

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(ZoomItSettings.self, from: data) {
            settings = decoded
        } else {
            settings = ZoomItSettings()
        }
    }

    public func update(_ mutate: (inout ZoomItSettings) -> Void) {
        mutate(&settings)
        save()
    }

    public func replace(_ newSettings: ZoomItSettings) {
        settings = newSettings
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
