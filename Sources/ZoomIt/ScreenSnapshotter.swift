import AppKit
import ScreenCaptureKit

/// Captures still screenshots with ScreenCaptureKit.
enum ScreenSnapshotter {
    enum SnapshotError: Error {
        case noDisplay
        case captureFailed
    }

    /// The NSScreen currently containing the mouse cursor.
    static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// Capture a full-screen image of `screen` at native pixel resolution,
    /// excluding this app's own windows.
    static func capture(screen: NSScreen) async throws -> CGImage {
        let displayID = displayID(for: screen)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw SnapshotError.noDisplay
        }
        let ourWindows = content.windows.filter { $0.owningApplication?.processID == pid_t(ProcessInfo.processInfo.processIdentifier) }
        let filter = SCContentFilter(display: display, excludingWindows: ourWindows)
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            throw SnapshotError.captureFailed
        }
        return image
    }

    /// Capture a region of `screen`. `rect` is in screen points using Cocoa's
    /// global coordinate space (origin bottom-left of the primary display).
    static func capture(rect: NSRect, on screen: NSScreen) async throws -> CGImage {
        let full = try await capture(screen: screen)
        let scale = screen.backingScaleFactor
        // Convert Cocoa global rect to the screen's local top-left-origin pixel rect.
        let local = CGRect(
            x: (rect.minX - screen.frame.minX) * scale,
            y: (screen.frame.maxY - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = full.cropping(to: local) else {
            throw SnapshotError.captureFailed
        }
        return cropped
    }
}

extension CGImage {
    var nsImage: NSImage {
        NSImage(cgImage: self, size: NSSize(width: width, height: height))
    }

    func pngData() -> Data? {
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .png, properties: [:])
    }

    @discardableResult
    func copyToPasteboard() -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: self)
        guard let tiff = rep.tiffRepresentation else { return false }
        return pb.setData(tiff, forType: .tiff)
    }

    @discardableResult
    func savePNG(to url: URL) -> Bool {
        guard let data = pngData() else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            NSLog("ZoomIt: failed to save PNG: \(error)")
            return false
        }
    }
}

enum SaveNamer {
    static func timestampedURL(in folder: URL, prefix: String, ext: String, now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "\(prefix) \(formatter.string(from: now)).\(ext)"
        return folder.appendingPathComponent(name)
    }
}
