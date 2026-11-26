import Foundation

public struct SpringCameraEngine: Sendable {
    public init() {}

    /// Smooth spring-inspired easing curve (0 -> 1) with gentle settle.
    public static func ease(_ t: Double, style: ZoomEasing) -> Double {
        let clamped = min(max(t, 0.0), 1.0)
        switch style {
        case .springSmooth:
            // Quintic smoothstep for silky camera motion without harsh acceleration
            return clamped * clamped * clamped * (clamped * (clamped * 6.0 - 15.0) + 10.0)
        case .snappy:
            // Fast cubic out
            let inv = 1.0 - clamped
            return 1.0 - inv * inv * inv
        case .gentle:
            // Cosine S-curve
            return 0.5 - 0.5 * cos(clamped * .pi)
        }
    }

    /// Evaluates camera zoom, focus, cursor position, and active click ripple at a given timestamp.
    public func evaluate(
        at time: Double,
        segments: [ZoomSegment],
        cursorSamples: [CursorSample],
        easing: ZoomEasing
    ) -> CameraState {
        let transition = easing.transitionDuration
        var bestScale = 1.0
        var bestFocus = NormalizedPoint.center

        let sorted = segments.sorted { $0.startTime < $1.startTime }
        for seg in sorted {
            let fadeInStart = seg.startTime
            let fadeInEnd = min(seg.startTime + transition, seg.startTime + seg.duration * 0.45)
            let fadeOutStart = max(seg.endTime - transition, seg.startTime + seg.duration * 0.55)
            let fadeOutEnd = seg.endTime

            guard time >= fadeInStart && time <= fadeOutEnd else { continue }

            let weight: Double
            if time < fadeInEnd && fadeInEnd > fadeInStart {
                weight = Self.ease((time - fadeInStart) / (fadeInEnd - fadeInStart), style: easing)
            } else if time > fadeOutStart && fadeOutEnd > fadeOutStart {
                weight = 1.0 - Self.ease((time - fadeOutStart) / (fadeOutEnd - fadeOutStart), style: easing)
            } else {
                weight = 1.0
            }

            let currentScale = 1.0 + (seg.scale - 1.0) * weight
            if currentScale > bestScale {
                bestScale = currentScale
                let fx = 0.5 + (seg.focus.x - 0.5) * weight
                let fy = 0.5 + (seg.focus.y - 0.5) * weight
                bestFocus = NormalizedPoint(x: fx, y: fy)
            }
        }

        let cursorPos = interpolateCursor(at: time, samples: cursorSamples)
        let (rippleProgress, ripplePos) = evaluateClickRipple(at: time, samples: cursorSamples)

        return CameraState(
            scale: bestScale,
            focus: bestFocus,
            cursorPosition: cursorPos,
            clickRippleProgress: rippleProgress,
            clickRipplePosition: ripplePos
        )
    }

    /// Automatically generates non-overlapping ZoomSegments from recorded click events.
    public func autoGenerateZoomSegments(
        from cursorSamples: [CursorSample],
        duration: Double,
        defaultScale: Double = 2.0,
        leadIn: Double = 0.30,
        holdDuration: Double = 1.45,
        mergeThreshold: Double = 1.10
    ) -> [ZoomSegment] {
        let clicks = cursorSamples
            .filter(\.isClick)
            .sorted { $0.time < $1.time }

        guard !clicks.isEmpty else { return [] }

        var segments: [ZoomSegment] = []
        var idx = 1

        for click in clicks {
            let proposedStart = max(0.0, click.time - leadIn)
            let proposedEnd = min(duration, click.time + holdDuration)

            if var last = segments.last, proposedStart <= last.endTime + mergeThreshold {
                // Extend existing segment and smoothly average focus toward new click
                last.endTime = max(last.endTime, proposedEnd)
                last.focus = NormalizedPoint(
                    x: (last.focus.x + click.position.x) * 0.5,
                    y: (last.focus.y + click.position.y) * 0.5
                )
                segments[segments.count - 1] = last
            } else {
                segments.append(
                    ZoomSegment(
                        startTime: proposedStart,
                        endTime: max(proposedStart + 0.5, proposedEnd),
                        scale: defaultScale,
                        focus: click.position,
                        label: "Click Zoom #\(idx)"
                    )
                )
                idx += 1
            }
        }

        return segments
    }

    /// Computes normalized crop rect inside a source frame [0..1] for a given camera state,
    /// clamped so the crop never extends outside the source frame.
    public static func normalizedCropRect(scale: Double, focus: NormalizedPoint) -> CGRect {
        let s = max(1.0, scale)
        let cropW = 1.0 / s
        let cropH = 1.0 / s
        var originX = focus.x - cropW * 0.5
        var originY = focus.y - cropH * 0.5
        originX = min(max(originX, 0.0), 1.0 - cropW)
        originY = min(max(originY, 0.0), 1.0 - cropH)
        return CGRect(x: originX, y: originY, width: cropW, height: cropH)
    }

    private func interpolateCursor(at time: Double, samples: [CursorSample]) -> NormalizedPoint? {
        guard !samples.isEmpty else { return nil }
        if samples.count == 1 { return samples[0].position }

        // Samples are assumed sorted by time; handle edge bounds fast
        if time <= samples[0].time { return samples[0].position }
        if time >= samples[samples.count - 1].time { return samples[samples.count - 1].position }

        // Binary search for surrounding samples
        var lo = 0
        var hi = samples.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let a = samples[lo]
        let b = samples[hi]
        let dt = b.time - a.time
        guard dt > 1e-6 else { return a.position }
        let frac = (time - a.time) / dt
        return NormalizedPoint(
            x: a.position.x + (b.position.x - a.position.x) * frac,
            y: a.position.y + (b.position.y - a.position.y) * frac
        )
    }

    private func evaluateClickRipple(at time: Double, samples: [CursorSample]) -> (Double?, NormalizedPoint?) {
        let rippleDuration = 0.45
        for sample in samples.reversed() where sample.isClick {
            let dt = time - sample.time
            if dt >= 0 && dt <= rippleDuration {
                return (dt / rippleDuration, sample.position)
            }
        }
        return (nil, nil)
    }
}
