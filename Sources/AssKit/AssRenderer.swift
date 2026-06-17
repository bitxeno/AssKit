import CAssKit
import CoreGraphics
import Foundation

public final class AssRenderer: AssRendering {
    private let handle: OpaquePointer
    private var framePixelSize: CGSize = .zero

    public init(configuration: AssRendererConfiguration = AssRendererConfiguration()) throws {
        guard let handle = asskit_renderer_create() else {
            throw AssKitError.rendererCreationFailed
        }
        self.handle = handle
        setFonts(configuration)
    }

    deinit {
        asskit_renderer_destroy(handle)
    }

    public func loadASS(_ data: Data) throws {
        let status = data.withUnsafeBytes { rawBuffer in
            asskit_renderer_load_ass(
                handle,
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                data.count
            )
        }
        guard status == 0 else {
            throw AssKitError.invalidSubtitleData
        }
    }

    public func loadTrack(_ track: AssTrack) throws {
        let status = track.header.withUnsafeBytes { rawBuffer in
            asskit_renderer_load_codec_private(
                handle,
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                track.header.count,
                track.usesReadOrder ? 1 : 0
            )
        }
        guard status == 0 else {
            throw AssKitError.invalidSubtitleData
        }
    }

    public func appendEvent(_ event: AssEvent) throws {
        let startMS = Int64((event.startTime * 1000).rounded())
        let durationMS = Int64((event.duration * 1000).rounded())
        let status = event.payload.withUnsafeBytes { rawBuffer in
            asskit_renderer_process_chunk(
                handle,
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                event.payload.count,
                startMS,
                durationMS
            )
        }
        guard status == 0 else {
            throw AssKitError.invalidSubtitleData
        }
    }

    public func appendEvent(_ text: String, startTime: TimeInterval, duration: TimeInterval) throws {
        try appendEvent(AssEvent(text: text, startTime: startTime, duration: duration))
    }

    public func pruneEvents(before time: TimeInterval) throws {
        let status = asskit_renderer_prune_events(handle, Int64((time * 1000).rounded()))
        guard status == 0 else {
            throw AssKitError.renderFailed(status)
        }
    }

    public func loadTrack(_ header: Data, checkReadOrder: Bool = true) throws {
        try loadTrack(.track(header, usesReadOrder: checkReadOrder))
    }

    public func flush() throws {
        let status = asskit_renderer_flush_track(handle)
        guard status == 0 else {
            throw AssKitError.renderFailed(status)
        }
    }

    public func render(_ request: AssRenderRequest) throws -> AssRenderOutput {
        try updateFrameSizeIfNeeded(request)

        let timeMS = Int64((request.time * 1000).rounded())
        let result = asskit_renderer_render(handle, timeMS)
        defer { asskit_render_result_free(result) }

        if result.changed == 0 {
            return .unchanged
        }
        guard result.changed > 0 else {
            throw AssKitError.renderFailed(result.changed)
        }
        guard let bgra = result.bgra, result.bgra_count > 0 else {
            return .changed(
                AssBitmapPatch(
                    rect: .zero,
                    pixelWidth: 0,
                    pixelHeight: 0,
                    bytesPerRow: 0,
                    data: Data()
                )
            )
        }

        let scale = max(request.scale, 1)
        let rect = CGRect(
            x: CGFloat(result.dirty_x) / scale,
            y: CGFloat(result.dirty_y) / scale,
            width: CGFloat(result.dirty_width) / scale,
            height: CGFloat(result.dirty_height) / scale
        )
        let patch = AssBitmapPatch(
            rect: rect,
            pixelWidth: Int(result.dirty_width),
            pixelHeight: Int(result.dirty_height),
            bytesPerRow: Int(result.bytes_per_row),
            data: Data(bytes: bgra, count: Int(result.bgra_count))
        )
        return .changed(patch)
    }

    private func setFonts(_ configuration: AssRendererConfiguration) {
        configuration.defaultFontPath.withCStringOrNil { fontPath in
            configuration.defaultFontFamily.withCString { family in
                asskit_renderer_set_fonts(handle, fontPath, family)
            }
        }
    }

    private func updateFrameSizeIfNeeded(_ request: AssRenderRequest) throws {
        let scale = max(request.scale, 1)
        let width = Int32(max(1, (request.viewportSize.width * scale).rounded()))
        let height = Int32(max(1, (request.viewportSize.height * scale).rounded()))
        let nextSize = CGSize(width: Int(width), height: Int(height))
        guard nextSize != framePixelSize else {
            return
        }

        let status = asskit_renderer_set_frame_size(handle, width, height)
        guard status == 0 else {
            throw AssKitError.invalidFrameSize
        }
        framePixelSize = nextSize
    }
}

private extension Optional where Wrapped == String {
    func withCStringOrNil<R>(_ body: (UnsafePointer<CChar>?) throws -> R) rethrows -> R {
        switch self {
        case .some(let string):
            return try string.withCString(body)
        case .none:
            return try body(nil)
        }
    }
}
