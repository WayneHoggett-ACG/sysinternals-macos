# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-17

Initial native macOS port of Sysinternals ZoomIt.

### Added
- Static zoom with animated zoom in/out, scroll/arrow zoom (1×–32×), and mouse pan.
- Draw mode: solid pens and highlighters in six colors, blur pen, freehand
  strokes, line/rectangle/ellipse/arrow shapes, whiteboard/blackboard, undo and
  erase-all, copy/save with optional crop.
- Type-in-text mode with left/right alignment and live font sizing.
- LiveZoom (live magnification) and LiveDraw (annotate over live windows).
- Break timer with adjustable duration, position/opacity/background options,
  expiry sound, and hide-without-pausing.
- Screen recording (full screen, region, or window under cursor) to H.264 MP4
  or animated GIF, with frame-rate/scaling and optional microphone audio.
- Snip to clipboard or file, and OCR snip (text to clipboard) via Vision.
- DemoType: types script snippets into other apps, with user-driven mode and
  previous-snippet support.
- Panorama scrolling screenshots.
- Options window with a click-to-record hotkey editor; all 14 hotkeys match
  ZoomIt for Windows by default and persist to `UserDefaults`.
- Release pipeline: tag-driven SemVer (version stamped into the bundle from
  `git describe`), GitHub Actions CI on every push/PR, and a release workflow
  that publishes a universal (arm64 + x86_64) `.app` zip on `v*` tags.
- About dialog shows the running version.
