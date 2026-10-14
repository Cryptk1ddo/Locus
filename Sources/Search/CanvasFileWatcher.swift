import Foundation
import Darwin

/// Watches only an explicitly granted file, never its parent directory.
final class CanvasFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private struct Version: Equatable {
        let size: off_t
        let seconds: Int
        let nanoseconds: Int
        let mode: mode_t
        init?(_ descriptor: Int32) {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { return nil }
            size = info.st_size; seconds = info.st_mtimespec.tv_sec
            nanoseconds = info.st_mtimespec.tv_nsec; mode = info.st_mode
        }
    }
    init?(url: URL, changed: @escaping () -> Void) {
        let access = url.startAccessingSecurityScopedResource()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { if access { url.stopAccessingSecurityScopedResource() }; return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke], queue: .global(qos: .utility))
        var version = Version(descriptor)
        source.setEventHandler { [weak source] in
            guard let source else { return }
            let next = Version(descriptor)
            let contentEvents: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename, .revoke]
            // Resolving security-scoped bookmarks may update extended attributes.
            // Ignore those read-side events without losing real content/permission changes.
            let meaningful = !source.data.intersection(contentEvents).isEmpty || next != version
            version = next
            if meaningful { changed() }
        }
        source.setCancelHandler { close(descriptor); if access { url.stopAccessingSecurityScopedResource() } }
        source.resume(); self.source = source
    }
    func stop() { source?.cancel(); source = nil }
    deinit { stop() }
}
