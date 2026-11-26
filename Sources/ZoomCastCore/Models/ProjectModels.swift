import CoreGraphics
import Foundation

public struct NormalizedPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0.0), 1.0)
        self.y = min(max(y, 0.0), 1.0)
    }

    public static let center = NormalizedPoint(x: 0.5, y: 0.5)
}

public struct CursorSample: Codable, Equatable, Sendable {
    public var time: Double
    public var position: NormalizedPoint
    public var isClick: Bool

    public init(time: Double, position: NormalizedPoint, isClick: Bool = false) {
        self.time = max(0, time)
        self.position = position
        self.isClick = isClick
    }
}

public enum ZoomEasing: String, Codable, CaseIterable, Identifiable, Sendable {
    case springSmooth = "Spring Smooth"
    case snappy = "Snappy"
    case gentle = "Gentle"

    public var id: String { rawValue }

    public var transitionDuration: Double {
        switch self {
        case .springSmooth: return 0.42
        case .snappy: return 0.24
        case .gentle: return 0.65
        }
    }
}

public struct ZoomSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startTime: Double
    public var endTime: Double
    public var scale: Double
    public var focus: NormalizedPoint
    public var label: String

    public init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        scale: Double = 2.0,
        focus: NormalizedPoint = .center,
        label: String = "Auto Zoom"
    ) {
        self.id = id
        self.startTime = max(0, startTime)
        self.endTime = max(self.startTime + 0.3, endTime)
        self.scale = min(max(scale, 1.05), 3.5)
        self.focus = focus
        self.label = label
    }

    public var duration: Double { endTime - startTime }
}

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
    }
}

public struct BackgroundPreset: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var topLeading: RGBAColor
    public var bottomTrailing: RGBAColor
    public var accentGlow: RGBAColor

    public init(
        id: String,
        name: String,
        topLeading: RGBAColor,
        bottomTrailing: RGBAColor,
        accentGlow: RGBAColor
    ) {
        self.id = id
        self.name = name
        self.topLeading = topLeading
        self.bottomTrailing = bottomTrailing
        self.accentGlow = accentGlow
    }

    public static let allPresets: [BackgroundPreset] = [
        BackgroundPreset(
            id: "midnight-indigo",
            name: "Midnight Indigo",
            topLeading: RGBAColor(r: 0.08, g: 0.11, b: 0.28),
            bottomTrailing: RGBAColor(r: 0.24, g: 0.11, b: 0.39),
            accentGlow: RGBAColor(r: 0.31, g: 0.45, b: 0.98, a: 0.45)
        ),
        BackgroundPreset(
            id: "sunset-coral",
            name: "Sunset Coral",
            topLeading: RGBAColor(r: 0.94, g: 0.38, b: 0.36),
            bottomTrailing: RGBAColor(r: 0.45, g: 0.18, b: 0.56),
            accentGlow: RGBAColor(r: 1.0, g: 0.72, b: 0.38, a: 0.42)
        ),
        BackgroundPreset(
            id: "emerald-aurora",
            name: "Emerald Aurora",
            topLeading: RGBAColor(r: 0.05, g: 0.28, b: 0.33),
            bottomTrailing: RGBAColor(r: 0.07, g: 0.14, b: 0.24),
            accentGlow: RGBAColor(r: 0.16, g: 0.82, b: 0.62, a: 0.38)
        ),
        BackgroundPreset(
            id: "ocean-glass",
            name: "Ocean Glass",
            topLeading: RGBAColor(r: 0.07, g: 0.32, b: 0.68),
            bottomTrailing: RGBAColor(r: 0.04, g: 0.12, b: 0.28),
            accentGlow: RGBAColor(r: 0.28, g: 0.78, b: 1.0, a: 0.40)
        ),
        BackgroundPreset(
            id: "cyber-violet",
            name: "Cyber Violet",
            topLeading: RGBAColor(r: 0.38, g: 0.14, b: 0.74),
            bottomTrailing: RGBAColor(r: 0.12, g: 0.07, b: 0.25),
            accentGlow: RGBAColor(r: 0.92, g: 0.32, b: 0.78, a: 0.42)
        ),
        BackgroundPreset(
            id: "warm-sand",
            name: "Warm Sand",
            topLeading: RGBAColor(r: 0.91, g: 0.79, b: 0.66),
            bottomTrailing: RGBAColor(r: 0.71, g: 0.56, b: 0.49),
            accentGlow: RGBAColor(r: 1.0, g: 0.92, b: 0.80, a: 0.35)
        ),
        BackgroundPreset(
            id: "graphite",
            name: "Graphite",
            topLeading: RGBAColor(r: 0.16, g: 0.17, b: 0.20),
            bottomTrailing: RGBAColor(r: 0.09, g: 0.10, b: 0.12),
            accentGlow: RGBAColor(r: 0.45, g: 0.48, b: 0.55, a: 0.22)
        ),
        BackgroundPreset(
            id: "pure-obsidian",
            name: "Obsidian",
            topLeading: RGBAColor(r: 0.04, g: 0.05, b: 0.07),
            bottomTrailing: RGBAColor(r: 0.02, g: 0.02, b: 0.03),
            accentGlow: RGBAColor(r: 0.18, g: 0.22, b: 0.30, a: 0.20)
        )
    ]

    public static func find(_ id: String) -> BackgroundPreset {
        allPresets.first(where: { $0.id == id }) ?? allPresets[0]
    }
}

