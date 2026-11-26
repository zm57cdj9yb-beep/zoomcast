# Contributing to ZoomCast

Contributions are welcome! ZoomCast is pure Swift 6 with zero external Swift packages.

## Local Development

```bash
swift test
./scripts/build_app.sh debug
open build/ZoomCast.app
```

## Guidelines
- Keep `ZoomCastCore` free of UI imports where possible (AppKit is only used in `ScreenRecorder`).
- Add XCTests in `Tests/ZoomCastCoreTests/` for engine, compositor, or export changes.
- Run `swift test` and `./benchmarks/run_benchmarks.sh` before opening a PR.
