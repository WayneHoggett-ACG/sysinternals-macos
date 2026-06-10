import AppKit
import SwiftUI
import ZoomItCore

/// Observable bridge between SwiftUI and the SettingsStore.
final class SettingsViewModel: ObservableObject {
    let store: SettingsStore
    var onHotkeysChanged: (() -> Void)?

    @Published var settings: ZoomItSettings {
        didSet {
            store.replace(settings)
            if settings.hotkeys != oldValue.hotkeys {
                onHotkeysChanged?()
            }
        }
    }

    init(store: SettingsStore) {
        self.store = store
        self.settings = store.settings
    }

    func reloadFromStore() {
        settings = store.settings
    }
}

final class OptionsWindowController {
    private var window: NSWindow?
    let viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        viewModel.reloadFromStore()
        if window == nil {
            let view = OptionsView(model: viewModel)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "ZoomIt Options"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 560, height: 480))
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct OptionsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        TabView {
            zoomTab.tabItem { Text("Zoom") }
            liveZoomTab.tabItem { Text("LiveZoom") }
            drawTab.tabItem { Text("Draw") }
            typeTab.tabItem { Text("Type") }
            breakTab.tabItem { Text("Break") }
            recordTab.tabItem { Text("Record") }
            snipTab.tabItem { Text("Snip") }
            demoTypeTab.tabItem { Text("DemoType") }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }

    private func hotkeyRow(_ label: String, _ action: HotkeyAction) -> some View {
        HStack {
            Text(label)
            Spacer()
            HotkeyRecorderView(
                chord: Binding(
                    get: { model.settings.chord(for: action) },
                    set: { model.settings.setChord($0, for: action) }
                )
            )
            .frame(width: 140, height: 24)
        }
    }

    private var zoomTab: some View {
        Form {
            hotkeyRow("Zoom toggle hotkey:", .zoom)
            Picker("Initial zoom level:", selection: $model.settings.zoomLevel) {
                ForEach([1.25, 1.5, 1.75, 2.0, 3.0, 4.0], id: \.self) { level in
                    Text(String(format: "%.2fx", level)).tag(CGFloat(level))
                }
            }
            Toggle("Animate zoom in and out", isOn: $model.settings.animateZoom)
            Spacer()
        }
        .padding()
    }

    private var liveZoomTab: some View {
        Form {
            hotkeyRow("LiveZoom toggle hotkey:", .liveZoom)
            hotkeyRow("LiveDraw toggle hotkey:", .liveDraw)
            Text("LiveZoom magnifies the screen while it continues to update. LiveDraw lets you annotate over live windows.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var drawTab: some View {
        Form {
            hotkeyRow("Draw without zoom hotkey:", .draw)
            Picker("Pen color:", selection: $model.settings.penColor) {
                ForEach(PenColorChoice.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            Slider(value: $model.settings.penWidth, in: 1...40, step: 1) {
                Text("Pen width: \(Int(model.settings.penWidth))")
            }
            Text("While drawing: R/G/B/Y/O/P set colors (Shift for highlighter), X is the blur pen, W/K toggle whiteboard/blackboard, hold Shift/Ctrl/Tab/Ctrl+Shift for line/rectangle/ellipse/arrow.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var typeTab: some View {
        Form {
            HStack {
                Text("Font:")
                Spacer()
                Button("\(model.settings.fontName), \(Int(model.settings.fontSize)) pt") {
                    showFontPanel()
                }
            }
            Slider(value: $model.settings.fontSize, in: 8...160, step: 1) {
                Text("Font size: \(Int(model.settings.fontSize))")
            }
            Text("Press T while drawing to type (Shift+T for right-aligned text). Ctrl+scroll or arrow keys change the size while typing.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private func showFontPanel() {
        let panel = NSFontPanel.shared
        let current = NSFont(name: model.settings.fontName, size: model.settings.fontSize)
            ?? NSFont.boldSystemFont(ofSize: model.settings.fontSize)
        NSFontManager.shared.setSelectedFont(current, isMultiple: false)
        NSFontManager.shared.target = FontPanelTarget.shared
        FontPanelTarget.shared.onChange = { font in
            model.settings.fontName = font.fontName
            model.settings.fontSize = font.pointSize
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private var breakTab: some View {
        Form {
            hotkeyRow("Break timer hotkey:", .breakTimer)
            Stepper("Timer: \(model.settings.timerMinutes) minutes", value: $model.settings.timerMinutes, in: 1...120)
            Toggle("Show time elapsed after expiration", isOn: $model.settings.showTimeElapsed)
            Toggle("Play sound on expiration", isOn: $model.settings.playSoundOnExpiration)
            Slider(value: $model.settings.timerOpacity, in: 0.2...1) {
                Text("Opacity: \(Int(model.settings.timerOpacity * 100))%")
            }
            Picker("Timer position:", selection: $model.settings.timerPosition) {
                ForEach(TimerPosition.allCases, id: \.self) { pos in
                    Text(pos.title).tag(pos)
                }
            }
            HStack {
                TextField("Background image (optional):", text: $model.settings.timerBackgroundImagePath)
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK, let url = panel.url {
                        model.settings.timerBackgroundImagePath = url.path
                    }
                }
            }
            Spacer()
        }
        .padding()
    }

    private var recordTab: some View {
        Form {
            hotkeyRow("Record toggle hotkey:", .record)
            hotkeyRow("Record region hotkey:", .recordCrop)
            hotkeyRow("Record window hotkey:", .recordWindow)
            Picker("Format:", selection: $model.settings.recordingFormat) {
                Text("MP4 (H.264)").tag(RecordingFormat.mp4)
                Text("Animated GIF").tag(RecordingFormat.gif)
            }
            Picker("Frame rate:", selection: $model.settings.recordingFrameRate) {
                ForEach([15, 24, 30, 60], id: \.self) { fps in
                    Text("\(fps) fps").tag(fps)
                }
            }
            Picker("Scaling:", selection: $model.settings.recordingScale) {
                Text("100%").tag(CGFloat(1.0))
                Text("75%").tag(CGFloat(0.75))
                Text("50%").tag(CGFloat(0.5))
            }
            Toggle("Capture microphone audio", isOn: $model.settings.captureMicrophone)
            Spacer()
        }
        .padding()
    }

    private var snipTab: some View {
        Form {
            hotkeyRow("Snip to clipboard hotkey:", .snipCopy)
            hotkeyRow("Snip to file hotkey:", .snipSave)
            hotkeyRow("Copy text (OCR) hotkey:", .snipOCR)
            HStack {
                TextField("Save folder:", text: $model.settings.saveFolderPath, prompt: Text("~/Desktop"))
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url {
                        model.settings.saveFolderPath = url.path
                    }
                }
            }
            Spacer()
        }
        .padding()
    }

    private var demoTypeTab: some View {
        Form {
            hotkeyRow("DemoType hotkey:", .demoType)
            hotkeyRow("Previous snippet hotkey:", .demoTypePrevious)
            HStack {
                TextField("Script file:", text: $model.settings.demoTypeFilePath, prompt: Text("Choose a text file"))
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.plainText, .text]
                    if panel.runModal() == .OK, let url = panel.url {
                        model.settings.demoTypeFilePath = url.path
                    }
                }
            }
            Toggle("User-driven mode (Space advances to the next snippet)", isOn: $model.settings.demoTypeUserDriven)
            Slider(value: Binding(
                get: { Double(model.settings.demoTypeSpeed) },
                set: { model.settings.demoTypeSpeed = Int($0) }
            ), in: 1...100, step: 1) {
                Text("Typing speed: \(model.settings.demoTypeSpeed)")
            }
            Text("Snippets are separated by lines containing [end]. Use [pause:N] to pause N tenths of a second while typing.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

/// Target object for NSFontManager changes from the shared font panel.
final class FontPanelTarget: NSObject {
    static let shared = FontPanelTarget()
    var onChange: ((NSFont) -> Void)?

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let manager = sender else { return }
        let newFont = manager.convert(NSFont.boldSystemFont(ofSize: 36))
        onChange?(newFont)
    }
}

/// Click, then press a key combination to assign a hotkey.
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var chord: KeyChord

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.chord = chord
        view.onChange = { chord = $0 }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.chord = chord
        nsView.needsDisplay = true
    }

    final class RecorderNSView: NSView {
        var chord: KeyChord?
        var onChange: ((KeyChord) -> Void)?
        private var recording = false

        override var acceptsFirstResponder: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            let bg: NSColor = recording ? .selectedContentBackgroundColor : .controlBackgroundColor
            bg.setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            let text = recording ? "Press keys…" : (chord?.displayString ?? "Click to set")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: recording ? NSColor.white : NSColor.labelColor,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }

        override func mouseDown(with event: NSEvent) {
            recording = true
            window?.makeFirstResponder(self)
            needsDisplay = true
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            needsDisplay = true
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            guard recording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 { // Esc cancels
                recording = false
                needsDisplay = true
                return
            }
            var carbon: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.control) { carbon |= KeyChord.controlKey }
            if flags.contains(.shift) { carbon |= KeyChord.shiftKey }
            if flags.contains(.option) { carbon |= KeyChord.optionKey }
            if flags.contains(.command) { carbon |= KeyChord.cmdKey }
            guard carbon != 0 else { return } // require at least one modifier
            let newChord = KeyChord(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
            chord = newChord
            onChange?(newChord)
            recording = false
            needsDisplay = true
        }
    }
}
