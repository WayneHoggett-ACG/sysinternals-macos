# ZoomIt for macOS

A native macOS port of [Sysinternals ZoomIt](https://learn.microsoft.com/en-us/sysinternals/downloads/zoomit), Mark Russinovich's screen zoom, annotation, and recording tool for technical presentations and demos.

Built with Swift + AppKit + ScreenCaptureKit. Runs as a menu-bar app, just like ZoomIt's tray presence on Windows.

## Building

```sh
make app    # builds dist/ZoomIt.app (release, ad-hoc signed)
make test   # runs the unit test suite
make run    # builds and launches
```

Requires macOS 14+ and Xcode command line tools.

On first use of any capture feature, grant **Screen Recording** permission (System Settings → Privacy & Security). DemoType additionally needs **Accessibility** permission to type into other apps. Recording with microphone audio requires macOS 15+.

## Features and shortcuts

Defaults match ZoomIt for Windows (Ctrl = ⌃ control). All hotkeys are customizable in Options.

| Function | Shortcut |
| --- | --- |
| Zoom mode | ⌃1 |
| Zoom in / out | Mouse scroll or ↑ / ↓ |
| Start drawing (while zoomed) | Left-click |
| Stop drawing (back to pan) | Right-click |
| Draw without zoom | ⌃2 |
| Pen width | ⌃scroll or ↑ / ↓ (while drawing) |
| Center the cursor | Space (while drawing) |
| Whiteboard / Blackboard | W / K |
| Type text (left / right aligned) | T / ⇧T |
| Font size | ⌃scroll or ↑ / ↓ (while typing) |
| Pen colors | R G B Y O P |
| Highlighter | ⇧ + color key |
| Blur pen | X |
| Straight line / rectangle / ellipse / arrow | hold ⇧ / ⌃ / Tab / ⌃⇧ while dragging |
| Undo last drawing | ⌃Z (or ⌘Z) |
| Erase all drawings | E |
| Copy screenshot / crop and copy | ⌃C / ⌃⇧C |
| Save screenshot / crop and save | ⌃S / ⌃⇧S |
| Snip region to clipboard / file | ⌃6 / ⌃⇧6 |
| Copy text from region (OCR) | ⌃⌥6 |
| Record screen (MP4 or GIF) / region / window | ⌃5 / ⌃⇧5 / ⌃⌥5 |
| Break timer (adjust with ⌃scroll or ↑/↓) | ⌃3 |
| Hide timer without pausing / restore | ⌘M / menu-bar icon |
| LiveZoom (screen keeps updating) | ⌃4 |
| LiveDraw (draw over live windows) | ⌃⇧4 |
| DemoType next snippet / previous snippet | ⌃7 / ⌃⇧7 |
| Advance snippet (DemoType user-driven mode) | Space |
| Panorama (scrolling screenshot) start/stop | ⌃8 |
| Exit any mode | Esc or right-click |

### Notes on the macOS port

- **Zoom** captures a still of the screen under the cursor and magnifies it; move the mouse to pan, scroll/arrows to zoom (4 steps per doubling, 1×–32×), left-click to annotate the zoomed image.
- **LiveZoom** uses a ScreenCaptureKit stream, so video and animations keep playing while magnified.
- **Record** writes H.264 MP4 via AVFoundation; choose GIF in Options to export an animated GIF instead. Region and window-under-cursor recording are supported.
- **OCR snip** uses the Vision framework and copies recognized text to the clipboard.
- **Panorama** (⌃8): select a region, scroll through the content, press ⌃8 again — frames are stitched into one tall PNG (copied to clipboard and offered for saving). Scroll slowly for best stitching accuracy.
- **DemoType** scripts are plain text files. Snippets are separated by lines containing `[end]`; `[pause:N]` pauses N tenths of a second mid-snippet. See `Examples/demotype-sample.txt`.
- **Break timer** keeps counting while hidden (⌘M); restore it from the menu-bar icon.

## Project layout

- `Sources/ZoomItCore` — platform-independent logic (zoom math, drawing model and renderer, DemoType parser, panorama stitcher, GIF writer, settings, timer model), fully unit tested.
- `Sources/ZoomIt` — the AppKit app: menu bar item, Carbon global hotkeys, overlay windows, ScreenCaptureKit capture/recording, Vision OCR, options UI.
- `Tests/ZoomItCoreTests` — unit tests (`swift test`).

There is also a built-in end-to-end smoke test that exercises the real status item, hotkey registration, overlay render pipeline, and break timer:

```sh
./dist/ZoomIt.app/Contents/MacOS/ZoomIt --selftest
```
