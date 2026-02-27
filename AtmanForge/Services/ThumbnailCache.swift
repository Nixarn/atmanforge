import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ImageIO

/// Shared in-memory cache for thumbnail images, using CGImageSource for efficient
/// downsampled loading (decodes at target size rather than full file resolution).
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    #if os(macOS)
    private let cache = NSCache<NSURL, NSImage>()
    #else
    private let cache = NSCache<NSURL, UIImage>()
    #endif

    private init() {
        cache.countLimit = 500
    }

    #if os(macOS)
    func image(for url: URL, maxPixelSize: CGFloat = 128) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(nsImage, forKey: key)
        return nsImage
    }
    #else
    func image(for url: URL, maxPixelSize: CGFloat = 128) -> UIImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        cache.setObject(uiImage, forKey: key)
        return uiImage
    }
    #endif

    func invalidate(url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}
