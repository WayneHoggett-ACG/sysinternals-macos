import Foundation

/// A keyboard shortcut: a virtual key code plus Carbon-style modifier flags.
/// Stored in settings and registered as a global hotkey by the app layer.
public struct KeyChord: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    // Carbon modifier masks (from Carbon's Events.h; redeclared so core stays
    // free of Carbon imports and unit-testable on any toolchain).
    public static let cmdKey: UInt32 = 0x0100
    public static let shiftKey: UInt32 = 0x0200
    public static let optionKey: UInt32 = 0x0800
    public static let controlKey: UInt32 = 0x1000

    public var hasControl: Bool { carbonModifiers & Self.controlKey != 0 }
    public var hasShift: Bool { carbonModifiers & Self.shiftKey != 0 }
    public var hasOption: Bool { carbonModifiers & Self.optionKey != 0 }
    public var hasCommand: Bool { carbonModifiers & Self.cmdKey != 0 }

    /// Human readable description, e.g. "⌃⇧4".
    public var displayString: String {
        var s = ""
        if hasControl { s += "⌃" }
        if hasOption { s += "⌥" }
        if hasShift { s += "⇧" }
        if hasCommand { s += "⌘" }
        s += Self.keyName(forKeyCode: keyCode)
        return s
    }

    public static func keyName(forKeyCode code: UInt32) -> String {
        if let name = keyNames[code] { return name }
        return "key\(code)"
    }

    // ANSI virtual key codes for keys we use by default.
    public static let keyNames: [UInt32: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        49: "Space", 53: "Esc", 36: "Return", 48: "Tab",
    ]
}

/// Every hotkey-triggered action in ZoomIt.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case zoom               // Ctrl+1
    case draw               // Ctrl+2
    case breakTimer         // Ctrl+3
    case liveZoom           // Ctrl+4
    case liveDraw           // Ctrl+Shift+4
    case record             // Ctrl+5
    case recordCrop         // Ctrl+Shift+5
    case recordWindow       // Ctrl+Alt+5
    case snipCopy           // Ctrl+6
    case snipSave           // Ctrl+Shift+6
    case snipOCR            // Ctrl+Alt+6
    case demoType           // Ctrl+7
    case demoTypePrevious   // Ctrl+Shift+7
    case panorama           // Ctrl+8

    /// Default chords matching ZoomIt for Windows.
    public var defaultChord: KeyChord {
        let ctrl = KeyChord.controlKey
        let shift = KeyChord.shiftKey
        let opt = KeyChord.optionKey
        switch self {
        case .zoom: return KeyChord(keyCode: 18, carbonModifiers: ctrl)              // Ctrl+1
        case .draw: return KeyChord(keyCode: 19, carbonModifiers: ctrl)              // Ctrl+2
        case .breakTimer: return KeyChord(keyCode: 20, carbonModifiers: ctrl)        // Ctrl+3
        case .liveZoom: return KeyChord(keyCode: 21, carbonModifiers: ctrl)          // Ctrl+4
        case .liveDraw: return KeyChord(keyCode: 21, carbonModifiers: ctrl | shift)  // Ctrl+Shift+4
        case .record: return KeyChord(keyCode: 23, carbonModifiers: ctrl)            // Ctrl+5
        case .recordCrop: return KeyChord(keyCode: 23, carbonModifiers: ctrl | shift)
        case .recordWindow: return KeyChord(keyCode: 23, carbonModifiers: ctrl | opt)
        case .snipCopy: return KeyChord(keyCode: 22, carbonModifiers: ctrl)          // Ctrl+6
        case .snipSave: return KeyChord(keyCode: 22, carbonModifiers: ctrl | shift)
        case .snipOCR: return KeyChord(keyCode: 22, carbonModifiers: ctrl | opt)
        case .demoType: return KeyChord(keyCode: 26, carbonModifiers: ctrl)          // Ctrl+7
        case .demoTypePrevious: return KeyChord(keyCode: 26, carbonModifiers: ctrl | shift)
        case .panorama: return KeyChord(keyCode: 28, carbonModifiers: ctrl)          // Ctrl+8
        }
    }

    public var title: String {
        switch self {
        case .zoom: return "Zoom"
        case .draw: return "Draw"
        case .breakTimer: return "Break Timer"
        case .liveZoom: return "LiveZoom"
        case .liveDraw: return "LiveDraw"
        case .record: return "Record"
        case .recordCrop: return "Record Region"
        case .recordWindow: return "Record Window"
        case .snipCopy: return "Snip to Clipboard"
        case .snipSave: return "Snip to File"
        case .snipOCR: return "Copy Text (OCR)"
        case .demoType: return "DemoType"
        case .demoTypePrevious: return "DemoType Previous"
        case .panorama: return "Panorama"
        }
    }
}
