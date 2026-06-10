import XCTest
@testable import ZoomItCore

final class SettingsTests: XCTestCase {
    func testDefaultHotkeysMatchZoomIt() {
        let s = ZoomItSettings()
        // Ctrl+1 zoom, Ctrl+2 draw, Ctrl+3 break, Ctrl+4 livezoom, Ctrl+5 record,
        // Ctrl+6 snip, Ctrl+7 demotype, Ctrl+8 panorama.
        XCTAssertEqual(s.chord(for: .zoom), KeyChord(keyCode: 18, carbonModifiers: KeyChord.controlKey))
        XCTAssertEqual(s.chord(for: .draw), KeyChord(keyCode: 19, carbonModifiers: KeyChord.controlKey))
        XCTAssertEqual(s.chord(for: .liveDraw), KeyChord(keyCode: 21, carbonModifiers: KeyChord.controlKey | KeyChord.shiftKey))
        XCTAssertEqual(s.chord(for: .recordWindow), KeyChord(keyCode: 23, carbonModifiers: KeyChord.controlKey | KeyChord.optionKey))
        XCTAssertEqual(s.chord(for: .panorama), KeyChord(keyCode: 28, carbonModifiers: KeyChord.controlKey))
    }

    func testChordDisplayString() {
        let chord = KeyChord(keyCode: 21, carbonModifiers: KeyChord.controlKey | KeyChord.shiftKey)
        XCTAssertEqual(chord.displayString, "⌃⇧4")
    }

    func testSettingsRoundTripThroughStore() {
        let suiteName = "ZoomItTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.update { s in
            s.penColor = .green
            s.penWidth = 9
            s.timerMinutes = 25
            s.recordingFormat = .gif
            s.setChord(KeyChord(keyCode: 1, carbonModifiers: KeyChord.cmdKey), for: .zoom)
        }

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.penColor, .green)
        XCTAssertEqual(reloaded.settings.penWidth, 9)
        XCTAssertEqual(reloaded.settings.timerMinutes, 25)
        XCTAssertEqual(reloaded.settings.recordingFormat, .gif)
        XCTAssertEqual(reloaded.settings.chord(for: .zoom), KeyChord(keyCode: 1, carbonModifiers: KeyChord.cmdKey))
        // Untouched actions keep defaults.
        XCTAssertEqual(reloaded.settings.chord(for: .draw), HotkeyAction.draw.defaultChord)
    }

    func testDemoTypeSpeedMapsToDelay() {
        var s = ZoomItSettings()
        s.demoTypeSpeed = 100
        let fast = s.demoTypeCharacterDelay
        s.demoTypeSpeed = 1
        let slow = s.demoTypeCharacterDelay
        XCTAssertLessThan(fast, slow)
        XCTAssertEqual(fast, 0.005, accuracy: 0.001)
    }

    func testAllActionsHaveDistinctDefaultChords() {
        var seen = Set<KeyChord>()
        for action in HotkeyAction.allCases {
            let chord = action.defaultChord
            XCTAssertFalse(seen.contains(chord), "duplicate default hotkey for \(action)")
            seen.insert(chord)
        }
    }
}
