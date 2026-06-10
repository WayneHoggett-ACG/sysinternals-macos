import AppKit
import AVFoundation
import ScreenCaptureKit
import ZoomItCore

/// Screen recording (Ctrl+5 full screen, Ctrl+Shift+5 region, Ctrl+Alt+5
/// window under cursor). Records H.264 MP4 via ScreenCaptureKit; can export
/// as animated GIF on save. The record hotkey toggles stop.
final class RecordController: NSObject, SCStreamOutput, SCStreamDelegate {
    enum Target {
        case fullScreen
        case region(NSRect)      // global Cocoa coordinates
        case window(SCWindow)
    }

    let settingsStore: SettingsStore
    var onStateChange: ((Bool) -> Void)?

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var tempURL: URL?
    private let sampleQueue = DispatchQueue(label: "zoomit.record.samples")
    private var selector: RegionSelector?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var isRecording: Bool { stream != nil }

    // MARK: - Entry points

    func toggleFullScreen() {
        if isRecording { stop(); return }
        guard Permissions.ensureScreenCapture() else { return }
        start(target: .fullScreen)
    }

    func toggleRegion() {
        if isRecording { stop(); return }
        guard Permissions.ensureScreenCapture() else { return }
        let screen = ScreenSnapshotter.screenUnderMouse()
        let selector = RegionSelector()
        self.selector = selector
        selector.begin(on: screen) { [weak self] rect in
            self?.selector = nil
            guard let rect else { return }
            self?.start(target: .region(rect))
        }
    }

    func toggleWindow() {
        if isRecording { stop(); return }
        guard Permissions.ensureScreenCapture() else { return }
        Task { @MainActor in
            guard let window = await Self.windowUnderCursor() else {
                NSSound.beep()
                return
            }
            self.start(target: .window(window))
        }
    }

    /// Front-most shareable window containing the cursor.
    static func windowUnderCursor() async -> SCWindow? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
            return nil
        }
        guard let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let mouse = CGEvent(source: nil)?.location ?? .zero
        let ourPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        // CGWindowList is ordered front to back.
        for info in cgList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ourPID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let frame = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
            )
            guard frame.contains(mouse),
                  let windowID = info[kCGWindowNumber as String] as? UInt32 else { continue }
            if let match = content.windows.first(where: { $0.windowID == windowID }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Recording

    private func start(target: Target) {
        Task { @MainActor in
            do {
                try await self.startStream(target: target)
                self.onStateChange?(true)
            } catch {
                NSLog("ZoomIt: failed to start recording: \(error)")
                NSSound.beep()
            }
        }
    }

    @MainActor
    private func startStream(target: Target) async throws {
        let screen = ScreenSnapshotter.screenUnderMouse()
        let scale = screen.backingScaleFactor
        let displayID = ScreenSnapshotter.displayID(for: screen)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenSnapshotter.SnapshotError.noDisplay
        }

        let config = SCStreamConfiguration()
        let settings = settingsStore.settings
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, settings.recordingFrameRate)))
        config.showsCursor = true
        config.queueDepth = 6

        let filter: SCContentFilter
        var outputSize: CGSize

        switch target {
        case .fullScreen:
            let ourWindows = content.windows.filter {
                $0.owningApplication?.processID == pid_t(ProcessInfo.processInfo.processIdentifier)
            }
            filter = SCContentFilter(display: display, excludingWindows: ourWindows)
            outputSize = CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale)
        case .region(let rect):
            let ourWindows = content.windows.filter {
                $0.owningApplication?.processID == pid_t(ProcessInfo.processInfo.processIdentifier)
            }
            filter = SCContentFilter(display: display, excludingWindows: ourWindows)
            // sourceRect is in display points with a top-left origin.
            let local = CGRect(
                x: rect.minX - screen.frame.minX,
                y: screen.frame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            config.sourceRect = local
            outputSize = CGSize(width: rect.width * scale, height: rect.height * scale)
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            outputSize = CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
        }

        let recordScale = min(max(settings.recordingScale, 0.25), 1.0)
        // H.264 wants even dimensions.
        outputSize.width = (outputSize.width * recordScale).rounded(.down)
        outputSize.height = (outputSize.height * recordScale).rounded(.down)
        if outputSize.width.truncatingRemainder(dividingBy: 2) != 0 { outputSize.width -= 1 }
        if outputSize.height.truncatingRemainder(dividingBy: 2) != 0 { outputSize.height -= 1 }
        config.width = Int(outputSize.width)
        config.height = Int(outputSize.height)

        let wantsMic = settings.captureMicrophone
        if #available(macOS 15.0, *), wantsMic {
            config.captureMicrophone = true
        }

        // Writer
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZoomIt-recording-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if #available(macOS 15.0, *), wantsMic {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else {
            throw writer.error ?? ScreenSnapshotter.SnapshotError.captureFailed
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if #available(macOS 15.0, *), wantsMic {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
        }
        try await stream.startCapture()

        self.tempURL = tempURL
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.sessionStarted = false
        self.stream = stream
    }

    func stop() {
        guard let stream, let writer, let tempURL else { return }
        self.stream = nil
        onStateChange?(false)
        Task { @MainActor in
            try? await stream.stopCapture()
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            await writer.finishWriting()
            self.writer = nil
            self.videoInput = nil
            self.audioInput = nil
            self.tempURL = nil
            if writer.status == .completed {
                self.promptSave(movieURL: tempURL)
            } else {
                NSLog("ZoomIt: recording failed: \(String(describing: writer.error))")
                NSSound.beep()
            }
        }
    }

    @MainActor
    private func promptSave(movieURL: URL) {
        let settings = settingsStore.settings
        let format = settings.recordingFormat
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .gif ? [.gif] : [.mpeg4Movie]
        panel.directoryURL = settings.saveFolderURL
        panel.nameFieldStringValue = SaveNamer.timestampedURL(
            in: settings.saveFolderURL, prefix: "ZoomIt Recording", ext: format == .gif ? "gif" : "mp4"
        ).lastPathComponent
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                try? FileManager.default.removeItem(at: movieURL)
                return
            }
            switch format {
            case .mp4:
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.moveItem(at: movieURL, to: url)
                } catch {
                    NSLog("ZoomIt: failed to save recording: \(error)")
                }
            case .gif:
                Task.detached {
                    await Self.exportGIF(from: movieURL, to: url)
                    try? FileManager.default.removeItem(at: movieURL)
                }
            }
        }
    }

    /// Transcode the recorded movie to an animated GIF (10 fps, max 960 px wide).
    static func exportGIF(from movieURL: URL, to gifURL: URL) async {
        let asset = AVURLAsset(url: movieURL)
        guard let duration = try? await asset.load(.duration) else { return }
        let fps = 10.0
        let frameCount = max(1, Int(duration.seconds * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        generator.maximumSize = CGSize(width: 960, height: 960)
        let writer = GIFWriter(url: gifURL, frameDelay: 1.0 / fps)
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image {
                writer.add(frame: image)
            }
        }
        do {
            try writer.finalize()
        } catch {
            NSLog("ZoomIt: GIF export failed: \(error)")
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer else { return }
        switch type {
        case .screen:
            // Skip frames that carry no new content.
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let statusRaw = attachments.first?[.status] as? Int,
               let status = SCFrameStatus(rawValue: statusRaw),
               status != .complete {
                return
            }
            if !sessionStarted {
                sessionStarted = true
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            }
            if let videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .microphone:
            guard sessionStarted else { return }
            if let audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            if self?.isRecording == true {
                self?.stop()
            }
        }
    }
}
