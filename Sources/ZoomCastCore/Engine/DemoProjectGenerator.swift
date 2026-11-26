import AVFoundation
import CoreGraphics
import CoreMedia
import CoreText
import CoreVideo
import Foundation

public enum DemoProjectGenerator {
    /// Generates a crisp 6-second 1080p (30 fps) synthetic macOS developer app screencast
    /// with synchronized cursor motion and 3 click-triggered auto-zoom segments.
    public static func createDemoProject(in directory: URL) async throws -> ZoomCastProject {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let videoURL = directory.appendingPathComponent("demo_recording.mp4")

        let width = 1920
        let height = 1080
        let fps = 30
        let duration = 6.0
        let totalFrames = Int(duration * Double(fps))

        // Build deterministic cursor path with 3 clicks on interactive regions
        let cursorSamples = buildDemoCursorSamples(duration: duration, fps: fps)

        if !FileManager.default.fileExists(atPath: videoURL.path) {
            try await renderDemoVideo(
                to: videoURL,
                width: width,
                height: height,
                fps: fps,
                totalFrames: totalFrames,
                cursorSamples: cursorSamples
            )
        }

        let engine = SpringCameraEngine()
        let autoSegments = engine.autoGenerateZoomSegments(
            from: cursorSamples,
            duration: duration,
            defaultScale: 2.05,
            leadIn: 0.25,
            holdDuration: 1.05,
            mergeThreshold: 0.25
        )

        return ZoomCastProject(
            title: "Product Demo — Launch Recording",
            videoPath: videoURL.path,
            duration: duration,
            sourceWidth: width,
            sourceHeight: height,
            fps: Double(fps),
            style: CanvasStyle(
                backgroundID: "midnight-indigo",
                padding: 74,
                cornerRadius: 20,
                shadowIntensity: 0.70,
                aspect: .landscape16x9,
                easing: .springSmooth,
                showCursorHighlight: true,
                showClickRipples: true
            ),
            zoomSegments: autoSegments,
            cursorSamples: cursorSamples
        )
    }

    public static func buildDemoCursorSamples(duration: Double, fps: Int) -> [CursorSample] {
        // Keyframes: (time, x, y, isClick)
        let waypoints: [(Double, Double, Double, Bool)] = [
            (0.0, 0.50, 0.50, false),
            (0.7, 0.25, 0.32, false),
            (1.1, 0.24, 0.31, true),   // Click #1: Deploy / Run Pipeline card (top-left)
            (2.2, 0.28, 0.35, false),
            (2.7, 0.72, 0.36, false),
            (3.0, 0.74, 0.35, true),   // Click #2: Live Benchmark chart (top-right)
            (4.1, 0.65, 0.58, false),
            (4.8, 0.52, 0.74, true),   // Click #3: Terminal output panel (bottom-center)
            (6.0, 0.54, 0.72, false)
        ]

        var samples: [CursorSample] = []
        let totalSteps = Int(duration * Double(fps))
        for step in 0...totalSteps {
            let t = Double(step) / Double(fps)
            var segIdx = 0
            for i in 0..<(waypoints.count - 1) {
                if t >= waypoints[i].0 && t <= waypoints[i + 1].0 {
                    segIdx = i
                    break
                }
            }
            let a = waypoints[segIdx]
            let b = waypoints[min(segIdx + 1, waypoints.count - 1)]
            let span = max(0.001, b.0 - a.0)
            let rawFrac = min(max((t - a.0) / span, 0.0), 1.0)
            let smooth = rawFrac * rawFrac * (3.0 - 2.0 * rawFrac)
            let x = a.1 + (b.1 - a.1) * smooth
            let y = a.2 + (b.2 - a.2) * smooth
            let isClick = waypoints.contains { wp in wp.3 && abs(wp.0 - t) < (0.40 / Double(fps)) }
            samples.append(CursorSample(time: t, position: NormalizedPoint(x: x, y: y), isClick: isClick))
        }
        return samples
    }

