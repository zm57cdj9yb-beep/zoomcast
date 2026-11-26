import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers
import ZoomCastCore

private final class PreviewFrameExtractor: @unchecked Sendable {
    private let generator: AVAssetImageGenerator

    init(videoURL: URL) {
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.03, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.03, preferredTimescale: 600)
        gen.maximumSize = CGSize(width: 1280, height: 720)
        self.generator = gen
    }

    func copyFrame(at seconds: Double) -> CGImage? {
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        return try? generator.copyCGImage(at: cmTime, actualTime: nil)
    }
}

@MainActor
@Observable
public final class StudioStore {
    public var project: ZoomCastProject?
    public var currentTime: Double = 1.25
    public var isPlaying: Bool = false
    public var selectedZoomID: UUID?
    public var previewImage: NSImage?
    public var activeCameraScale: Double = 1.0

    public var isLoadingDemo: Bool = false
    public var isRecording: Bool = false
    public var recordingElapsed: Double = 0.0
    public var isExporting: Bool = false
    public var exportProgress: Double = 0.0
    public var statusMessage: String?
    public var lastExportURL: URL?

    private let cameraEngine = SpringCameraEngine()
    private let compositor = VideoCompositor()
    private let exporter = VideoExporter()
    private let recorder = ScreenRecorder()

    private var frameExtractor: PreviewFrameExtractor?
    private var playbackTimer: Timer?
    private var recordTimer: Timer?
    private var renderTask: Task<Void, Never>?

    public init() {}

    public var selectedZoom: ZoomSegment? {
        guard let id = selectedZoomID else { return nil }
        return project?.zoomSegments.first(where: { $0.id == id })
    }

    public func bootstrapOnLaunch() {
        guard project == nil && !isLoadingDemo else { return }
        loadDemoProject()
    }

    public func loadDemoProject() {
        stopPlayback()
        isLoadingDemo = true
        statusMessage = "Preparing 1080p demo recording..."

        Task {
            do {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let demoDir = appSupport.appendingPathComponent("ZoomCast/DemoProject", isDirectory: true)
                let demo = try await DemoProjectGenerator.createDemoProject(in: demoDir)
                self.setProject(demo, initialTime: 1.35)
                self.selectedZoomID = demo.zoomSegments.first?.id
                self.statusMessage = "Demo ready — 3 click-triggered Auto-Zoom segments active"
            } catch {
                self.statusMessage = "Demo error: \(error.localizedDescription)"
            }
            self.isLoadingDemo = false
        }
    }

    public func setProject(_ newProject: ZoomCastProject, initialTime: Double = 0.0) {
        stopPlayback()
        self.project = newProject
        self.currentTime = min(max(0.0, initialTime), newProject.duration)
        self.selectedZoomID = newProject.zoomSegments.first?.id

        self.frameExtractor = PreviewFrameExtractor(videoURL: URL(fileURLWithPath: newProject.videoPath))

        refreshPreview()
    }

    public func seek(to time: Double) {
        guard let project else { return }
        currentTime = min(max(0.0, time), project.duration)
        refreshPreview()
    }

