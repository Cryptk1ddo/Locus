import Foundation

/// Media state never treats a live stream as a finite, seekable recording.
struct FloatMediaState: Equatable {
    var current: Double = 0
    var duration: Double = 0
    var playing = false
    var muted = false
    var seekable = false
    var canSkip = false
    var available = false
    var loading = false
    var buffering = false
    var ended = false
    var failed = false
    var live = false
    var rate: Double = 1
    var aspect: Double?
    init() {}
    init(_ value: Any?) {
        guard let fields = value as? [String: Any] else { return }
        available = fields["available"] as? Bool ?? true
        loading = fields["loading"] as? Bool ?? false
        buffering = fields["buffering"] as? Bool ?? false
        ended = fields["ended"] as? Bool ?? false
        failed = fields["failed"] as? Bool ?? false
        let speed = Self.finite(fields["rate"]); rate = speed > 0 && speed <= 16 ? speed : 1
        let width = Self.finite(fields["width"]), height = Self.finite(fields["height"])
        if width > 0, height > 0, width <= 16_384, height <= 16_384, (0.5...3).contains(width / height) { aspect = width / height }
        current = max(0, Self.finite(fields["current"]))
        duration = max(0, Self.finite(fields["duration"]))
        if duration > 0 { current = min(current, duration) }
        playing = fields["playing"] as? Bool ?? false
        muted = fields["muted"] as? Bool ?? false
        seekable = duration > 0 && fields["seekable"] as? Bool == true
        canSkip = fields["canSkip"] as? Bool ?? seekable
        live = fields["live"] as? Bool ?? (duration == 0 && !loading)
        if !available || failed { playing = false; seekable = false; canSkip = false }
    }
    private static func finite(_ value: Any?) -> Double { let number = value as? Double ?? 0; return number.isFinite ? number : 0 }
    var needsAttention: Bool { !available || loading || buffering || failed }
    var progress: Double { duration > 0 ? min(1, max(0, current / duration)) : 0 }
    var timeLabel: String {
        if !available { return "Video unavailable" }
        if failed { return "Playback error" }
        if loading { return "Loading…" }
        let clock = duration > 0 ? Self.clock(current) + " / " + Self.clock(duration) : live ? "Live" : Self.clock(current)
        if ended { return "Ended · " + clock }
        return buffering ? "Buffering… · " + clock : clock
    }
    static func clock(_ seconds: Double) -> String {
        let value = Int(min(359_999, max(0, seconds.isFinite ? seconds : 0)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}