    private static func renderDemoVideo(
        to url: URL,
        width: Int,
        height: Int,
        fps: Int,
        totalFrames: Int,
        cursorSamples: [CursorSample]
    ) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let progress = Double(frame) / Double(max(1, totalFrames - 1))
            let t = Double(frame) / Double(fps)
            let pts = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))

            autoreleasepool {
                var pixelBuffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
                      let pb = pixelBuffer else { return }

                CVPixelBufferLockBaseAddress(pb, [])
                defer { CVPixelBufferUnlockBaseAddress(pb, []) }

                if let base = CVPixelBufferGetBaseAddress(pb),
                   let ctx = CGContext(
                       data: base,
                       width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                       space: colorSpace,
                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                   ) {
                    drawSyntheticMacAppFrame(ctx: ctx, width: width, height: height, time: t, progress: progress)
                }

                _ = adaptor.append(pb, withPresentationTime: pts)
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
    }

    private static func drawSyntheticMacAppFrame(
        ctx: CGContext,
        width: Int,
        height: Int,
        time: Double,
        progress: Double
    ) {
        let cs = CGColorSpaceCreateDeviceRGB()
        func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
            CGColor(colorSpace: cs, components: [r, g, b, a])!
        }

        // App window background (deep slate macOS dark mode)
        ctx.setFillColor(col(0.085, 0.095, 0.125))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Top macOS titlebar
        ctx.setFillColor(col(0.115, 0.125, 0.16))
        ctx.fill(CGRect(x: 0, y: height - 56, width: width, height: 56))
        ctx.setFillColor(col(1, 1, 1, 0.08))
        ctx.fill(CGRect(x: 0, y: height - 57, width: width, height: 1))

        // Traffic lights
        let dots: [(CGFloat, CGColor)] = [
            (28, col(1.0, 0.37, 0.34)),
            (54, col(1.0, 0.74, 0.18)),
            (80, col(0.15, 0.80, 0.38))
        ]
        for (dx, c) in dots {
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: dx, y: CGFloat(height - 35), width: 14, height: 14))
        }
        drawText(ctx, "SwiftBuild Studio — Release Pipeline", x: 120, y: CGFloat(height - 37), size: 17, bold: true, color: col(0.90, 0.92, 0.96))

        // Left sidebar
        ctx.setFillColor(col(0.098, 0.108, 0.14))
        ctx.fill(CGRect(x: 0, y: 0, width: 290, height: height - 57))
        ctx.setFillColor(col(1, 1, 1, 0.06))
        ctx.fill(CGRect(x: 290, y: 0, width: 1, height: height - 57))

        let navItems = ["Overview", "Build Targets", "Benchmarks", "Signing & Release", "Activity Log"]
        for (i, item) in navItems.enumerated() {
            let y = CGFloat(height - 125 - i * 48)
            if i == 0 {
                let r = CGRect(x: 16, y: y - 10, width: 258, height: 38)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
                ctx.setFillColor(col(0.22, 0.45, 0.98, 0.25))
                ctx.fillPath()
            }
            drawText(ctx, item, x: 34, y: y, size: 16, bold: i == 0, color: i == 0 ? col(0.55, 0.78, 1.0) : col(0.68, 0.72, 0.80))
        }

        // Top-left card: Build Action Card (Click #1 target around x=0.24, y=0.31 from top)
        let card1 = CGRect(x: 330, y: CGFloat(height - 430), width: 520, height: 320)
        drawCard(ctx, rect: card1, fill: col(0.125, 0.14, 0.185), stroke: col(0.28, 0.56, 1.0, time >= 1.0 && time <= 2.4 ? 0.85 : 0.18))
        drawText(ctx, "Apple Silicon Release Build", x: card1.minX + 28, y: card1.maxY - 52, size: 22, bold: true, color: col(0.95, 0.97, 1.0))
        drawText(ctx, "Swift 6 · Zero Dependencies · arm64", x: card1.minX + 28, y: card1.maxY - 82, size: 15, bold: false, color: col(0.60, 0.66, 0.78))

        // Animated deploy button inside card 1
        let btnRect = CGRect(x: card1.minX + 28, y: card1.maxY - 165, width: 210, height: 48)
        let clicked1 = time >= 1.1
        ctx.addPath(CGPath(roundedRect: btnRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(clicked1 ? col(0.16, 0.76, 0.46) : col(0.23, 0.48, 0.98))
        ctx.fillPath()
        drawText(ctx, clicked1 ? "✓ Build Succeeded" : "▶ Run Release Build", x: btnRect.minX + 20, y: btnRect.minY + 15, size: 16, bold: true, color: col(1, 1, 1))

        // Animated progress bar
        let barBg = CGRect(x: card1.minX + 28, y: card1.minY + 46, width: card1.width - 56, height: 14)
        ctx.addPath(CGPath(roundedRect: barBg, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.setFillColor(col(0.08, 0.09, 0.12))
        ctx.fillPath()
        let fillW = barBg.width * CGFloat(min(1.0, max(0.12, progress * 1.25)))
        let barFg = CGRect(x: barBg.minX, y: barBg.minY, width: fillW, height: barBg.height)
        ctx.addPath(CGPath(roundedRect: barFg, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.setFillColor(col(0.28, 0.62, 1.0))
        ctx.fillPath()

        // Top-right card: Live Benchmark Chart (Click #2 target around x=0.74, y=0.35 from top)
        let card2 = CGRect(x: 884, y: CGFloat(height - 430), width: 996, height: 320)
        drawCard(ctx, rect: card2, fill: col(0.125, 0.14, 0.185), stroke: col(0.56, 0.38, 1.0, time >= 3.0 && time <= 4.4 ? 0.85 : 0.18))
        drawText(ctx, "Frame Compositing Throughput (Apple M2)", x: card2.minX + 28, y: card2.maxY - 52, size: 22, bold: true, color: col(0.95, 0.97, 1.0))
        drawText(ctx, "1920×1080 H.264 · Hardware Accelerated", x: card2.minX + 28, y: card2.maxY - 82, size: 15, bold: false, color: col(0.60, 0.66, 0.78))

        let barHeights: [CGFloat] = [0.45, 0.62, 0.58, 0.78, 0.84, 0.92, 0.88, 0.96]
        for (i, h) in barHeights.enumerated() {
            let animH = h * CGFloat(min(1.0, 0.35 + progress * 0.9)) * 155.0
            let bx = card2.minX + 42 + CGFloat(i) * 112
            let br = CGRect(x: bx, y: card2.minY + 34, width: 68, height: animH)
            ctx.addPath(CGPath(roundedRect: br, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.setFillColor(i >= 5 ? col(0.45, 0.38, 1.0) : col(0.24, 0.56, 0.98))
            ctx.fillPath()
        }

        // Bottom terminal panel (Click #3 target around x=0.52, y=0.74 from top)
        let term = CGRect(x: 330, y: 42, width: 1550, height: 572)
        drawCard(ctx, rect: term, fill: col(0.065, 0.075, 0.10), stroke: col(0.20, 0.82, 0.56, time >= 4.6 ? 0.85 : 0.16))
        drawText(ctx, "Terminal — swift test && ./scripts/build_app.sh release", x: term.minX + 28, y: term.maxY - 46, size: 17, bold: true, color: col(0.76, 0.82, 0.92))

        let lines: [(String, CGColor)] = [
            ("$ swift build -c release", col(0.48, 0.78, 1.0)),
            ("Building for production... [14/14] Linking ZoomCast", col(0.75, 0.78, 0.86)),
            ("Build complete! (1.82s)", col(0.25, 0.86, 0.54)),
            ("$ swift test", col(0.48, 0.78, 1.0)),
            ("Executed 9 tests, with 0 failures in 0.42s", col(0.25, 0.86, 0.54)),
            ("$ codesign --verify --strict build/ZoomCast.app", col(0.48, 0.78, 1.0)),
            ("build/ZoomCast.app: valid on disk — ready for release v1.0.0", col(0.95, 0.82, 0.36))
        ]
        let visibleLines = min(lines.count, max(2, Int(progress * Double(lines.count + 2))))
        for i in 0..<visibleLines {
            drawText(ctx, lines[i].0, x: term.minX + 28, y: term.maxY - 102 - CGFloat(i) * 44, size: 18, bold: false, color: lines[i].1)
        }
    }

    private static func drawCard(_ ctx: CGContext, rect: CGRect, fill: CGColor, stroke: CGColor) {
        let path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(stroke)
        ctx.setLineWidth(2.0)
        ctx.strokePath()
    }

    private static func drawText(
        _ ctx: CGContext,
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        bold: Bool,
        color: CGColor
    ) {
        let fontName = bold ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
