import AppKit
import ImageIO
import CryptoKit

/// Immutable, owned PNG assets only. No network URL is a thumbnail request.
enum WorkspaceImage {
    nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func validPNG(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 4_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = info[kCGImagePropertyPixelWidth as String] as? Int,
              let height = info[kCGImagePropertyPixelHeight as String] as? Int,
              (1...2_000).contains(width), (1...4_000).contains(height),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil
        else { return false }
        return true
    }

    nonisolated static func png(_ cg: CGImage) -> Data? {
        guard cg.width <= 2_000, cg.height <= 4_000 else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination), data.length <= 4_000_000 else { return nil }
        return data as Data
    }

    @MainActor private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 24_000_000
        return cache
    }()

    @MainActor static func thumbnail(_ object: LocusObject, store: WorkspaceStore) -> NSImage? {
        image(object, store: store, maxPixels: 600)
    }

    @MainActor static func image(_ object: LocusObject, store: WorkspaceStore, maxPixels: Int = 2_000) -> NSImage? {
        guard let id = object.snapshotID else { return nil }
        let url = store.assetURL(id)
        guard (try? WorkspaceFiles.checkPath(url)) != nil,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= 4_000_000 else { return nil }
        let integrity = object.snapshotIntegrity
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let stamp = "\(attributes[.systemFileNumber] ?? 0)-\(modified)-\(size)"
        let key = "\(url.path)-\(stamp)-\(integrity["sha256"]?.text ?? "legacy")-\(String(describing: integrity["bytes"]))-\(maxPixels)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let data = try? Data(contentsOf: url), validPNG(data),
              integrity["bytes"].map({ $0 == .number(Double(data.count)) }) ?? true,
              integrity["sha256"].map({ $0 == .string(digest(data)) }) ?? true,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: min(2_000, max(1, maxPixels)),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }
}
