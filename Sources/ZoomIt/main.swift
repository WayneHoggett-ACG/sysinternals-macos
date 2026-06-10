import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only app (like ZoomIt's tray presence on Windows).
app.setActivationPolicy(.accessory)
app.run()
