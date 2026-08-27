import XCTest
@testable import AssKit

final class AssKitTests: XCTestCase {
    func testRendererProducesPatchAndSkipsUnchangedFrame() throws {
        let ass = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 320
        PlayResY: 180

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Helvetica,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,AssKit
        """

        let renderer = try AssRenderer()
        try renderer.loadASS(Data(ass.utf8))

        let first = try renderer.render(
            AssRenderRequest(time: 0.5, viewportSize: CGSize(width: 320, height: 180), scale: 1)
        )
        XCTAssertNotNil(first.patch)

        let second = try renderer.render(
            AssRenderRequest(time: 0.5, viewportSize: CGSize(width: 320, height: 180), scale: 1)
        )
        guard case .unchanged = second else {
            return XCTFail("Expected unchanged output for same timestamp")
        }
    }

    func testRendererAcceptsFFmpegEmbeddedASSChunks() throws {
        let codecPrivate = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 320
        PlayResY: 180

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Helvetica,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """

        let renderer = try AssRenderer()
        try renderer.loadTrack(.track(Data(codecPrivate.utf8)))
        try renderer.appendEvent(
            .AssRect(
                "0,0,Default,,0,0,0,,Embedded AssKit",
                startTime: 0.25,
                duration: 1.5
            )
        )

        let output = try renderer.render(
            AssRenderRequest(time: 0.5, viewportSize: CGSize(width: 320, height: 180), scale: 1)
        )
        XCTAssertNotNil(output.patch)
    }

    func testRendererAcceptsCustomFontsDirectoryConfiguration() throws {
        let fontsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fontsDirectory) }

        let ass = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 320
        PlayResY: 180

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Helvetica,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,AssKit
        """

        let renderer = try AssRenderer(
            configuration: AssRendererConfiguration(fontsDirectoryPath: fontsDirectory.path)
        )
        try renderer.loadASS(Data(ass.utf8))

        let output = try renderer.render(
            AssRenderRequest(time: 0.5, viewportSize: CGSize(width: 320, height: 180), scale: 1)
        )
        XCTAssertNotNil(output.patch)
    }

    func testRendererInjectsMemoryFontsFromAttachments() throws {
        let fontURL = URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc")
        let fontData = try Data(contentsOf: fontURL)

        let ass = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 320
        PlayResY: 180

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Helvetica,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,AssKit
        """

        let renderer = try AssRenderer()
        try renderer.injectMemoryFont(named: "Helvetica.ttf", data: fontData)
        try renderer.loadASS(Data(ass.utf8))

        let output = try renderer.render(
            AssRenderRequest(time: 0.5, viewportSize: CGSize(width: 320, height: 180), scale: 1)
        )
        XCTAssertNotNil(output.patch)
    }

    func testRendererInjectsBatchedMemoryFonts() throws {
        guard FileManager.default.fileExists(atPath: "/System/Library/Fonts/Helvetica.ttc") else {
            throw XCTSkip("System font fixture is unavailable on this platform")
        }
        let fontData = try Data(contentsOf: URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc"))

        let renderer = try AssRenderer(
            configuration: AssRendererConfiguration(defaultFontFamily: "Helvetica")
        )
        try renderer.injectMemoryFonts([
            AssMemoryFont(name: "Helvetica-Attachment.ttf", data: fontData),
            AssMemoryFont(name: "Helvetica-Bold-Attachment.ttf", data: fontData),
        ])

        try renderer.loadASS(Data(assSample.utf8))
        let output = try renderer.render(
            AssRenderRequest(time: 0.5, viewportSize: CGSize(width: 320, height: 180), scale: 1)
        )
        XCTAssertNotNil(output.patch)
    }

    func testRendererRejectsInvalidMemoryFontInjections() throws {
        let renderer = try AssRenderer()

        XCTAssertThrowsError(try renderer.injectMemoryFont(named: "", data: Data([0x01]))) { error in
            XCTAssertEqual(error as? AssKitError, .invalidFontData)
        }
        XCTAssertThrowsError(try renderer.injectMemoryFont(named: "Empty.ttf", data: Data())) { error in
            XCTAssertEqual(error as? AssKitError, .invalidFontData)
        }
    }

    private var assSample: String {
        """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 320
        PlayResY: 180

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Helvetica,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,AssKit
        """
    }

    func testPatchSurfaceAcceptsEmptyPatch() {
        let surface = AssPixelSurface()
        surface.reset(pixelWidth: 16, pixelHeight: 16)
        surface.apply(
            AssBitmapPatch(
                rect: .zero,
                pixelWidth: 0,
                pixelHeight: 0,
                bytesPerRow: 0,
                data: Data()
            )
        )
        XCTAssertNotNil(surface.makeCGImage())
    }
}
