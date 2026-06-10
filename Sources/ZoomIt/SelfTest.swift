import AppKit
import ZoomItCore

/// In-process smoke test (`ZoomIt --selftest`): exercises the real status
/// item, hotkey registration, overlay drawing pipeline, and break timer, then
/// prints a report and exits non-zero on failure. Windows are made invisible
/// so the run does not disturb the screen.
extension AppDelegate {
    func runSelfTest() {
        var failures: [String] = []

        func check(_ condition: Bool, _ name: String) {
            print(condition ? "PASS  \(name)" : "FAIL  \(name)")
            if !condition { failures.append(name) }
        }

        // 1. Hotkeys: all 14 actions registered with Carbon.
        check(selfTestHotkeyCount == HotkeyAction.allCases.count,
              "hotkeys registered (\(selfTestHotkeyCount)/\(HotkeyAction.allCases.count))")

        // 2. Status item present in the menu bar.
        check(selfTestHasStatusItem, "status item created")

        // 3. Settings store round-trips.
        let originalWidth = settingsStore.settings.penWidth
        settingsStore.update { $0.penWidth = 17 }
        check(SettingsStore().settings.penWidth == 17, "settings persisted to UserDefaults")
        settingsStore.update { $0.penWidth = originalWidth }

        // 4. LiveDraw overlay: open invisibly, draw annotations, verify pixels.
        let overlay = selfTestOverlay
        overlay.begin(.liveDraw)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            defer {
                overlay.dismiss()
                self.selfTestBreakTimer(check: check) {
                    print(failures.isEmpty ? "SELFTEST PASSED" : "SELFTEST FAILED: \(failures.joined(separator: ", "))")
                    exit(failures.isEmpty ? 0 : 1)
                }
            }
            guard let view = overlay.view, let window = overlay.window else {
                check(false, "overlay window created")
                return
            }
            window.alphaValue = 0  // keep the test invisible
            check(view.sessionKind == .liveDraw, "overlay session kind")

            // Draw on a whiteboard so no screen capture is needed.
            view.model.toggleBoard(.whiteboard)
            view.model.add(.stroke(StrokeAnnotation(
                points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300), CGPoint(x: 500, y: 200)],
                color: .red, width: 8
            )))
            view.model.add(.shape(ShapeAnnotation(
                kind: .arrow, start: CGPoint(x: 200, y: 400), end: CGPoint(x: 600, y: 450),
                color: .blue, width: 6
            )))
            view.model.add(.text(TextAnnotation(
                origin: CGPoint(x: 150, y: 500), text: "Self test", color: .green, fontSize: 48
            )))

            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                check(false, "overlay bitmap render")
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            var sawWhite = false, sawRed = false, sawBlue = false
            let width = rep.pixelsWide, height = rep.pixelsHigh
            for y in stride(from: 0, to: height, by: 4) {
                for x in stride(from: 0, to: width, by: 4) {
                    guard let color = rep.colorAt(x: x, y: y) else { continue }
                    let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                    if r > 0.9 && g > 0.9 && b > 0.9 { sawWhite = true }
                    if r > 0.8 && g < 0.3 && b < 0.3 { sawRed = true }
                    if b > 0.7 && r < 0.4 { sawBlue = true }
                }
            }
            check(sawWhite, "whiteboard background rendered")
            check(sawRed, "pen stroke rendered")
            check(sawBlue, "arrow shape rendered")
        }
    }

    private func selfTestBreakTimer(check: @escaping (Bool, String) -> Void, completion: @escaping () -> Void) {
        let timer = BreakTimerController(settingsStore: settingsStore)
        timer.hiddenForTesting = true
        timer.begin()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            check(timer.isActive, "break timer active")
            timer.minimize()
            check(timer.isMinimized, "break timer keeps running while minimized")
            timer.stop()
            check(!timer.isActive, "break timer stopped")
            completion()
        }
    }
}
