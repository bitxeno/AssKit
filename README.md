# AssKit

AssKit is a Swift Package for rendering ASS/SSA subtitles on Apple platforms with [libass](https://github.com/libass/libass).

## Features

- C bridge over libass for stable Swift interop
- Dirty-rect BGRA patches for changed subtitle pixels
- UIKit overlay view for player overlays
- SwiftUI wrapper for UIKit-based overlays

## Installation

Add this repository as a Swift Package dependency, then import:

```swift
import AssKit
```

`Package.swift` uses local binary targets under `Vendor/*.xcframework`. No remote binary target is referenced by the package.


## SwiftUI Overlay

```swift
VideoPlayer(player: player)
    .overlay {
        AssSubtitleOverlay(subtitleData: assFileData, time: playerTime.seconds)
            .allowsHitTesting(false)
    }
```

For production playback, drive `time` from a display link or player time observer. A 60 fps loop is fine because unchanged frames return without re-rendering or copying subtitle pixels.

## UIKit Overlay

```swift
let subtitleView = try AssSubtitleOverlayView()
try subtitleView.loadASS(assFileData)
playerContainer.addSubview(subtitleView)

// Keep it pinned over the player, then call from your display link.
try subtitleView.render(at: playerTime.seconds)
```

`AssSubtitleOverlayView` keeps a reusable pixel surface. When libass reports no visual change, it does no pixel work. When the frame changes, it applies only the returned dirty patch into the surface.

## Rendering API

```swift
let renderer = try AssRenderer(
    configuration: AssRendererConfiguration(
        defaultFontFamily: "Helvetica",
        fontsDirectoryPath: Bundle.main.bundleURL
            .appendingPathComponent("SubtitleFonts", isDirectory: true)
            .path
    )
)
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

If you package extra font files with your app, point `fontsDirectoryPath` at that directory so libass can resolve subtitle font names from your bundled fonts.

You can also update the extra font search path later:

```swift
renderer.setFontsDirectory(
    Bundle.main.bundleURL
        .appendingPathComponent("SubtitleFonts", isDirectory: true)
        .path
)
```

For FFmpeg embedded ASS/SSA streams:

```swift
let renderer = try AssRenderer()
try renderer.loadTrack(.track(assHeader))

try renderer.appendEvent(
    .AssRect(
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
- `AssTrack`: one embedded ASS/SSA subtitle stream header
- `AssEvent`: one decoded embedded ASS/SSA subtitle event
- `AssRenderRequest`: time, viewport size, display scale
- `AssRenderOutput`: `.unchanged` or `.changed(AssBitmapPatch)`
- `AssBitmapPatch`: dirty rect and premultiplied BGRA8 bytes

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

## Performance Notes

libass already exposes frame-change detection through `ass_render_frame`. AssKit preserves that behavior:

- unchanged subtitle frame: returns `.unchanged`
- changed subtitle frame: returns one BGRA dirty rect
- dirty rect includes the previous subtitle bounds so moved/removed subtitles clear correctly
- overlay views update their backing pixel buffer only inside that dirty rect

For a Metal player, prefer consuming `AssBitmapPatch` directly and uploading the patch into a subtitle texture with `replace(region:mipmapLevel:withBytes:bytesPerRow:)`.

## License Notes

AssKit itself is MIT licensed; see [LICENSE](LICENSE).

AssKit redistributes libass, libunibreak, freetype, fribidi, and harfbuzz in source-derived binary form via the vendored XCFrameworks under [Vendor](Vendor).

When you regenerate the vendored frameworks with [build.sh](build.sh), the build script reads each dependency's upstream license text from the fetched source trees under [build/src](build/src) and copies it into each packaged framework as a LICENSE file so the redistributed binary artifacts carry their notices.

Review the obligations for each dependency before shipping binaries in your app or SDK. The vendored libass public headers are included only so the C bridge can compile reliably with SPM binary targets.
