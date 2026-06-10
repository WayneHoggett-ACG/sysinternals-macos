import AppKit
import Vision
import ZoomItCore

/// Snip (Ctrl+6 / Ctrl+Shift+6 / Ctrl+Alt+6): grab a region of the screen and
/// copy it, save it, or OCR its text to the clipboard.
final class SnipController {
    enum Action {
        case copy, save, ocr
    }

    let settingsStore: SettingsStore
    private var selector: RegionSelector?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func begin(_ action: Action) {
        guard Permissions.ensureScreenCapture() else { return }
        let screen = ScreenSnapshotter.screenUnderMouse()
        let selector = RegionSelector()
        self.selector = selector
        selector.begin(on: screen) { [weak self] rect in
            guard let self else { return }
            self.selector = nil
            guard let rect else { return }
            Task { @MainActor in
                do {
                    let image = try await ScreenSnapshotter.capture(rect: rect, on: screen)
                    self.handle(image: image, action: action)
                } catch {
                    NSLog("ZoomIt: snip capture failed: \(error)")
                }
            }
        }
    }

    @MainActor
    private func handle(image: CGImage, action: Action) {
        switch action {
        case .copy:
            image.copyToPasteboard()
        case .save:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.directoryURL = settingsStore.settings.saveFolderURL
            panel.nameFieldStringValue = SaveNamer.timestampedURL(
                in: settingsStore.settings.saveFolderURL, prefix: "ZoomIt Snip", ext: "png"
            ).lastPathComponent
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    image.savePNG(to: url)
                }
            }
        case .ocr:
            recognizeText(in: image) { text in
                guard let text, !text.isEmpty else {
                    NSSound.beep()
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
        }
    }

    private func recognizeText(in image: CGImage, completion: @escaping @Sendable (String?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Preserve reading order top-to-bottom, joining lines with newlines.
            let lines = observations
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