public enum AspectPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case landscape16x9 = "16:9 (1080p)"
    case landscape4K = "16:9 (1440p)"
    case square1x1 = "1:1 (Square)"
    case vertical9x16 = "9:16 (Vertical)"

    public var id: String { rawValue }

    public var pixelSize: CGSize {
        switch self {
        case .landscape16x9: return CGSize(width: 1920, height: 1080)
        case .landscape4K: return CGSize(width: 2560, height: 1440)
        case .square1x1: return CGSize(width: 1080, height: 1080)
        case .vertical9x16: return CGSize(width: 1080, height: 1920)
        }
    }

    public var shortLabel: String {
        switch self {
        case .landscape16x9: return "16:9"
        case .landscape4K: return "1440p"
        case .square1x1: return "1:1"
        case .vertical9x16: return "9:16"
        }
    }
}

public enum ExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4H264 = "MP4 (H.264)"
    case gif = "Animated GIF"

    public var id: String { rawValue }
}

public struct CanvasStyle: Codable, Equatable, Sendable {
    public var backgroundID: String
    public var padding: Double
    public var cornerRadius: Double
    public var shadowIntensity: Double
    public var aspect: AspectPreset
    public var easing: ZoomEasing
    public var showCursorHighlight: Bool
    public var showClickRipples: Bool

    public init(
        backgroundID: String = "midnight-indigo",
        padding: Double = 72,
        cornerRadius: Double = 18,
        shadowIntensity: Double = 0.65,
        aspect: AspectPreset = .landscape16x9,
        easing: ZoomEasing = .springSmooth,
        showCursorHighlight: Bool = true,
        showClickRipples: Bool = true
    ) {
        self.backgroundID = backgroundID
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowIntensity = shadowIntensity
        self.aspect = aspect
        self.easing = easing
        self.showCursorHighlight = showCursorHighlight
        self.showClickRipples = showClickRipples
    }

    public var background: BackgroundPreset {
        BackgroundPreset.find(backgroundID)
    }
}

public struct ZoomCastProject: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var videoPath: String
    public var duration: Double
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var fps: Double
    public var style: CanvasStyle
    public var zoomSegments: [ZoomSegment]
    public var cursorSamples: [CursorSample]

    public init(
        id: UUID = UUID(),
        title: String,
        videoPath: String,
        duration: Double,
        sourceWidth: Int,
        sourceHeight: Int,
        fps: Double = 30.0,
        style: CanvasStyle = CanvasStyle(),
        zoomSegments: [ZoomSegment] = [],
        cursorSamples: [CursorSample] = []
    ) {
        self.id = id
        self.title = title
        self.videoPath = videoPath
        self.duration = max(0.1, duration)
        self.sourceWidth = max(1, sourceWidth)
        self.sourceHeight = max(1, sourceHeight)
        self.fps = max(1.0, fps)
        self.style = style
        self.zoomSegments = zoomSegments
        self.cursorSamples = cursorSamples
    }

    public var clickEvents: [CursorSample] {
        cursorSamples.filter(\.isClick)
    }
}

public struct CameraState: Equatable, Sendable {
    public var scale: Double
    public var focus: NormalizedPoint
    public var cursorPosition: NormalizedPoint?
    public var clickRippleProgress: Double? // 0.0 .. 1.0 when a click recently occurred
    public var clickRipplePosition: NormalizedPoint?

    public init(
        scale: Double = 1.0,
        focus: NormalizedPoint = .center,
        cursorPosition: NormalizedPoint? = nil,
        clickRippleProgress: Double? = nil,
        clickRipplePosition: NormalizedPoint? = nil
    ) {
        self.scale = scale
        self.focus = focus
        self.cursorPosition = cursorPosition
        self.clickRippleProgress = clickRippleProgress
        self.clickRipplePosition = clickRipplePosition
    }
}
