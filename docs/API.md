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

Font lookup can be customized through `AssRendererConfiguration` during initialization,
or later with `AssRenderer.setFontsDirectory(_:)` and `AssRenderer.configureFonts(_:)`.

In-memory fonts (such as fonts attached to an MKV file) can be added with
`AssRenderer.addFont(named:data:)` and `AssRenderer.addFonts(_:)`, and removed
again with `AssRenderer.clearFonts()`.

## FFmpeg Embedded ASS

Use this path for ASS/SSA subtitles embedded in containers and decoded by FFmpeg.

```swift
let renderer = try AssRenderer(
    configuration: AssRendererConfiguration(
        defaultFontFamily: "Helvetica",
        fontsDirectoryPath: customFontsDirectory.path
    )
)

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

If you need to update the extra font search path later:

```swift
renderer.setFontsDirectory(customFontsDirectory.path)
```

### Memory Font Injection (MKV Attachments)

Matroska/MKV files commonly ship subtitle fonts as attachments. Demux the
attachment name and bytes, then add them before rendering so libass can
resolve embedded font names without touching the filesystem:

```swift
let renderer = try AssRenderer()

for attachment in container.fontAttachments {
    try renderer.addFont(
        named: attachment.fileName, // e.g. "SourceHanSansSC-Regular.otf"
        data: attachment.data
    )
}

// Or add everything in one call:
try renderer.addFonts(
    container.fontAttachments.map { AssMemoryFont(name: $0.fileName, data: $0.data) }
)

try renderer.loadTrack(.track(codecPrivateData))
```

Notes:

- `name` should be the original attachment file name, because libass uses it
  to match family names declared by the subtitle script.
- Fonts live inside libass' own storage (the data is copied); release
  `Data` buffers freely afterwards.
- `clearFonts()` removes all previously added fonts. Because libass only
  permits clearing its font store once every associated track and renderer is
  released, the call also discards loaded subtitle data; reload subtitles
  with `loadASS`/`loadTrack` afterwards.

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
