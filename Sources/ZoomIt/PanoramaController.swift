import AppKit
import ScreenCaptureKit
import ZoomItCore

/// Panorama (Ctrl+8): select a region, scroll through content while ZoomIt
/// captures frames, press Ctrl+8 again to stop. The frames are stitched into
/// one tall scrolling screenshot that is copied to the clipboard and offered
/// for saving.
final class PanoramaController: NSObject, SCStreamOutput, SCStreamDelegate {
    let settingsStore: SettingsStore
    var onStateChange: ((Bool) -> Void)?

    private var stream: SCStream?
    private var stitcher: PanoramaStitcher?
    private let sampleQueue = DispatchQueue(label: "zoomit.panorama.samples")
    private let ciContext = CIContext()
    private var selector: RegionSelector?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var isCapturing: Bool { stream != nil }

    func toggle() {
        if isCapturing {
            stop()
            return
        }
        guard Permissions.ensureScreenCapture() else { return }
        let screen = ScreenSnapshotter.screenUnderMouse()
        let selector = RegionSelector()
        self.selector = selector
        selector.begin(on: screen) { [weak self] rect in
            self?.selector = nil
            guard let rect else { return }
            self?.start(rect: rect, screen: screen)
        }
    }

    private func start(rect: NSRect, screen: NSScreen) {
        Task { @MainActor in
            do {
                let displayID = ScreenSnapshotter.displayID(for: screen)
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let ourWindows = content.windows.filter {
                    $0.owningApplication?.processID == pid_t(ProcessInfo.processInfo.processIdentifier)
                }
                let filter = SCContentFilter(display: display, excludingWindows: ourWindows)
                let config = SCStreamConfiguration()
                let scale = screen.backingScaleFactor
                config.sourceRect = CGRect(
                    x: rect.minX - screen.frame.minX,
                    y: screen.frame.maxY - rect.maxY,
                    width: rect.width,
                    height: rect.height
                )
                config.width = Int(rect.width * scale)
                config.height = Int(rect.height * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 8)
                config.showsCursor = false
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.sampleQueue)
                try await stream.startCapture()
                self.stitcher = PanoramaStitcher()
                self.stream = stream
                self.onStateChange?(true)
            } catch {
                NSLog("ZoomIt: panorama capture failed to start: \(error)")
                NSSound.beep()
            }
        }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        onStateChange?(false)
        Task { @MainActor in
            try? await stream.stopCapture()
            // Drain any in-flight samples before stitching.
            self.sampleQueue.async {
                let panorama = self.stitcher?.makePanorama()
                self.stitcher = nil
                DispatchQueue.main.async {
                    guard let panorama else {
                        NSSound.beep()
                        return
                    }
                    panorama.copyToPasteboard()
                    self.promptSave(panorama)
                }
            }
        }
    }

    @MainActor
    private func promptSave(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = settingsStore.settings.saveFolderURL
        panel.nameFieldStringValue = SaveNamer.timestampedURL(
            in: settingsStore.settings.saveFolderURL, prefix: "ZoomIt Panorama", ext: "png"
        ).lastPathComponent
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            if response == .OK, let url = panel.url {
                image.savePNG(to: url)
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        stitcher?.append(cgImage)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            if self?.isCapturing == true {
                self?.stop()
            }
        }
    }
}
