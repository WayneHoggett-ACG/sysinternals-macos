import Carbon.HIToolbox
import Foundation
import ZoomItCore

/// Registers global hotkeys with Carbon's RegisterEventHotKey, which works
/// without accessibility permission.
final class HotkeyManager {
    typealias Handler = (HotkeyAction) -> Void

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: HotkeyAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let handler: Handler
    private var nextID: UInt32 = 1

    init(handler: @escaping Handler) {
        self.handler = handler
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }

    var registeredCount: Int { hotKeyRefs.count }

    /// (Re-)register every action with the chords from settings.
    func registerAll(settings: ZoomItSettings) {
        unregisterAll()
        for action in HotkeyAction.allCases {
            register(action: action, chord: settings.chord(for: action))
        }
    }

    private func register(action: HotkeyAction, chord: KeyChord) {
        let id = nextID
        nextID += 1
        actionsByID[id] = action
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5A4D_4954) /* 'ZMIT' */, id: id)
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        } else {
            NSLog("ZoomIt: failed to register hotkey for \(action.title) (status \(status))")
        }
    }

    private func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionsByID.removeAll()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let action = manager.actionsByID[hotKeyID.id] {
                    DispatchQueue.main.async {
                        manager.handler(action)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }
}