    public func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let project else { return }
        if currentTime >= project.duration - 0.05 {
            currentTime = 0.0
        }
        isPlaying = true
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let proj = self.project, self.isPlaying else { return }
                let next = self.currentTime + (1.0 / 24.0)
                if next >= proj.duration {
                    self.currentTime = 0.0
                } else {
                    self.currentTime = next
                }
                self.refreshPreview()
            }
        }
    }

    public func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    public func refreshPreview() {
        guard let project, let extractor = frameExtractor else { return }
        let t = currentTime
        let style = project.style
        let segments = project.zoomSegments
        let samples = project.cursorSamples

        let cam = cameraEngine.evaluate(at: t, segments: segments, cursorSamples: samples, easing: style.easing)
        self.activeCameraScale = cam.scale

        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) { [compositor, extractor] in
            guard let rawCG = extractor.copyFrame(at: t) else { return }
            if Task.isCancelled { return }

            let aspectSize = style.aspect.pixelSize
            let maxPreviewWidth: Double = 1120.0
            let scale = min(1.0, maxPreviewWidth / aspectSize.width)
            let outSize = CGSize(
                width: Double(Int(aspectSize.width * scale) & ~1),
                height: Double(Int(aspectSize.height * scale) & ~1)
            )
            guard let composed = compositor.compose(
                sourceFrame: rawCG,
                style: style,
                camera: cam,
                outputSize: outSize
            ) else { return }

            if Task.isCancelled { return }
            let nsImg = NSImage(cgImage: composed, size: NSSize(width: composed.width, height: composed.height))
            await MainActor.run {
                self.previewImage = nsImg
            }
        }
    }

    // MARK: - Style & Zoom Mutations

    public func updateStyle(_ mutate: (inout CanvasStyle) -> Void) {
        guard var proj = project else { return }
        mutate(&proj.style)
        project = proj
        refreshPreview()
    }

    public func addZoomAtPlayhead() {
        guard var proj = project else { return }
        let start = max(0.0, currentTime - 0.15)
        let end = min(proj.duration, start + 1.5)
        let focus = cameraEngine.evaluate(
            at: currentTime,
            segments: [],
            cursorSamples: proj.cursorSamples,
            easing: proj.style.easing
        ).cursorPosition ?? .center

        let seg = ZoomSegment(
            startTime: start,
            endTime: max(start + 0.5, end),
            scale: 2.0,
            focus: focus,
            label: "Zoom #\(proj.zoomSegments.count + 1)"
        )
        proj.zoomSegments.append(seg)
        proj.zoomSegments.sort { $0.startTime < $1.startTime }
        project = proj
        selectedZoomID = seg.id
        statusMessage = "Added \(String(format: "%.1f×", seg.scale)) zoom at \(formatTime(start))"
        refreshPreview()
    }

    public func autoGenerateZooms() {
        guard var proj = project else { return }
        let generated = cameraEngine.autoGenerateZoomSegments(
            from: proj.cursorSamples,
            duration: proj.duration,
            defaultScale: 2.05,
            leadIn: 0.25,
            holdDuration: 1.05,
            mergeThreshold: 0.25
        )
        if generated.isEmpty {
            // Fallback: create a clean midpoint zoom if imported video has no recorded clicks
            let mid = proj.duration * 0.5
            proj.zoomSegments = [
                ZoomSegment(
                    startTime: max(0, mid - 1.0),
                    endTime: min(proj.duration, mid + 1.0),
                    scale: 1.85,
                    focus: .center,
                    label: "Center Zoom"
                )
            ]
            statusMessage = "No click track found — created center focus zoom"
        } else {
            proj.zoomSegments = generated
            statusMessage = "Generated \(generated.count) Auto-Zoom segments from clicks"
        }
        project = proj
        selectedZoomID = proj.zoomSegments.first?.id
        refreshPreview()
    }

    public func updateSelectedZoom(_ mutate: (inout ZoomSegment) -> Void) {
        guard var proj = project,
              let id = selectedZoomID,
              let idx = proj.zoomSegments.firstIndex(where: { $0.id == id }) else { return }
        mutate(&proj.zoomSegments[idx])
        proj.zoomSegments[idx].endTime = min(proj.duration, max(proj.zoomSegments[idx].startTime + 0.3, proj.zoomSegments[idx].endTime))
        project = proj
        refreshPreview()
    }

    public func deleteSelectedZoom() {
        guard var proj = project, let id = selectedZoomID else { return }
        proj.zoomSegments.removeAll { $0.id == id }
        project = proj
        selectedZoomID = proj.zoomSegments.first?.id
        statusMessage = "Removed zoom segment"
        refreshPreview()
    }

    // MARK: - Recording & Import

    public func toggleRecording() {
        if isRecording {
            stopScreenRecording()
        } else {
            startScreenRecording()
        }
    }

    private func startScreenRecording() {
        stopPlayback()
        Task { [weak self] in
            guard let self else { return }
            do {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let recDir = appSupport.appendingPathComponent("ZoomCast/Recordings", isDirectory: true)
                try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
                let stamp = Int(Date().timeIntervalSince1970)
                let outURL = recDir.appendingPathComponent("capture-\(stamp).mp4")

                try await recorder.startRecording(to: outURL, fps: 30)
                self.isRecording = true
                self.recordingElapsed = 0.0
                self.statusMessage = "Recording screen & cursor clicks..."
                self.recordTimer?.invalidate()
                self.recordTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recordingElapsed += 0.1
                    }
                }
            } catch {
                self.statusMessage = error.localizedDescription
            }
        }
    }

    private func stopScreenRecording() {
        recordTimer?.invalidate()
        recordTimer = nil
        Task {
            do {
                let output = try await recorder.stopRecording()
                self.isRecording = false
                let zooms = cameraEngine.autoGenerateZoomSegments(
                    from: output.cursorSamples,
                    duration: output.duration,
                    defaultScale: 2.0
                )
                let newProj = ZoomCastProject(
                    title: "Screen Recording (\(formatTime(output.duration)))",
                    videoPath: output.videoURL.path,
                    duration: output.duration,
                    sourceWidth: output.width,
                    sourceHeight: output.height,
                    fps: 30.0,
                    style: project?.style ?? CanvasStyle(),
                    zoomSegments: zooms,
                    cursorSamples: output.cursorSamples
                )
                self.setProject(newProj, initialTime: min(0.5, output.duration * 0.25))
                self.statusMessage = "Captured \(formatTime(output.duration)) · \(output.cursorSamples.filter(\.isClick).count) clicks detected"
            } catch {
                self.isRecording = false
                self.statusMessage = "Stop error: \(error.localizedDescription)"
            }
        }
    }

    public func importVideo() {
        stopPlayback()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.allowsMultipleSelection = false
        panel.title = "Import Screen Recording"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else {
                    self.statusMessage = "Selected file has no video track."
                    return
                }
                let dur = max(0.5, CMTimeGetSeconds(try await asset.load(.duration)))
                let natSize = try await track.load(.naturalSize)
                let newProj = ZoomCastProject(
                    title: url.deletingPathExtension().lastPathComponent,
                    videoPath: url.path,
                    duration: dur,
                    sourceWidth: Int(abs(natSize.width)),
                    sourceHeight: Int(abs(natSize.height)),
                    fps: 30.0,
                    style: project?.style ?? CanvasStyle(),
                    zoomSegments: [
                        ZoomSegment(
                            startTime: min(1.0, dur * 0.2),
                            endTime: min(dur, min(1.0, dur * 0.2) + 1.8),
                            scale: 1.9,
                            focus: .center,
                            label: "Intro Zoom"
                        )
                    ],
                    cursorSamples: []
                )
                self.setProject(newProj, initialTime: 0.0)
                self.statusMessage = "Imported \(url.lastPathComponent) (\(formatTime(dur)))"
            } catch {
                self.statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Export

    public func export(format: ExportFormat) {
        guard let project, !isExporting else { return }
        stopPlayback()

        let panel = NSSavePanel()
        panel.title = format == .mp4H264 ? "Export Studio MP4" : "Export Web GIF"
        panel.allowedContentTypes = format == .mp4H264 ? [.mpeg4Movie] : [.gif]
        let baseName = project.title.replacingOccurrences(of: " ", with: "_")
        panel.nameFieldStringValue = format == .mp4H264 ? "\(baseName).mp4" : "\(baseName).gif"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isExporting = true
        exportProgress = 0.02
        statusMessage = "Exporting \(format.rawValue)..."

        Task {
            do {
                let result: ExportResult
                if format == .mp4H264 {
                    result = try await exporter.exportMP4(project: project, to: destURL) { p in
                        Task { @MainActor in self.exportProgress = p }
                    }
                } else {
                    result = try await exporter.exportGIF(project: project, to: destURL) { p in
                        Task { @MainActor in self.exportProgress = p }
                    }
                }
                self.isExporting = false
                self.exportProgress = 1.0
                self.lastExportURL = result.outputURL
                let mb = Double(result.fileSizeBytes) / (1024.0 * 1024.0)
                let sec = result.elapsedMs / 1000.0
                self.statusMessage = String(format: "Exported %@ (%.2f MB, %d frames in %.2fs)", destURL.lastPathComponent, mb, result.frameCount, sec)
            } catch {
                self.isExporting = false
                self.statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    public func revealLastExport() {
        guard let url = lastExportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func formatTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = clamped.truncatingRemainder(dividingBy: 60.0)
        return String(format: "%02d:%05.2f", mins, secs)
    }
}
