import AVFoundation
import CoreGraphics
import Foundation
import XCTest
@testable import ZoomCastCore

final class ZoomCastCoreTests: XCTestCase {

    func testSpringCameraAutoGeneratesAndMergesNearbyClicks() {
        let samples = [
            CursorSample(time: 0.5, position: NormalizedPoint(x: 0.2, y: 0.3), isClick: true),
            CursorSample(time: 1.0, position: NormalizedPoint(x: 0.4, y: 0.3), isClick: true), // merges with first
            CursorSample(time: 4.5, position: NormalizedPoint(x: 0.8, y: 0.7), isClick: true)  // separate segment
        ]
        let engine = SpringCameraEngine()
        let segments = engine.autoGenerateZoomSegments(from: samples, duration: 6.0, defaultScale: 2.0)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].focus.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(segments[1].focus.x, 0.8, accuracy: 0.001)
        XCTAssertLessThanOrEqual(segments[1].endTime, 6.0)
    }

    func testSpringCameraEasingAndBoundsClamping() {
        let seg = ZoomSegment(startTime: 1.0, endTime: 3.0, scale: 2.5, focus: NormalizedPoint(x: 0.05, y: 0.95))
        let engine = SpringCameraEngine()

        // Outside segment -> scale 1.0
        let before = engine.evaluate(at: 0.5, segments: [seg], cursorSamples: [], easing: .springSmooth)
        XCTAssertEqual(before.scale, 1.0, accuracy: 0.001)

        // Midpoint -> full scale 2.5
        let mid = engine.evaluate(at: 2.0, segments: [seg], cursorSamples: [], easing: .springSmooth)
        XCTAssertEqual(mid.scale, 2.5, accuracy: 0.001)

        // Crop rect must stay strictly within [0..1] even near corners
        let crop = SpringCameraEngine.normalizedCropRect(scale: mid.scale, focus: mid.focus)
        XCTAssertGreaterThanOrEqual(crop.minX, 0.0)
        XCTAssertGreaterThanOrEqual(crop.minY, 0.0)
        XCTAssertLessThanOrEqual(crop.maxX, 1.0 + 1e-6)
        XCTAssertLessThanOrEqual(crop.maxY, 1.0 + 1e-6)
    }

    func testCursorInterpolationAndClickRipple() {
        let samples = [
            CursorSample(time: 0.0, position: NormalizedPoint(x: 0.0, y: 0.0), isClick: false),
            CursorSample(time: 1.0, position: NormalizedPoint(x: 1.0, y: 1.0), isClick: true),
            CursorSample(time: 2.0, position: NormalizedPoint(x: 1.0, y: 0.0), isClick: false)
        ]
        let engine = SpringCameraEngine()

        let atHalf = engine.evaluate(at: 0.5, segments: [], cursorSamples: samples, easing: .springSmooth)
        XCTAssertEqual(atHalf.cursorPosition?.x ?? -1, 0.5, accuracy: 0.01)
        XCTAssertNil(atHalf.clickRippleProgress)

        let afterClick = engine.evaluate(at: 1.2, segments: [], cursorSamples: samples, easing: .springSmooth)
        XCTAssertNotNil(afterClick.clickRippleProgress)
        XCTAssertGreaterThan(afterClick.clickRippleProgress ?? 0, 0.4)
    }

    func testProjectCodableRoundTrip() throws {
        let project = ZoomCastProject(
            title: "RoundTrip Demo",
            videoPath: "/tmp/demo.mp4",
            duration: 6.0,
            sourceWidth: 1920,
            sourceHeight: 1080,
            fps: 30,
            style: CanvasStyle(backgroundID: "sunset-coral", padding: 80, cornerRadius: 24, aspect: .square1x1),
            zoomSegments: [ZoomSegment(startTime: 1.0, endTime: 2.5, scale: 2.2, focus: NormalizedPoint(x: 0.3, y: 0.4))],
            cursorSamples: [CursorSample(time: 1.2, position: NormalizedPoint(x: 0.3, y: 0.4), isClick: true)]
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ZoomCastProject.self, from: data)
        XCTAssertEqual(decoded, project)
    }

    func testVideoCompositorProducesValidStyledImage() {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 320 * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return XCTFail("Could not create test CGContext")
        }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        guard let src = ctx.makeImage() else { return XCTFail("No source CGImage") }

        let compositor = VideoCompositor()
        let cam = CameraState(
            scale: 1.8,
            focus: NormalizedPoint(x: 0.35, y: 0.45),
            cursorPosition: NormalizedPoint(x: 0.35, y: 0.45),
            clickRippleProgress: 0.4,
            clickRipplePosition: NormalizedPoint(x: 0.35, y: 0.45)
        )
        let out = compositor.compose(
            sourceFrame: src,
            style: CanvasStyle(backgroundID: "emerald-aurora", padding: 48, cornerRadius: 16),
            camera: cam,
            outputSize: CGSize(width: 640, height: 360)
        )

        XCTAssertNotNil(out)
        XCTAssertEqual(out?.width, 640)
        XCTAssertEqual(out?.height, 360)
    }

    func testDemoGenerationAndMP4AndGIFExportEndToEnd() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomcast-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let project = try await DemoProjectGenerator.createDemoProject(in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.videoPath))
        XCTAssertEqual(project.zoomSegments.count, 3)
        XCTAssertEqual(project.clickEvents.count, 3)

        // Export scaled 640x360 MP4 for fast CI verification
        let exporter = VideoExporter()
        let mp4URL = dir.appendingPathComponent("out.mp4")
        let mp4Res = try await exporter.exportMP4(
            project: project,
            to: mp4URL,
            outputSize: CGSize(width: 640, height: 360)
        )
        XCTAssertGreaterThanOrEqual(mp4Res.frameCount, 170)
        XCTAssertGreaterThan(mp4Res.fileSizeBytes, 50_000)

        let outAsset = AVURLAsset(url: mp4URL)
        let outTracks = try await outAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(outTracks.count, 1)
        let outDur = CMTimeGetSeconds(try await outAsset.load(.duration))
        XCTAssertEqual(outDur, 6.0, accuracy: 0.3)

        // Export web GIF (5 fps, 480w for fast test)
        let gifURL = dir.appendingPathComponent("out.gif")
        let gifRes = try await exporter.exportGIF(project: project, to: gifURL, targetFPS: 5.0, maxWidth: 480.0)
        XCTAssertGreaterThanOrEqual(gifRes.frameCount, 25)
        XCTAssertGreaterThan(gifRes.fileSizeBytes, 20_000)
    }
}
