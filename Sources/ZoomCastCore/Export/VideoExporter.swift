import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportError: Error, LocalizedError, Sendable {
    case missingVideoTrack
    case readerFailed(String)
    case writerFailed(String)
    case gifDestinationFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingVideoTrack: return "The source video contains no readable video track."
        case .readerFailed(let msg): return "Failed to read source video: \(msg)"
        case .writerFailed(let msg): return "Failed to write output video: \(msg)"
        case .gifDestinationFailed: return "Failed to initialize GIF image destination."
        case .cancelled: return "Export was cancelled."
        }
    }
}

public struct ExportResult: Sendable {
    public let outputURL: URL
    public let frameCount: Int
    public let durationSeconds: Double
    public let fileSizeBytes: Int64
    public let elapsedMs: Double
}

public final class VideoExporter: @unchecked Sendable {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let cameraEngine = SpringCameraEngine()

    public init() {}

    public func exportMP4(
        project: ZoomCastProject,
        to outputURL: URL,
        outputSize: CGSize? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ExportResult {
        let startWall = CFAbsoluteTimeGetCurrent()
        let sourceURL = URL(fileURLWithPath: project.videoPath)
        let asset = AVURLAsset(url: sourceURL)

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw ExportError.missingVideoTrack
        }

        let cmDuration = try await asset.load(.duration)
        let totalDuration = max(0.1, CMTimeGetSeconds(cmDuration))

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let targetSize = outputSize ?? project.style.aspect.pixelSize
        let width = max(2, Int(targetSize.width) & ~1)
        let height = max(2, Int(targetSize.height) & ~1)

        let reader = try AVAssetReader(asset: asset)
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw ExportError.readerFailed("Cannot attach reader track output.")
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let bitRate = max(4_000_000, width * height * 6)
        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(writerInput) else {
            throw ExportError.writerFailed("Cannot attach writer video input.")
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "Unknown reader error")
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "Unknown writer error")
        }
        writer.startSession(atSourceTime: .zero)

        let compositor = VideoCompositor()
        var frameCount = 0

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                throw ExportError.cancelled
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = max(0.0, CMTimeGetSeconds(pts))

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let ok: Bool = autoreleasepool {
                guard let srcPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return false
                }
                let ciImage = CIImage(cvPixelBuffer: srcPixelBuffer)
                guard let srcCG = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                    return false
                }

                var outBuffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuffer) == kCVReturnSuccess,
                      let dstBuffer = outBuffer else {
                    return false
                }

                let cam = cameraEngine.evaluate(
                    at: seconds,
                    segments: project.zoomSegments,
                    cursorSamples: project.cursorSamples,
                    easing: project.style.easing
                )
                guard compositor.composeIntoPixelBuffer(
                    sourceFrame: srcCG,
                    style: project.style,
                    camera: cam,
                    pixelBuffer: dstBuffer
                ) else {
                    return false
                }

                return adaptor.append(dstBuffer, withPresentationTime: pts)
            }

            if !ok {
                throw ExportError.writerFailed(writer.error?.localizedDescription ?? "Frame append failed at \(seconds)s")
            }

            frameCount += 1
            if frameCount % 3 == 0 {
                progress?(min(0.99, seconds / totalDuration))
            }
        }

        if reader.status == .failed {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "Reader failed mid-stream")
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "Writer finish failed")
        }

        progress?(1.0)
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startWall) * 1000.0

        return ExportResult(
            outputURL: outputURL,
            frameCount: frameCount,
            durationSeconds: totalDuration,
            fileSizeBytes: fileSize,
            elapsedMs: elapsedMs
        )
    }

    /// Exports a smooth web-ready animated GIF at targetFPS (default 15 fps) and width (default 960 px).
    public func exportGIF(
        project: ZoomCastProject,
        to outputURL: URL,
        targetFPS: Double = 15.0,
        maxWidth: Double = 960.0,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ExportResult {
        let startWall = CFAbsoluteTimeGetCurrent()
        let sourceURL = URL(fileURLWithPath: project.videoPath)
        let asset = AVURLAsset(url: sourceURL)
        let cmDuration = try await asset.load(.duration)
        let totalDuration = max(0.1, CMTimeGetSeconds(cmDuration))

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let aspectSize = project.style.aspect.pixelSize
        let scale = min(1.0, maxWidth / aspectSize.width)
        let outSize = CGSize(
            width: max(2, Double(Int(aspectSize.width * scale) & ~1)),
            height: max(2, Double(Int(aspectSize.height * scale) & ~1))
        )

        let totalFrames = max(1, Int(ceil(totalDuration * targetFPS)))
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            totalFrames,
            nil
        ) else {
            throw ExportError.gifDestinationFailed
        }

        let gifProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.03, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.03, preferredTimescale: 600)

        let compositor = VideoCompositor()
        let delay = 1.0 / targetFPS
        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]
        ]

        var written = 0
        for i in 0..<totalFrames {
            if Task.isCancelled { throw ExportError.cancelled }
            let sec = min(totalDuration - 0.01, Double(i) / targetFPS)
            let cmTime = CMTime(seconds: sec, preferredTimescale: 600)

            let composed: CGImage? = autoreleasepool {
                guard let rawCG = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                    return nil
                }
                let cam = cameraEngine.evaluate(
                    at: sec,
                    segments: project.zoomSegments,
                    cursorSamples: project.cursorSamples,
                    easing: project.style.easing
                )
                return compositor.compose(sourceFrame: rawCG, style: project.style, camera: cam, outputSize: outSize)
            }

            if let img = composed {
                CGImageDestinationAddImage(dest, img, frameProps as CFDictionary)
                written += 1
            }

            if i % 3 == 0 {
                progress?(min(0.98, Double(i + 1) / Double(totalFrames)))
            }
        }

        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.gifDestinationFailed
        }

        progress?(1.0)
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startWall) * 1000.0

        return ExportResult(
            outputURL: outputURL,
            frameCount: written,
            durationSeconds: totalDuration,
            fileSizeBytes: fileSize,
            elapsedMs: elapsedMs
        )
    }
}
