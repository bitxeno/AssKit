# AssKit Public API

This document describes the stable Swift-facing API surface.

## Renderer

```swift
public protocol AssRendering: AnyObject {
    func loadASS(_ data: Data) throws
    func loadTrack(_ track: AssTrack) throws
    func appendEvent(_ event: AssEvent) throws
    func pruneEvents(before time: TimeInterval) throws
    func flush() throws
    func render(_ request: AssRenderRequest) throws -> AssRenderOutput
}
```

`AssRenderer` is the default libass implementation.

## FFmpeg Embedded ASS

Use this path for ASS/SSA subtitles embedded in containers and decoded by FFmpeg.

```swift
let renderer = try AssRenderer()

try renderer.loadTrack(
    .track(codecPrivateData)
)

try renderer.appendEvent(
    .AssRect(
        eventData,
        startTime: subtitleStartSeconds,
        duration: subtitleDurationSeconds
    )
)

let output = try renderer.render(
    AssRenderRequest(time: playbackTime, viewportSize: overlaySize, scale: displayScale)
)
```

For long-running playback, prune old events after they are no longer needed:

```swift
try renderer.pruneEvents(before: playbackTime - 30)
```

The chunk format is libass/Matroska ASS event format: `ReadOrder, Layer, Style, Name, MarginL, MarginR, MarginV, Effect, Text`. FFmpeg's ASS decoded text normally matches this shape.

## Render Request

```swift
public struct AssRenderRequest: Sendable {
    public var time: TimeInterval
    public var viewportSize: CGSize
    public var scale: CGFloat
}
```

- `time`: presentation timestamp in seconds
- `viewportSize`: player overlay size in points
- `scale`: display scale used to create the pixel buffer

## Render Output

```swift
public enum AssRenderOutput: Sendable {
    case unchanged
    case changed(AssBitmapPatch)
}
```

Callers should skip texture/view updates for `.unchanged`.

## Bitmap Patch

```swift
public struct AssBitmapPatch: Sendable {
    public let rect: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let bytesPerRow: Int
    public let format: AssPixelFormat
    public let data: Data
}
```

`data` uses premultiplied BGRA8 byte order. `rect` is in view points; `pixelWidth` and `pixelHeight` are the exact patch dimensions in pixels.

## Overlay Components

UIKit:

```swift
public final class AssSubtitleOverlayView: UIView {
    public let renderer: AssRenderer
    public var onPatch: ((AssBitmapPatch) -> Void)?
    public func loadASS(_ data: Data) throws
    @discardableResult public func render(at time: TimeInterval) throws -> Bool
    public func clear()
}
```

SwiftUI:

```swift
public struct AssSubtitleOverlay: UIViewRepresentable {
    public init(
        subtitleData: Data,
        time: TimeInterval,
        configuration: AssRendererConfiguration = AssRendererConfiguration()
    )
}
```
