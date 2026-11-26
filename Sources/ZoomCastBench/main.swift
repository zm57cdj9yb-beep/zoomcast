import Foundation
import ZoomCastCore

@main
struct ZoomCastBench {
    static func main() async {
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("zoomcast-bench-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let tDemo0 = CFAbsoluteTimeGetCurrent()
            let project = try await DemoProjectGenerator.createDemoProject(in: tempDir)
            let demoMs = (CFAbsoluteTimeGetCurrent() - tDemo0) * 1000.0

            // 1. SpringCameraEngine 10,000 evaluations
            let engine = SpringCameraEngine()
            let tCam0 = CFAbsoluteTimeGetCurrent()
            var acc = 0.0
            for i in 0..<10_000 {
                let t = Double(i) / 10_000.0 * project.duration
                let cam = engine.evaluate(
                    at: t,
                    segments: project.zoomSegments,
                    cursorSamples: project.cursorSamples,
                    easing: project.style.easing
                )
                acc += cam.scale
            }
            let camMs = (CFAbsoluteTimeGetCurrent() - tCam0) * 1000.0

            // 2. Full 1920x1080 H.264 MP4 Auto-Zoom Export (180 frames)
            let exporter = VideoExporter()
            let mp4URL = tempDir.appendingPathComponent("export_1080p.mp4")
            let mp4Result = try await exporter.exportMP4(project: project, to: mp4URL)
            let mp4FPS = Double(mp4Result.frameCount) / max(0.001, mp4Result.elapsedMs / 1000.0)

            // 3. Web Animated GIF Export (960x540 @ 15fps = 90 frames)
            let gifURL = tempDir.appendingPathComponent("export_web.gif")
            let gifResult = try await exporter.exportGIF(project: project, to: gifURL, targetFPS: 15.0, maxWidth: 960.0)
            let gifFPS = Double(gifResult.frameCount) / max(0.001, gifResult.elapsedMs / 1000.0)

            print("DEMO_GEN_MS=\(String(format: "%.1f", demoMs))")
            print("CAMERA_10K_MS=\(String(format: "%.2f", camMs)) ACC=\(String(format: "%.2f", acc))")
            print("MP4_1080P_FRAMES=\(mp4Result.frameCount) MS=\(String(format: "%.1f", mp4Result.elapsedMs)) FPS=\(String(format: "%.1f", mp4FPS)) BYTES=\(mp4Result.fileSizeBytes)")
            print("GIF_960P_FRAMES=\(gifResult.frameCount) MS=\(String(format: "%.1f", gifResult.elapsedMs)) FPS=\(String(format: "%.1f", gifFPS)) BYTES=\(gifResult.fileSizeBytes)")
        } catch {
            fputs("BENCH_ERROR: \(error)\n", stderr)
            exit(1)
        }
    }
}
