# Changelog

## [1.0.0] - 2026-11-26

### Added
- Native Swift 6 / SwiftUI / AppKit studio editor (`ZoomCast.app`, `2.7 MB`, zero external Swift packages).
- `ScreenCaptureKit` display recorder (`SCStream` + `AVAssetWriter` H.264) with synchronized cursor and left-click tracking.
- `SpringCameraEngine` with automatic click clustering, bounds-clamped crops, `Spring Smooth` / `Snappy` / `Gentle` easing, and click-ripple evaluation.
- `VideoCompositor` with 8 studio gradient presets, padding, corner radius, soft drop shadow, aspect presets (`16:9`, `1440p`, `1:1`, `9:16`), cursor highlight, and click ripples.
- Hardware-accelerated H.264 `.mp4` exporter (`31.8 fps` at 1080p on Apple M2) and 15 fps web `.gif` exporter (`30.4 fps` at `960×540`).
- First-launch 6-second 1080p demo project generator and 6 end-to-end XCTests.
