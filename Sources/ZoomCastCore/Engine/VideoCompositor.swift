import CoreGraphics
import CoreVideo
import Foundation

public final class VideoCompositor: @unchecked Sendable {
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var cachedBackgroundKey: String = ""
    private var cachedBackground: CGImage?

    public init() {}

    /// Renders a single studio-framed output CGImage from a raw source video frame.
    public func compose(
        sourceFrame: CGImage,
        style: CanvasStyle,
        camera: CameraState,
        outputSize: CGSize? = nil
    ) -> CGImage? {
        let targetSize = outputSize ?? style.aspect.pixelSize
        let width = max(2, Int(targetSize.width))
        let height = max(2, Int(targetSize.height))

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        drawFrame(into: ctx, width: width, height: height, sourceFrame: sourceFrame, style: style, camera: camera)
        return ctx.makeImage()
    }

    /// Renders directly into a CVPixelBuffer (BGRA) for zero-extra-copy AVAssetWriter export.
    public func composeIntoPixelBuffer(
        sourceFrame: CGImage,
        style: CanvasStyle,
        camera: CameraState,
        pixelBuffer: CVPixelBuffer
    ) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }

        guard let ctx = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return false
        }

        drawFrame(into: ctx, width: width, height: height, sourceFrame: sourceFrame, style: style, camera: camera)
        return true
    }

    private func drawFrame(
        into ctx: CGContext,
        width: Int,
        height: Int,
        sourceFrame: CGImage,
        style: CanvasStyle,
        camera: CameraState
    ) {
        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.interpolationQuality = .high

        // 1. Studio gradient background (cached)
        if let bg = backgroundImage(for: style.background, width: width, height: height) {
            ctx.draw(bg, in: canvasRect)
        } else {
            ctx.setFillColor(style.background.topLeading.cgColor)
            ctx.fill(canvasRect)
        }

        // 2. Compute fitted video frame rect inside padded canvas
        let scaleFactor = Double(width) / 1920.0
        let pad = style.padding * scaleFactor
        let availW = max(16.0, Double(width) - pad * 2.0)
        let availH = max(16.0, Double(height) - pad * 2.0)

        let srcW = Double(sourceFrame.width)
        let srcH = Double(sourceFrame.height)
        let srcAspect = srcW / max(1.0, srcH)
        let availAspect = availW / max(1.0, availH)

        let frameW: Double
        let frameH: Double
        if srcAspect > availAspect {
            frameW = availW
            frameH = availW / srcAspect
        } else {
            frameH = availH
            frameW = availH * srcAspect
        }

        let frameRect = CGRect(
            x: (Double(width) - frameW) * 0.5,
            y: (Double(height) - frameH) * 0.5,
            width: frameW,
            height: frameH
        )

        let radius = CGFloat(style.cornerRadius * scaleFactor)
        let roundedPath = CGPath(roundedRect: frameRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // 3. Soft studio drop shadow behind the video card
        if style.shadowIntensity > 0.01 {
            ctx.saveGState()
            let blur = CGFloat(42.0 * style.shadowIntensity * scaleFactor)
            let shadowOffset = CGSize(width: 0, height: -CGFloat(18.0 * scaleFactor))
            let shadowColor = CGColor(colorSpace: colorSpace, components: [0, 0, 0, min(0.72, style.shadowIntensity * 0.78)])!
            ctx.setShadow(offset: shadowOffset, blur: blur, color: shadowColor)
            ctx.addPath(roundedPath)
            ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.05, 0.05, 0.08, 1.0])!)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 4. Compute camera zoom crop rect (top-left normalized -> CGImage crop pixels)
        let normCrop = SpringCameraEngine.normalizedCropRect(scale: camera.scale, focus: camera.focus)
        let cropPixelRect = CGRect(
            x: normCrop.origin.x * srcW,
            y: normCrop.origin.y * srcH,
            width: normCrop.width * srcW,
            height: normCrop.height * srcH
        ).integral

        let croppedImage = sourceFrame.cropping(to: cropPixelRect) ?? sourceFrame

        // 5. Clip to rounded rect and draw zoomed frame
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.clip()
        ctx.draw(croppedImage, in: frameRect)

        // 6. Optional cursor highlight & click ripple mapped through the active camera crop
        if style.showClickRipples,
           let progress = camera.clickRippleProgress,
           let ripplePos = camera.clickRipplePosition {
            if let pt = mapNormalizedToCanvas(ripplePos, crop: normCrop, frameRect: frameRect) {
                let maxR = CGFloat(38.0 * scaleFactor * max(1.0, camera.scale * 0.65))
                let r = maxR * CGFloat(0.25 + 0.75 * progress)
                let alpha = CGFloat(max(0.0, 1.0 - progress)) * 0.85
                ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [1.0, 0.78, 0.22, alpha])!)
                ctx.setLineWidth(CGFloat(3.5 * scaleFactor))
                ctx.strokeEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            }
        }

        if style.showCursorHighlight, let cursorPos = camera.cursorPosition {
            if let pt = mapNormalizedToCanvas(cursorPos, crop: normCrop, frameRect: frameRect) {
                let haloR = CGFloat(14.0 * scaleFactor)
                ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.35, 0.72, 1.0, 0.28])!)
                ctx.fillEllipse(in: CGRect(x: pt.x - haloR, y: pt.y - haloR, width: haloR * 2, height: haloR * 2))

                // Crisp macOS-style pointer dot with white outline
                let dotR = CGFloat(5.5 * scaleFactor)
                ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.96])!)
                ctx.fillEllipse(in: CGRect(x: pt.x - dotR - 1.5, y: pt.y - dotR - 1.5, width: (dotR + 1.5) * 2, height: (dotR + 1.5) * 2))
                ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.10, 0.12, 0.18, 0.96])!)
                ctx.fillEllipse(in: CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR * 2, height: dotR * 2))
            }
        }

        ctx.restoreGState()

        // 7. Subtle 1px specular border around video card
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.16])!)
        ctx.setLineWidth(max(1.0, CGFloat(1.2 * scaleFactor)))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func mapNormalizedToCanvas(
        _ pos: NormalizedPoint,
        crop: CGRect,
        frameRect: CGRect
    ) -> CGPoint? {
        guard crop.width > 1e-6, crop.height > 1e-6 else { return nil }
        let localX = (pos.x - crop.origin.x) / crop.width
        let localY = (pos.y - crop.origin.y) / crop.height
        guard localX >= -0.05 && localX <= 1.05 && localY >= -0.05 && localY <= 1.05 else {
            return nil
        }
        // CoreGraphics origin is bottom-left, NormalizedPoint origin is top-left
        return CGPoint(
            x: frameRect.origin.x + localX * frameRect.width,
            y: frameRect.origin.y + (1.0 - localY) * frameRect.height
        )
    }

    private func backgroundImage(for preset: BackgroundPreset, width: Int, height: Int) -> CGImage? {
        let key = "\(preset.id)-\(width)x\(height)"
        if key == cachedBackgroundKey, let img = cachedBackground {
            return img
        }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        let colors = [preset.topLeading.cgColor, preset.bottomTrailing.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(height)),
                end: CGPoint(x: CGFloat(width), y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Soft radial studio accent glow
        let glowColors = [
            preset.accentGlow.cgColor,
            CGColor(colorSpace: colorSpace, components: [preset.accentGlow.r, preset.accentGlow.g, preset.accentGlow.b, 0.0])!
        ] as CFArray
        if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
            let center = CGPoint(x: CGFloat(width) * 0.22, y: CGFloat(height) * 0.80)
            ctx.drawRadialGradient(
                radial,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: CGFloat(max(width, height)) * 0.65,
                options: []
            )
        }

        let img = ctx.makeImage()
        cachedBackgroundKey = key
        cachedBackground = img
        return img
    }
}
