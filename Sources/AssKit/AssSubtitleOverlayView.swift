#if canImport(UIKit)
import CoreGraphics
import Foundation
import UIKit

public final class AssSubtitleOverlayView: UIView {
    public let renderer: AssRenderer
    public var onPatch: ((AssBitmapPatch) -> Void)?

    private let surface = AssPixelSurface()
    private var lastPixelSize: CGSize = .zero

    public init(renderer: AssRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        commonInit()
    }

    public convenience init(configuration: AssRendererConfiguration = AssRendererConfiguration()) throws {
        try self.init(renderer: AssRenderer(configuration: configuration))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        return nil
    }

    public func loadASS(_ data: Data) throws {
        try renderer.loadASS(data)
        clear()
    }

    @discardableResult
    public func render(at time: TimeInterval) throws -> Bool {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let pixelWidth = Int(max(1, (bounds.width * scale).rounded()))
        let pixelHeight = Int(max(1, (bounds.height * scale).rounded()))
        let pixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        if pixelSize != lastPixelSize {
            surface.reset(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
            lastPixelSize = pixelSize
        }

        let output = try renderer.render(
            AssRenderRequest(time: time, viewportSize: bounds.size, scale: scale)
        )
        guard case let .changed(patch) = output else {
            return false
        }

        surface.apply(patch)
        layer.contents = surface.makeCGImage()
        onPatch?(patch)
        return true
    }

    public func clear() {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        surface.reset(
            pixelWidth: Int(max(1, (bounds.width * scale).rounded())),
            pixelHeight: Int(max(1, (bounds.height * scale).rounded()))
        )
        layer.contents = nil
        lastPixelSize = .zero
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
    }
}
#endif
