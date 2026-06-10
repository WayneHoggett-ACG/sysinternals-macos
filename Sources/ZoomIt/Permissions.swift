import AppKit
import ApplicationServices

enum Permissions {
    /// Screen-recording permission: needed for zoom, draw-over-screen,
    /// LiveZoom, record, snip, and panorama.
    static func ensureScreenCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "ZoomIt needs Screen Recording access to capture the screen. Grant it in System Settings → Privacy & Security → Screen Recording, then relaunch ZoomIt."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

    /// Accessibility permission: needed by DemoType to synthesize keystrokes.
    static func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }
}
