import SwiftUI
import ImageIO

/// Sizing rules shared by the inspector's image previews.
enum ImagePreview {
    /// Width of the inspector panel.
    static let inspectorWidth: CGFloat = 320

    /// Padding applied inside the inspector's scroll content.
    static let inspectorPadding: CGFloat = 16

    /// Width available to a preview once the inspector's padding is taken off.
    static var contentWidth: CGFloat { inspectorWidth - inspectorPadding * 2 }

    /// Ceiling on preview height. A 1:8 generation would otherwise render over
    /// 2000pt tall at the inspector's width and push everything else off-screen,
    /// so extreme ratios stop growing and shrink in width instead.
    static let maxHeight: CGFloat = 520

    /// Size the preview box for an image of the given aspect ratio (width / height).
    static func displaySize(aspectRatio: CGFloat) -> CGSize {
        let ratio = aspectRatio > 0 ? aspectRatio : 1
        let height = contentWidth / ratio
        guard height > maxHeight else {
            return CGSize(width: contentWidth, height: height)
        }
        return CGSize(width: maxHeight * ratio, height: maxHeight)
    }

    /// Aspect ratio for `url`, falling back to square when it can't be read.
    ///
    /// Resolved synchronously so the box is the right shape on its first frame.
    /// Doing this in `.task` instead made the preview render square and then jump
    /// to the real shape every time the selection changed. Results are cached
    /// because `body` re-runs often and generated files never change in place.
    @MainActor
    static func ratio(for url: URL) -> CGFloat {
        if let cached = ratioCache[url] { return cached }
        let ratio = aspectRatio(of: url) ?? 1
        ratioCache[url] = ratio
        return ratio
    }

    @MainActor private static var ratioCache: [URL: CGFloat] = [:]

    /// Aspect ratio (width / height) read from the file header, without decoding
    /// the image. Returns nil if the file can't be read.
    static func aspectRatio(of url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else {
            return nil
        }
        // Orientations 5-8 are the quarter turns: stored dimensions are swapped
        // relative to how the image displays.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let quarterTurned = (5...8).contains(orientation)
        return quarterTurned ? CGFloat(height / width) : CGFloat(width / height)
    }
}

/// A preview that takes its shape from the image it shows: a portrait generation
/// makes the box taller, a landscape one wider, up to `ImagePreview.maxHeight`.
/// Content is handed an exact frame, so it can fill the box without cropping.
struct AspectPreviewBox<Content: View>: View {
    /// The image the box takes its shape from — the generation, in both previews.
    let imageURL: URL
    @ViewBuilder var content: Content

    var body: some View {
        let size = ImagePreview.displaySize(aspectRatio: ImagePreview.ratio(for: imageURL))

        content
            .frame(width: size.width, height: size.height)
            .background(CheckerboardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 6))
            // Centre the box when a capped ratio makes it narrower than the column.
            .frame(maxWidth: .infinity)
    }
}

/// Grey checkerboard shown behind previews so transparent pixels read as
/// transparent rather than as the window background.
struct CheckerboardBackground: View {
    var body: some View {
        Image(decorative: Self.tile, scale: 1.0)
            .resizable(resizingMode: .tile)
    }

    private static let tile: CGImage = {
        let sq = 8
        let size = sq * 2
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Light squares
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sq, height: sq))
        ctx.fill(CGRect(x: sq, y: sq, width: sq, height: sq))
        // Dark squares
        ctx.setFillColor(CGColor(gray: 0.75, alpha: 1))
        ctx.fill(CGRect(x: sq, y: 0, width: sq, height: sq))
        ctx.fill(CGRect(x: 0, y: sq, width: sq, height: sq))
        return ctx.makeImage()!
    }()
}
