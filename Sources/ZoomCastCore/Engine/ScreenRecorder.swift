import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public struct CaptureTargetInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let width: Int
    public let height: Int
    public let displayID: CGDirectDisplayID?
    public let windowID: CGWindowID?

    public init(
        id: String,
        title: String,
        subtitle: String,
        width: Int,
        height: Int,
        displayID: CGDirectDisplayID? = nil,
        windowID: CGWindowID? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.height = height
        self.displayID = displayID
        self.windowID = windowID
    }
}

public enum RecorderError: Error, LocalizedError, Sendable {
    case permissionDenied
    case noDisplayAvailable
    case alreadyRecording
    case notRecording
    case writerSetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required. Enable ZoomCast in System Settings -> Privacy & Security -> Screen & System Audio Recording."
        case .noDisplayAvailable:
            return "No active display was found to capture."
        case .alreadyRecording:
            return "A screen recording is already in progress."
        case .notRecording:
            return "No screen recording is currently active."
        case .writerSetupFailed(let msg):
            return "Could not configure video writer: \(msg)"
        }
    }
}

public struct RecordingFinishedOutput: Sendable {
    public let videoURL: URL
    public let duration: Double
    public let width: Int
    public let height: Int
    public let cursorSamples: [CursorSample]
}

public final class ScreenRecorder: NSObject, @unchecked Sendable {
    private let sampleQueue = DispatchQueue(label: "com.zoomcast.recorder.samples", qos: .userInteractive)
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var startPTS: CMTime = .zero
    private var lastPTS: CMTime = .zero
    private var captureRect: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private var captureWidth: Int = 1920
    private var captureHeight: Int = 1080
    private var startWallTime: CFAbsoluteTime = 0
    private var cursorSamples: [CursorSample] = []
    private var cursorTimer: DispatchSourceTimer?
    private var lastMouseDown = false

    public override init() {
        super.init()
    }

    public static func availableTargets() async throws -> [CaptureTargetInfo] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecorderError.permissionDenied
        }

        var targets: [CaptureTargetInfo] = []
        for (idx, display) in content.displays.enumerated() {
            targets.append(
                CaptureTargetInfo(
                    id: "display-\(display.displayID)",
                    title: "Display \(idx + 1)",
                    subtitle: "\(display.width)×\(display.height) Full Screen",
                    width: display.width,
                    height: display.height,
                    displayID: display.displayID
                )
            )
        }
        return targets
    }

    public func startRecording(to url: URL, targetDisplayID: CGDirectDisplayID? = nil, fps: Int = 30) async throws {
        let active = stateLock.withLock { stream != nil }
        if active { throw RecorderError.alreadyRecording }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecorderError.permissionDenied
        }

        let display = content.displays.first(where: { $0.displayID == targetDisplayID }) ?? content.displays.first
        guard let selectedDisplay = display else {
            throw RecorderError.noDisplayAvailable
        }

        let width = max(2, selectedDisplay.width & ~1)
        let height = max(2, selectedDisplay.height & ~1)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(6_000_000, width * height * 5),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(input) else {
            throw RecorderError.writerSetupFailed("Cannot attach H.264 writer input.")
        }
        assetWriter.add(input)
        guard assetWriter.startWriting() else {
            throw RecorderError.writerSetupFailed(assetWriter.error?.localizedDescription ?? "Unknown writer error")
        }

        let filter = SCContentFilter(display: selectedDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(15, fps)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false // ZoomCast composites crisp cursor highlight + ripples cleanly
        config.queueDepth = 5

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        stateLock.withLock {
            self.stream = scStream
            self.writer = assetWriter
            self.videoInput = input
            self.outputURL = url
            self.sessionStarted = false
            self.startPTS = .zero
            self.lastPTS = .zero
            self.captureRect = selectedDisplay.frame
            self.captureWidth = width
            self.captureHeight = height
            self.startWallTime = CFAbsoluteTimeGetCurrent()
            self.cursorSamples = []
            self.lastMouseDown = false
        }

        try await scStream.startCapture()
        startCursorPolling()
    }

    public func stopRecording() async throws -> RecordingFinishedOutput {
        stopCursorPolling()

        let snapshot = stateLock.withLock { () -> (SCStream?, AVAssetWriter?, AVAssetWriterInput?, URL?, Int, Int, [CursorSample], Bool, Double) in
            let out = (
                self.stream,
                self.writer,
                self.videoInput,
                self.outputURL,
                self.captureWidth,
                self.captureHeight,
                self.cursorSamples,
                self.sessionStarted,
                max(0.2, CFAbsoluteTimeGetCurrent() - self.startWallTime)
            )
            self.stream = nil
            self.writer = nil
            self.videoInput = nil
            self.outputURL = nil
            return out
        }

        let (activeStream, activeWriter, activeInput, url, width, height, samples, started, elapsed) = snapshot

        guard let scStream = activeStream, let writer = activeWriter, let outURL = url else {
            throw RecorderError.notRecording
        }

        try? await scStream.stopCapture()
        activeInput?.markAsFinished()

        if started {
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
        } else {
            writer.cancelWriting()
        }

        return RecordingFinishedOutput(
            videoURL: outURL,
            duration: elapsed,
            width: width,
            height: height,
            cursorSamples: samples
        )
    }

    private func startCursorPolling() {
        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let loc = CGEvent(source: nil)?.location ?? .zero
            let isDown = CGEventSource.buttonState(.combinedSessionState, button: .left)

            self.stateLock.lock()
            let t = max(0.0, CFAbsoluteTimeGetCurrent() - self.startWallTime)
            let rect = self.captureRect
            let isClick = isDown && !self.lastMouseDown
            self.lastMouseDown = isDown
            let nx = (loc.x - rect.origin.x) / max(1.0, rect.width)
            let ny = (loc.y - rect.origin.y) / max(1.0, rect.height)
            self.cursorSamples.append(
                CursorSample(time: t, position: NormalizedPoint(x: nx, y: ny), isClick: isClick)
            )
            self.stateLock.unlock()
        }
        stateLock.lock()
        cursorTimer = timer
        stateLock.unlock()
        timer.resume()
    }

    private func stopCursorPolling() {
        stateLock.lock()
        let timer = cursorTimer
        cursorTimer = nil
        stateLock.unlock()
        timer?.cancel()
    }
}

extension ScreenRecorder: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        stateLock.lock()
        guard let writer = self.writer, let input = self.videoInput else {
            stateLock.unlock()
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !self.sessionStarted {
            writer.startSession(atSourceTime: pts)
            self.sessionStarted = true
            self.startPTS = pts
        }
        self.lastPTS = pts
        stateLock.unlock()

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
