import Foundation
import CoreServices

private final class VaultEventSink {
    let changed: () -> Void
    init(_ changed: @escaping () -> Void) { self.changed = changed }
}

/// One recursive native event stream. The stream retains only its callback sink.
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    init?(root: URL, changed: @escaping () -> Void) {
        let sink = VaultEventSink(changed)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(sink).toOpaque(), retain: { pointer in
            guard let pointer else { return nil }; return UnsafeRawPointer(Unmanaged<VaultEventSink>.fromOpaque(pointer).retain().toOpaque())
        }, release: { pointer in
            if let pointer { Unmanaged<VaultEventSink>.fromOpaque(pointer).release() }
        }, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }; Unmanaged<VaultEventSink>.fromOpaque(info).takeUnretainedValue().changed()
        }, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15, flags) else { return nil }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.global(qos: .utility))
        guard FSEventStreamStart(created) else { FSEventStreamInvalidate(created); FSEventStreamRelease(created); return nil }
        stream = created
    }
    func stop() {
        guard let stream else { return }; self.stream = nil
        FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
    }
    deinit { stop() }
}

/// Cancellation is shared with the utility queue; no stale result crosses a grant change.
final class VaultScanTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
