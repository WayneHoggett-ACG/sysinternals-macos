import AppKit
import ZoomItCore

/// DemoType (Ctrl+7): types the next snippet from a script file into the
/// frontmost application by synthesizing keyboard events. In user-driven mode
/// a Space press advances to the next snippet; Esc ends the session.
/// Ctrl+Shift+7 moves back one snippet.
final class DemoTypeController {
    let settingsStore: SettingsStore

    private var cursor: DemoTypeCursor?
    private var loadedPath: String?
    private var loadedModificationDate: Date?
    private var isTyping = false
    private var cancelTyping = false

    // User-driven session
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?
    private(set) var sessionActive = false

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    // MARK: - Entry points

    func trigger() {
        guard Permissions.ensureAccessibility() else { return }
        guard ensureScriptLoaded() else { return }
        if settingsStore.settings.demoTypeUserDriven {
            if sessionActive {
                endSession()
            } else {
                startSession()
                typeNextSnippet()
            }
        } else {
            typeNextSnippet()
        }
    }

    func moveBack() {
        cursor?.moveBack()
    }

    // MARK: - Script loading

    private func ensureScriptLoaded() -> Bool {
        var path = settingsStore.settings.demoTypeFilePath
        if path.isEmpty {
            guard let chosen = promptForScript() else { return false }
            path = chosen
            settingsStore.update { $0.demoTypeFilePath = chosen }
        }
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let modDate = (try? FileManager.default.attributesOfItem(atPath: expanded)[.modificationDate]) as? Date
        if cursor == nil || loadedPath != expanded || modDate != loadedModificationDate {
            guard let script = try? DemoTypeScript.load(from: url), !script.snippets.isEmpty else {
                NSSound.beep()
                NSLog("ZoomIt: DemoType could not load script at \(expanded)")
                return false
            }
            cursor = DemoTypeCursor(script: script)
            loadedPath = expanded
            loadedModificationDate = modDate
        }
        return true
    }

    private func promptForScript() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose DemoType Script"
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    // MARK: - Typing

    private func typeNextSnippet() {
        guard !isTyping, let cursor else { return }
        guard let snippet = cursor.nextSnippet() else {
            // Script exhausted: rewind for the next run, end any session.
            cursor.reset()
            if sessionActive { endSession() }
            NSSound.beep()
            return
        }
        isTyping = true
        cancelTyping = false
        let delay = settingsStore.settings.demoTypeCharacterDelay
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            for element in snippet.elements {
                if self.cancelTyping { break }
                switch element {
                case .pause(let seconds):
                    Thread.sleep(forTimeInterval: seconds)
                case .typeText(let text):
                    for ch in text {
                        if self.cancelTyping { break }
                        Self.type(character: ch)
                        Thread.sleep(forTimeInterval: delay)
                    }
                }
            }
            DispatchQueue.main.async {
                self.isTyping = false
            }
        }
    }

    private static func type(character: Character) {
        let source = CGEventSource(stateID: .combinedSessionState)
        if character == "\n" {
            // Real Return key press so editors apply auto-indent etc.
            let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            return
        }
        let utf16 = Array(String(character).utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - User-driven session (event tap)

    private func startSession() {
        guard eventTap == nil else {
            sessionActive = true
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData -> Unmanaged<CGEvent>? in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<DemoTypeController>.fromOpaque(userData).takeUnretainedValue()
                return controller.handleTap(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("ZoomIt: failed to create DemoType event tap")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        sessionActive = true
    }

    private func endSession() {
        sessionActive = false
        cancelTyping = true
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = tapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        tapRunLoopSource = nil
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard sessionActive, type == .keyDown else { return Unmanaged.passUnretained(event) }
        // Ignore our own synthesized events (they have no keyboard type info
        // but do carry the unicode payload; synthesized events come from our
        // CGEventSource, so check the source state ID via user data field).
        if isTyping { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 49: // Space: advance
            DispatchQueue.main.async { [weak self] in
                self?.typeNextSnippet()
            }
            return nil // swallow
        case 53: // Esc: end session
            DispatchQueue.main.async { [weak self] in
                self?.endSession()
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
