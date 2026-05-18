import CoreGraphics
import Foundation

public final class AssPixelSurface {
    public private(set) var pixelWidth: Int = 0
    public private(set) var pixelHeight: Int = 0
    public private(set) var bytesPerRow: Int = 0

    private var storage = Data()

    public init() {}

    public func reset(pixelWidth: Int, pixelHeight: Int) {
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
        self.bytesPerRow = self.pixelWidth * 4
        self.storage = Data(count: self.bytesPerRow * self.pixelHeight)
    }

    public func apply(_ patch: AssBitmapPatch) {
        guard patch.pixelWidth > 0, patch.pixelHeight > 0 else {
            return
        }

        let x = max(0, Int((patch.rect.origin.x * inferredScale(for: patch)).rounded()))
        let y = max(0, Int((patch.rect.origin.y * inferredScale(for: patch)).rounded()))
        guard x < pixelWidth, y < pixelHeight else {
            return
        }

        let copyWidth = min(patch.pixelWidth, pixelWidth - x) * 4
        let copyHeight = min(patch.pixelHeight, pixelHeight - y)
        storage.withUnsafeMutableBytes { dstRaw in
            patch.data.withUnsafeBytes { srcRaw in
                guard let dstBase = dstRaw.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                for row in 0..<copyHeight {
                    let dst = dstBase + (y + row) * bytesPerRow + x * 4
                    let src = srcBase + row * patch.bytesPerRow
                    dst.update(from: src, count: copyWidth)
                }
            }
        }
    }

    public func makeCGImage() -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0, storage.count == bytesPerRow * pixelHeight else {
            return nil
        }

        let data = storage as CFData
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }
        return CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                .union(.byteOrder32Little),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func inferredScale(for patch: AssBitmapPatch) -> CGFloat {
        guard patch.rect.width > 0 else {
            return 1
        }
        return CGFloat(patch.pixelWidth) / patch.rect.width
    }
}
