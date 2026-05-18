import CoreGraphics
import Foundation

public enum AssKitError: Error, Sendable {
    case rendererCreationFailed
    case invalidFrameSize
    case invalidSubtitleData
    case renderFailed(Int32)
}

public struct AssRendererConfiguration: Sendable {
    public var defaultFontPath: String?
    public var defaultFontFamily: String

    public init(defaultFontPath: String? = nil, defaultFontFamily: String = "Helvetica") {
        self.defaultFontPath = defaultFontPath
        self.defaultFontFamily = defaultFontFamily
    }
}

public struct AssRenderRequest: Sendable {
    public var time: TimeInterval
    public var viewportSize: CGSize
    public var scale: CGFloat

    public init(time: TimeInterval, viewportSize: CGSize, scale: CGFloat = 1) {
        self.time = time
        self.viewportSize = viewportSize
        self.scale = scale
    }
}

public struct AssEmbeddedTrack: Sendable {
    public var header: Data
    public var usesReadOrder: Bool

    public init(header: Data, usesReadOrder: Bool = true) {
        self.header = header
        self.usesReadOrder = usesReadOrder
    }
}

public struct AssEmbeddedEvent: Sendable {
    public var payload: Data
    public var startTime: TimeInterval
    public var duration: TimeInterval

    public init(payload: Data, startTime: TimeInterval, duration: TimeInterval) {
        self.payload = payload
        self.startTime = startTime
        self.duration = duration
    }

    public init(text: String, startTime: TimeInterval, duration: TimeInterval) {
        self.init(payload: Data(text.utf8), startTime: startTime, duration: duration)
    }
}

public extension AssEmbeddedTrack {
    static func ffmpegCodecPrivate(_ data: Data, usesReadOrder: Bool = true) -> Self {
        Self(header: data, usesReadOrder: usesReadOrder)
    }
}

public extension AssEmbeddedEvent {
    static func ffmpegASSRect(_ ass: String, startTime: TimeInterval, duration: TimeInterval) -> Self {
        Self(text: ass, startTime: startTime, duration: duration)
    }

    static func ffmpegASSRect(_ data: Data, startTime: TimeInterval, duration: TimeInterval) -> Self {
        Self(payload: data, startTime: startTime, duration: duration)
    }
}

public enum AssPixelFormat: Sendable {
    case premultipliedBGRA8
}

public struct AssBitmapPatch: Sendable {
    public let rect: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let bytesPerRow: Int
    public let format: AssPixelFormat
    public let data: Data

    public init(
        rect: CGRect,
        pixelWidth: Int,
        pixelHeight: Int,
        bytesPerRow: Int,
        format: AssPixelFormat = .premultipliedBGRA8,
        data: Data
    ) {
        self.rect = rect
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.format = format
        self.data = data
    }
}

public enum AssRenderOutput: Sendable {
    case unchanged
    case changed(AssBitmapPatch)

    public var patch: AssBitmapPatch? {
        guard case let .changed(patch) = self else {
            return nil
        }
        return patch
    }
}

public protocol AssRendering: AnyObject {
    func loadASS(_ data: Data) throws
    func loadEmbeddedTrack(_ track: AssEmbeddedTrack) throws
    func appendEmbeddedEvent(_ event: AssEmbeddedEvent) throws
    func pruneEvents(before time: TimeInterval) throws
    func flush() throws
    func render(_ request: AssRenderRequest) throws -> AssRenderOutput
}
