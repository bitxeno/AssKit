#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

public struct AssSubtitleOverlay: UIViewRepresentable {
    public let subtitleData: Data
    public var time: TimeInterval
    public var configuration: AssRendererConfiguration

    public init(
        subtitleData: Data,
        time: TimeInterval,
        configuration: AssRendererConfiguration = AssRendererConfiguration()
    ) {
        self.subtitleData = subtitleData
        self.time = time
        self.configuration = configuration
    }

    public func makeUIView(context: Context) -> AssSubtitleOverlayView {
        do {
            let view = try AssSubtitleOverlayView(configuration: configuration)
            try view.loadASS(subtitleData)
            return view
        } catch {
            return AssSubtitleOverlayView(renderer: context.coordinator.fallbackRenderer)
        }
    }

    public func updateUIView(_ uiView: AssSubtitleOverlayView, context: Context) {
        try? uiView.render(at: time)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        let fallbackRenderer: AssRenderer

        init() {
            self.fallbackRenderer = try! AssRenderer()
        }
    }
}
#endif
