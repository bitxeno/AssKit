# AssKit

AssKit is a Swift Package for rendering ASS/SSA subtitles on Apple platforms with libass. It follows the package shape used by FFmpegBuild: local binary XCFramework targets for libass and its dependencies, plus a small Swift API that app code can use directly.

## Features

- SPM product: `AssKit`
- C bridge over libass for stable Swift interop
- Incremental rendering API: unchanged subtitle frames return `.unchanged`
- Dirty-rect BGRA patches for changed subtitle pixels
- UIKit overlay view for player overlays
- SwiftUI wrapper for UIKit-based overlays
- Build scripts for libass, libunibreak, freetype, fribidi, and harfbuzz XCFrameworks

## Installation

Add this repository as a Swift Package dependency, then import:

```swift
import AssKit
```

`Package.swift` uses local binary targets under `Vendor/*.xcframework`. No remote binary target is referenced by the package.

## Build XCFrameworks

```bash
./build.sh
./build.sh platform=ios
./build.sh platform=ios,macos,tvos
./build.sh clean
```

The build script uses this dependency set:

- libunibreak `libunibreak_6_1`
- freetype `VER-2-14-3`
- fribidi `v1.0.16`
- harfbuzz `14.2.0`
- libass `0.17.4`

libass is built with CoreText enabled and fontconfig/directwrite disabled, which is the right shape for iOS/tvOS/macOS app embedding.

The generated XCFrameworks are written back into:

```text
Vendor/Libunibreak.xcframework
Vendor/Libfreetype.xcframework
Vendor/Libfribidi.xcframework
Vendor/Libharfbuzz.xcframework
Vendor/Libass.xcframework
```

## Rendering API

```swift
let renderer = try AssRenderer()
try renderer.loadASS(assFileData)

let output = try renderer.render(
    AssRenderRequest(
        time: playerTime.seconds,
        viewportSize: videoView.bounds.size,
        scale: UIScreen.main.scale
    )
)

switch output {
case .unchanged:
    break
case .changed(let patch):
    // patch.data is premultiplied BGRA8 for patch.rect.
    uploadPatchToTexture(patch)
}
```

For FFmpeg embedded ASS/SSA streams:

```swift
let renderer = try AssRenderer()
try renderer.loadEmbeddedTrack(.ffmpegCodecPrivate(codecParametersExtradata))

try renderer.appendEmbeddedEvent(
    .ffmpegASSRect(
        decodedSubtitleEventData,
        startTime: startSeconds,
        duration: durationSeconds
    )
)

let output = try renderer.render(
    AssRenderRequest(time: playerTime.seconds, viewportSize: videoView.bounds.size, scale: UIScreen.main.scale)
)
```

The event data should be the FFmpeg decoded ASS chunk, usually `AVSubtitleRect.ass` as UTF-8 bytes. Call `pruneEvents(before:)` periodically during long playback to discard old events.

The public contract is intentionally small:

- `AssRendering`: protocol for renderers
- `AssRenderer`: libass-backed implementation
- `AssEmbeddedTrack`: one embedded ASS/SSA subtitle stream header
- `AssEmbeddedEvent`: one decoded embedded ASS/SSA subtitle event
- `AssRenderRequest`: time, viewport size, display scale
- `AssRenderOutput`: `.unchanged` or `.changed(AssBitmapPatch)`
- `AssBitmapPatch`: dirty rect and premultiplied BGRA8 bytes

## UIKit Overlay

```swift
let subtitleView = try AssSubtitleOverlayView()
try subtitleView.loadASS(assFileData)
playerContainer.addSubview(subtitleView)

// Keep it pinned over the player, then call from your display link.
try subtitleView.render(at: playerTime.seconds)
```

`AssSubtitleOverlayView` keeps a reusable pixel surface. When libass reports no visual change, it does no pixel work. When the frame changes, it applies only the returned dirty patch into the surface.

## SwiftUI Overlay

```swift
VideoPlayer(player: player)
    .overlay {
        AssSubtitleOverlay(subtitleData: assFileData, time: playerTime.seconds)
            .allowsHitTesting(false)
    }
```

For production playback, drive `time` from a display link or player time observer. A 60 fps loop is fine because unchanged frames return without re-rendering or copying subtitle pixels.

## Performance Notes

libass already exposes frame-change detection through `ass_render_frame`. AssKit preserves that behavior:

- unchanged subtitle frame: returns `.unchanged`
- changed subtitle frame: returns one BGRA dirty rect
- dirty rect includes the previous subtitle bounds so moved/removed subtitles clear correctly
- overlay views update their backing pixel buffer only inside that dirty rect

For a Metal player, prefer consuming `AssBitmapPatch` directly and uploading the patch into a subtitle texture with `replace(region:mipmapLevel:withBytes:bytesPerRow:)`.

## License Notes

This package links to libass and related third-party libraries. Check each dependency's license before shipping binaries in your app. The vendored libass public headers are included only so the C bridge can compile reliably with SPM binary targets.
