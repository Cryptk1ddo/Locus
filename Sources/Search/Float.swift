import AppKit
import WebKit

// A video that keeps playing after you have gone somewhere else, in a small
// window that stays above everything — other tabs, and other apps.
//
// WebKit will not hand a video to the system's picture-in-picture without a
// real click on the page, and nothing the app does counts as one. Chromium is
// looser, which is why this works elsewhere and refused here.
//
// So the engine is not asked. The page itself is moved: everything but the
// video is made invisible, the video is stretched to fill the viewport, and the
// whole web view is lifted out of the window and into a small floating one. The
// video never stops, because it is the same page it always was — it has only
// changed windows.

@MainActor
final class Float {
    private var panel: NSPanel?
    private var controls: Controls?
    private weak var page: NSView?

    /// Asked to go away. The browser does the bookkeeping and calls back into
    /// `drop` — there is one way this window closes, and it is not this class
    /// quietly tidying up behind everyone's back. Two paths to closing is how
    /// it stayed on screen after the page had already gone home.
    var onClose: (() -> Void)?
    /// Bring the window forward and go to the tab it came from.
    var onReturn: (() -> Void)?
    /// Stop or start the video. Answers with whether it is playing now.
    var onPlayPause: ((@escaping (Bool) -> Void) -> Void)?
    /// Step over the bit you missed, or back to it.
    var onSkip: ((Double) -> Void)?
    /// Asked every half second while the window is up, for the line along the
    /// bottom edge.
    var onProgress: ((@escaping (FloatMediaState) -> Void) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onMute: (() -> Void)?
    var onRate: ((Double) -> Void)?

    private var ticker: Timer?

    var showing: Bool { panel != nil }
    static func owns(_ window: NSWindow?) -> Bool { window is Panel }
    @discardableResult static func take(_ event: NSEvent) -> Bool {
        guard let controls = event.window?.contentView?.subviews.compactMap({ $0 as? Controls }).first else { return false }
        return controls.takeKey(event)
    }


    /// Where a test run's bench opens the window instead: off every screen,
    /// at the size it would have had, and not remembered (see `film float`
    /// in Bench.swift). Nil everywhere else.
    static var benchAway: NSPoint?

    /// Two fingers flick the window to a corner instead of pushing it
    /// along (Settings › General). Off unless asked for.
    static var flicks = false

    /// Where a flick sends the window, a margin in from the edges of
    /// `area`. A swipe clearly both ways — between about 22° and 68° — takes
    /// it to the corner it points at; a straighter one along its stronger
    /// direction, against whichever of the other two edges it is nearer.
    nonisolated static func corner(for frame: NSRect, in area: NSRect, toward way: CGVector, margin: CGFloat = 12) -> NSPoint {
        let left = area.minX + margin, right = area.maxX - margin - frame.width
        let bottom = area.minY + margin, top = area.maxY - margin - frame.height
        let across = abs(way.dx), up = abs(way.dy)
        let x = way.dx > 0 ? right : left, y = way.dy > 0 ? top : bottom
        if min(across, up) >= 0.4 * max(across, up) { return NSPoint(x: x, y: y) }
        if across >= up { return NSPoint(x: x, y: frame.midY > area.midY ? top : bottom) }
        return NSPoint(x: frame.midX > area.midX ? right : left, y: y)
    }

    /// Where docking leaves the window: off the side of `area`, but for a
    /// sliver to bring it back by.
    nonisolated static func docked(_ frame: NSRect, right: Bool, in area: NSRect, sliver: CGFloat = 10) -> NSPoint {
        NSPoint(x: right ? area.maxX - sliver : area.minX - frame.width + sliver, y: frame.minY)
    }

    /// Whether the window can go into that side of `area`, one of `screens`:
    /// not where another screen carries on, where it would only slide onto
    /// that one instead.
    nonisolated static func dockable(_ frame: NSRect, right: Bool, in area: NSRect, screens: [NSRect]) -> Bool {
        let beyond = NSRect(x: right ? area.maxX : area.minX - frame.width, y: frame.minY, width: frame.width, height: frame.height)
        return !screens.contains { !$0.contains(area) && $0.intersects(beyond) }
    }

    /// Screens a test run's bench makes up, far off the real ones, for the
    /// window to flick and dock about (see `float` in Bench.swift). Nil
    /// everywhere else.
    static var benchScreens: [NSRect]?

    func lift(_ page: NSView) {
        guard panel == nil else { return }
        self.page = page

        let size = NSSize(width: 440, height: 247)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        // Where it was last, at the size it was, if a screen still shows it;
        // otherwise the bottom right of this one.
        var spot = Float.remembered ?? NSRect(
            x: screen.maxX - size.width - 24,
            y: screen.minY + 24,
            width: size.width,
            height: size.height
        )
        if let away = Float.benchAway { spot.origin = away }

        let panel = Panel(
            contentRect: spot,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above every ordinary window, this app's and everyone else's, and
        // present on whichever desktop you happen to be looking at.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // No shadow. A window with one is composited by WindowServer on every
        // frame of the video; without it the video can go straight to the
        // display, as it does in a tab. Measured on 1080p and 4K YouTube:
        // WindowServer's GPU time 28% with the shadow, 16–20% without, 22%
        // playing in the tab.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        // The bench's, off every screen, is left out when a probe is hidden.
        panel.canHide = Float.benchAway == nil
        panel.aspectRatio = size
        // Kept once a move or a resize is over, not on each step of one: at
        // the end of a resize by its edges, as it closes (see drop), and as
        // the app quits with it open, which closes nothing.
        let keep: (Notification.Name, AnyObject) -> NSObjectProtocol = { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let frame = self?.restingFrame { Float.remembered = frame }
                }
            }
        }
        keeping = [
            keep(NSWindow.didEndLiveResizeNotification, panel),
            keep(NSApplication.willTerminateNotification, NSApp),
        ]
        panel.minSize = NSSize(width: 260, height: 146)

        // At the size the window opens at. Built at the default size and
        // then stretched to a remembered one, the page was laid out twice,
        // and the first frames of video filled only part of the window
        // (#257).
        let ground = NSView(frame: NSRect(origin: .zero, size: spot.size))
        ground.wantsLayer = true
        ground.layer?.backgroundColor = NSColor.black.cgColor
        ground.layer?.cornerRadius = 14
        ground.layer?.masksToBounds = true

        // WebKit puts its own pinch recogniser on a web view, and a gesture
        // recogniser is consulted before the responder chain is. With it left
        // on, every pinch aimed at this window went into zooming the page
        // inside it instead of sizing the window. It comes back on landing.
        (page as? WKWebView)?.allowsMagnification = false

        page.removeFromSuperview()
        page.frame = ground.bounds
        page.autoresizingMask = [.width, .height]
        ground.addSubview(page)

        let controls = Controls(frame: ground.bounds)
        controls.autoresizingMask = [.width, .height]
        controls.onClose = { [weak self] in self?.onClose?() }
        controls.onReturn = { [weak self] in self?.onReturn?() }
        controls.onPlayPause = { [weak self, weak controls] in
            self?.onPlayPause? { [weak self, weak controls] playing in
                guard let controls, self?.controls === controls else { return }
                controls.playing = playing
            }
        }
        controls.onSkip = { [weak self] seconds in self?.onSkip?(seconds) }
        controls.onSeek = { [weak self] fraction in self?.onSeek?(fraction) }
        controls.onMute = { [weak self] in self?.onMute?() }
        controls.onRate = { [weak self] rate in self?.onRate?(rate) }
        ground.addSubview(controls)
        self.controls = controls

        panel.contentView = ground
        panel.orderFrontRegardless()
        self.panel = panel
        onProgress? { [weak self, weak controls] state in
            guard let self, let controls, self.controls === controls else { return }; self.applyAspect(state.aspect); controls.media = state
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak controls] _ in
            MainActor.assumeIsolated {
                guard let self, let controls else { return }

                // A window that no longer holds the page has nothing to show
                // and no reason to exist. Something else took the page back —
                // and rather than hunt every path that could, this makes it
                // impossible for the empty black rectangle to outlive it by
                // more than half a second.
                if self.page?.superview !== ground {
                    self.onClose?()
                    return
                }

                self.onProgress? { [weak controls] state in
                    guard let controls, self.controls === controls else { return }
                    self.applyAspect(state.aspect); controls.media = state
                }
            }
        }
    }

    /// Keep controls usable and fit the media without a window spilling off screen.
    nonisolated static func mediaFrame(_ frame: CGRect, ratio: Double, in area: CGRect) -> CGRect? {
        guard ratio.isFinite, (0.5...3).contains(ratio), frame.width.isFinite, frame.width > 0, area.width > 0, area.height > 0 else { return nil }
        let minimum = max(260, 146 * ratio), maximum = min(area.width * 0.85, area.height * 0.85 * ratio)
        guard maximum >= minimum else { return nil }
        let width = min(max(frame.width, minimum), maximum), height = width / ratio
        return CGRect(x: min(max(frame.maxX - width, area.minX), area.maxX - width), y: min(max(frame.maxY - height, area.minY), area.maxY - height), width: width, height: height)
    }
    private func applyAspect(_ ratio: Double?) {
        guard let ratio, let panel, !panel.inLiveResize, controls?.dockedFrom == nil,
              max(abs(panel.aspectRatio.width / max(1, panel.aspectRatio.height) - ratio),
                  abs(panel.frame.width / max(1, panel.frame.height) - ratio)) > 0.01 else { return }
        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let area = Float.benchAway == nil ? screen : CGRect(x: panel.frame.maxX - screen.width, y: panel.frame.maxY - screen.height, width: screen.width, height: screen.height)
        guard let frame = Self.mediaFrame(panel.frame, ratio: ratio, in: area) else { return }
        let minimum = max(260, 146 * ratio)
        panel.minSize = NSSize(width: minimum, height: minimum / ratio)
        panel.aspectRatio = NSSize(width: ratio, height: 1)
        panel.setFrame(frame, display: false)
    }

    /// The window's last place and size, kept across closing it and quitting,
    /// and given back only while a screen still shows most of it.
    private static var remembered: NSRect? {
        get {
            guard let text = Store.settings.string(forKey: "float.frame") else { return nil }
            let frame = NSRectFromString(text)
            let shown = NSScreen.screens.contains {
                let seen = $0.visibleFrame.intersection(frame)
                return seen.width * seen.height > 0.6 * frame.width * frame.height
            }
            return frame.width > 100 && shown ? frame : nil
        }
        set {
            guard benchAway == nil else { return }
            Store.settings.set(newValue.map(NSStringFromRect), forKey: "float.frame")
        }
    }

    private var keeping: [NSObjectProtocol] = []

    /// Where the window is, or was before it was docked at a side: a docked
    /// window is kept as it was, not as the sliver it is.
    private var restingFrame: NSRect? {
        guard let panel else { return nil }
        guard let home = controls?.dockedFrom else { return panel.frame }
        return NSRect(origin: home, size: panel.frame.size)
    }

    /// Puts the page down and closes. Whoever owns the page takes it back on
    /// their next layout.
    func drop() {
        guard let panel else { return }
        if let frame = restingFrame { Float.remembered = frame }
        keeping.forEach(NotificationCenter.default.removeObserver)
        keeping = []
        ticker?.invalidate()
        ticker = nil
        (page as? WKWebView)?.allowsMagnification = true
        page?.removeFromSuperview()
        page = nil
        controls = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    /// What a small window of video needs, and nothing else: a way out, a way
    /// back, a way to stop it, and a way to step over the bit you missed.
    ///
    /// Out of sight until the pointer is over the window — the whole point of
    /// this window is the picture.
    private final class Controls: NSView {
        var onClose: (() -> Void)?
        var onReturn: (() -> Void)?
        var onPlayPause: (() -> Void)?
        var onSkip: ((Double) -> Void)?
        var onSeek: ((Double) -> Void)?
        var onMute: (() -> Void)?
        var onRate: ((Double) -> Void)?

        var playing = true {
            didSet {
                pause.image = glyph(playing ? "pause.fill" : media.ended ? "arrow.counterclockwise" : "play.fill", 17)
                pause.setAccessibilityLabel(playing ? "Pause video" : media.ended ? "Replay video" : "Play video")
            }
        }

        var media = FloatMediaState() {
            didSet {
                playing = media.playing
                pause.isEnabled = media.available && !media.failed
                mute.isEnabled = media.available && !media.failed
                mute.image = glyph(media.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", 12)
                mute.setAccessibilityLabel(media.muted ? "Unmute video" : "Mute video")
                timeline.isEnabled = media.seekable
                if !timeline.trackingSeek { timeline.doubleValue = media.progress }
                timeline.setAccessibilityValueDescription(media.timeLabel)
                rewind.isEnabled = media.canSkip; forward.isEnabled = media.canSkip
                time.stringValue = media.timeLabel
                time.alphaValue = near || media.needsAttention ? 1 : 0
                CATransaction.begin(); CATransaction.setDisableActions(true)
                scrim.opacity = near || media.needsAttention ? 1 : 0; CATransaction.commit()
            }
        }

        private let close = MediaButton()
        private let back = MediaButton()
        private let pause = MediaButton()
        private let rewind = MediaButton()
        private let forward = MediaButton()
        private let scrim = CAGradientLayer()
        private let mute = MediaButton()
        private let timeline = MediaSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
        private let time = NSTextField(labelWithString: "Video unavailable")
        private var near = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true

            // A wash at the top and bottom, so white buttons hold against a
            // bright frame of film without covering it.
            scrim.colors = [
                NSColor(white: 0, alpha: 0.45).cgColor,
                NSColor(white: 0, alpha: 0).cgColor,
                NSColor(white: 0, alpha: 0).cgColor,
                NSColor(white: 0, alpha: 0.5).cgColor,
            ]
            scrim.locations = [0, 0.28, 0.66, 1]
            scrim.opacity = 0
            layer?.addSublayer(scrim)

            dress(close, "xmark", 11, round: 15, action: #selector(pressedClose))
            dress(back, "arrow.up.forward", 12, round: 15, action: #selector(pressedReturn))
            dress(rewind, "gobackward.15", 15, round: 19, action: #selector(pressedRewind))
            dress(pause, "pause.fill", 17, round: 25, action: #selector(pressedPause))
            dress(forward, "goforward.15", 15, round: 19, action: #selector(pressedForward))

            dress(mute, "speaker.wave.2.fill", 12, round: 15, action: #selector(pressedMute))
            for (button, title) in [(close, "Close picture in picture"), (back, "Return to video tab"), (pause, "Pause video"), (rewind, "Back 15 seconds"), (forward, "Forward 15 seconds")] {
                button.toolTip = title; button.setAccessibilityLabel(title)
            }
            mute.toolTip = "Mute or unmute · M"
            timeline.target = self; timeline.action = #selector(sought); timeline.isContinuous = true; timeline.isEnabled = false
            timeline.setAccessibilityLabel("Video position"); timeline.identifier = NSUserInterfaceItemIdentifier("locus.pip.timeline")
            time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); time.textColor = .white; time.alignment = .center
            [timeline, time].forEach { $0.alphaValue = 0; addSubview($0) }
            buttons.forEach { $0.alphaValue = 0 }
            media = FloatMediaState()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        private var buttons: [NSButton] { [close, back, rewind, pause, forward, mute] }

        private func dress(
            _ button: NSButton,
            _ symbol: String,
            _ size: CGFloat,
            round: CGFloat,
            action: Selector
        ) {
            button.image = glyph(symbol, size)
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.target = self
            button.action = action
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.55).cgColor
            button.layer?.cornerRadius = round
            addSubview(button)
        }

        private func glyph(_ name: String, _ size: CGFloat) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            let look = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            return image?.withSymbolConfiguration(look)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scrim.frame = bounds
            CATransaction.commit()

            close.frame = NSRect(x: 14, y: bounds.height - 44, width: 30, height: 30)
            back.frame = NSRect(x: bounds.width - 44, y: bounds.height - 44, width: 30, height: 30)

            let middle = bounds.midY - 25
            pause.frame = NSRect(x: bounds.midX - 25, y: middle, width: 50, height: 50)
            rewind.frame = NSRect(x: bounds.midX - 25 - 54, y: middle + 6, width: 38, height: 38)
            forward.frame = NSRect(x: bounds.midX + 25 + 16, y: middle + 6, width: 38, height: 38)

            mute.frame = NSRect(x: bounds.width - 80, y: bounds.height - 44, width: 30, height: 30)
            timeline.frame = NSRect(x: 18, y: 12, width: max(1, bounds.width - 36), height: 18)
            time.frame = NSRect(x: 18, y: 34, width: max(1, bounds.width - 36), height: 16)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) { fade(to: 1) }
        override func mouseExited(with event: NSEvent) { fade(to: 0) }

        private func fade(to value: CGFloat) {
            near = value > 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                buttons.forEach { $0.animator().alphaValue = value }
                timeline.animator().alphaValue = value
                time.animator().alphaValue = media.needsAttention ? 1 : value
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            scrim.opacity = media.needsAttention ? 1 : Swift.Float(value)
            CATransaction.commit()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Everything reaches this layer.
        ///
        /// isMovableByWindowBackground never worked here: the window's whole
        /// background is a web view, and a web view swallows every drag before
        /// the window sees it. So every gesture is taken here, above it.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let inside = convert(point, from: superview)
            if near {
                if timeline.isEnabled && timeline.frame.contains(inside) { return timeline.hitTest(point) ?? timeline }
                for button in buttons where button.frame.contains(inside) {
                    return button
                }
            }
            return self
        }

        // MARK: - moving and sizing

        private var grab = NSPoint.zero
        private var origin = NSRect.zero
        private var stretching = false

        private func atCorner(_ point: NSPoint) -> Bool {
            point.x > bounds.maxX - 22 && point.y < bounds.minY + 22
        }

        override func resetCursorRects() {
            addCursorRect(
                NSRect(x: bounds.maxX - 22, y: bounds.minY, width: 22, height: 22),
                cursor: .crosshair
            )
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            window.makeFirstResponder(self)
            // A click on the sliver of a docked window brings it back.
            if docked != nil {
                undock()
                ignoringDrag = true
                return
            }
            ignoringDrag = false
            stopGlide()
            grab = NSEvent.mouseLocation
            origin = window.frame
            stretching = atCorner(convert(event.locationInWindow, from: nil))
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, !ignoringDrag else { return }
            let now = NSEvent.mouseLocation
            let dx = now.x - grab.x
            let dy = now.y - grab.y

            guard stretching else {
                window.setFrameOrigin(NSPoint(x: origin.minX + dx, y: origin.minY + dy))
                return
            }
            resize(to: origin.width + dx, from: origin)
        }

        /// Two fingers on the trackpad move the window. There is nothing to
        /// scroll here — the window holds one picture — so the gesture is free
        /// to mean the thing you actually want it to mean.
        ///
        /// And the pointer travels with it. Moving the window alone leaves the
        /// cursor behind: it drifts towards the edge, falls out, and the window
        /// stops answering mid-gesture. Carrying it keeps it at the same place
        /// in the frame, so the window can be pushed as far as the screen goes.
        override func scrollWheel(with event: NSEvent) {
            guard let window else { return }
            // Only while fingers are actually down. Letting the glide continue
            // would fling the pointer across the screen after them.
            guard event.momentumPhase == [] else { return }
            if Float.flicks { return flickWheel(with: event) }
            // Docked, and flicks turned off since: out first, where it was.
            if docked != nil { return undock() }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard dx != 0 || dy != 0 else { return }

            let spot = window.frame.origin
            window.setFrameOrigin(NSPoint(x: spot.x + dx, y: spot.y - dy))

            // Screen coordinates run up from the bottom, the cursor's run down
            // from the top of the first display.
            guard let ground = NSScreen.screens.first else { return }
            let mouse = NSEvent.mouseLocation
            CGWarpMouseCursorPosition(
                CGPoint(
                    x: mouse.x + dx,
                    y: ground.frame.height - (mouse.y - dy)
                )
            )
            // Without this the pointer and the physical trackpad stay parted
            // for a moment, and the next flick arrives from the wrong place.
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        /// Two fingers flick the window to a corner, as in Dia and Arc: a
        /// swipe up takes it to the top on the side it is on, a swipe left to
        /// the left at the height it is at, a diagonal one to that corner —
        /// one move a swipe, however long the swipe. Dragging it anywhere is
        /// still the click's.
        private var swipe: CGVector = .zero
        private var flicked = false
        /// For a wheel, which has no gesture to belong to: one flick a turn.
        private var lastWheelFlick = Date.distantPast

        private func flickWheel(with event: NSEvent) {
            // Which way the fingers went, on screen: with natural scrolling
            // the deltas run with the fingers, without it against them.
            let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let step = CGVector(dx: sign * event.scrollingDeltaX, dy: -sign * event.scrollingDeltaY)

            if event.phase == [] {
                // A mouse's wheel: every turn is a flick, a moment apart.
                guard Date().timeIntervalSince(lastWheelFlick) > 0.4, step != .zero else { return }
                lastWheelFlick = Date()
                if docked != nil {
                    if inward(step) { undock() }
                } else if let side = against(), outward(step, from: side) {
                    dock(side)
                } else {
                    flick(step)
                }
                return
            }
            if event.phase.contains(.began) {
                swipe = .zero
                flicked = false
                pulling = nil
                pullFrom = window?.frame.origin ?? .zero
            }
            swipe.dx += step.dx
            swipe.dy += step.dy
            let lifted = event.phase.contains(.ended) || event.phase.contains(.cancelled)

            // Docked: a swipe back towards the middle brings it out.
            if docked != nil {
                if !flicked, inward(swipe), abs(swipe.dx) > 24 || lifted {
                    flicked = true
                    undock()
                }
                if lifted {
                    swipe = .zero
                    flicked = false
                }
                return
            }

            // Against a side, and swiped at it: it gives, heavily, under the
            // fingers, and on lifting either goes into the side — only a
            // sliver left — or springs back out.
            if pulling == nil, !flicked, let side = against(), outward(swipe, from: side), abs(swipe.dx) > 6 {
                pulling = side
                // A spring still settling from the last one would pull the
                // other way, a frame at a time.
                stopGlide()
            }
            if pulling != nil {
                window?.setFrameOrigin(NSPoint(x: pullFrom.x + swipe.dx * Controls.give, y: pullFrom.y))
                // The window moves out from under the pointer as it gives, and
                // the fingers lifting can then be told to whatever is under
                // it instead: if nothing more comes, the pull is over anyway.
                settling?.cancel()
                let settle = DispatchWorkItem { [weak self] in self?.letGo() }
                settling = settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: settle)
                if lifted { letGo() }
                return
            }
            // Read from the whole swipe, as the fingers lift: a swipe often
            // sets off along one side before it turns diagonal, and read
            // early it went the wrong way. A long one doesn't wait.
            let length = hypot(swipe.dx, swipe.dy)
            if !flicked, length > 120 || (lifted && length > 20) {
                flicked = true
                flick(swipe)
            }
            if lifted {
                swipe = .zero
                flicked = false
            }
        }

        // Docking at a side, as in Dia: a strong swipe at the side the window
        // is against slides it off, leaving a sliver to bring it back by.
        enum Side { case left, right }
        private(set) var docked: Side?
        /// Where it was before it docked: where it goes back to.
        private(set) var dockedFrom: NSPoint?
        private var pulling: Side?
        private var pullFrom: NSPoint = .zero
        private var ignoringDrag = false
        /// How much of it stays on screen, docked.
        static let sliver: CGFloat = 10
        /// How far the fingers go at the side before letting go docks it.
        static let dockAt: CGFloat = 90
        /// How much the window gives under the fingers while pulled at a side.
        static let give: CGFloat = 0.35

        /// The usable part of the screen the window is on.
        private var area: NSRect? {
            if let made = Float.benchScreens, let window {
                let middle = NSPoint(x: window.frame.midX, y: window.frame.midY)
                return made.first { $0.contains(middle) } ?? made.first
            }
            return (window?.screen ?? NSScreen.main)?.visibleFrame
        }

        /// The side the window is up against, if it is, and if it can go
        /// into it.
        private func against() -> Side? {
            guard let window, let area else { return nil }
            let screens = Float.benchScreens ?? NSScreen.screens.map(\.frame)
            if window.frame.maxX >= area.maxX - 16,
               Float.dockable(window.frame, right: true, in: area, screens: screens) { return .right }
            if window.frame.minX <= area.minX + 16,
               Float.dockable(window.frame, right: false, in: area, screens: screens) { return .left }
            return nil
        }

        /// Clearly sideways, and at that side.
        private func outward(_ way: CGVector, from side: Side) -> Bool {
            abs(way.dx) > abs(way.dy) * 1.2 && (side == .right ? way.dx > 0 : way.dx < 0)
        }

        /// Back towards the middle from the side it is docked at.
        private func inward(_ way: CGVector) -> Bool {
            guard let docked else { return false }
            return abs(way.dx) > abs(way.dy) && (docked == .right ? way.dx < 0 : way.dx > 0)
        }

        private var settling: DispatchWorkItem?

        /// A pull at a side over: into the side, or back out.
        private func letGo() {
            settling?.cancel()
            settling = nil
            guard let side = pulling else { return }
            if outward(swipe, from: side), abs(swipe.dx) >= Controls.dockAt {
                dock(side, from: pullFrom)
            } else {
                glide(to: pullFrom, bouncing: true)
            }
            pulling = nil
            swipe = .zero
            flicked = false
        }

        private func dock(_ side: Side, from origin: NSPoint? = nil) {
            guard let window, let area else { return }
            dockedFrom = origin ?? window.frame.origin
            docked = side
            glide(to: Float.docked(window.frame, right: side == .right, in: area, sliver: Controls.sliver))
        }

        private func undock() {
            guard let window else { return }
            let back = dockedFrom ?? window.frame.origin
            docked = nil
            dockedFrom = nil
            glide(to: back, bouncing: true)
        }

        /// To the corner the swipe points at, a margin in from the edges of
        /// the screen's usable part.
        private func flick(_ way: CGVector) {
            guard let window, let area else { return }
            let target = Float.corner(for: window.frame, in: area, toward: way)
            guard target != window.frame.origin else { return }
            glide(to: target)
        }

        // The glide, a frame at a time off the display's own refresh — 120
        // a second on a ProMotion screen, where AppKit's window animation
        // stepped at 60 — on a critically damped spring: quick away,
        // settling into the corner without overshooting it.
        private var gliding: CADisplayLink?
        private var glideFrom: NSPoint = .zero
        private var glideTo: NSPoint = .zero
        private var glideStart: CFTimeInterval = 0
        /// Back out from a side: a spring that goes a little past and settles.
        private var glideBounces = false

        private func glide(to target: NSPoint, bouncing: Bool = false) {
            guard let window else { return }
            glideBounces = bouncing
            glideFrom = window.frame.origin
            glideTo = target
            glideStart = CACurrentMediaTime()
            if window.screen == nil {
                // On no screen — the bench's window, off every one — there
                // is no display to keep time by: a clock does instead.
                ticking = ticking ?? Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.glideStep() }
                }
            } else if gliding == nil {
                let link = displayLink(target: self, selector: #selector(glideStep(_:)))
                link.add(to: .main, forMode: .common)
                gliding = link
            }
        }

        private var ticking: Timer?

        @objc private func glideStep(_ link: CADisplayLink) { glideStep() }

        private func glideStep() {
            guard let window else { stopGlide(); return }
            let t = CGFloat(CACurrentMediaTime() - glideStart)
            let p: CGFloat
            let done: Bool
            if glideBounces {
                // Underdamped: past the place, and back to it.
                let omega: CGFloat = 16, zeta: CGFloat = 0.5
                let damped = omega * sqrt(1 - zeta * zeta)
                done = t > 0.9
                p = done ? 1 : 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta / sqrt(1 - zeta * zeta) * sin(damped * t))
            } else {
                let omega: CGFloat = 15
                done = t > 0.6
                p = done ? 1 : 1 - (1 + omega * t) * exp(-omega * t)
            }
            window.setFrameOrigin(NSPoint(
                x: glideFrom.x + (glideTo.x - glideFrom.x) * p,
                y: glideFrom.y + (glideTo.y - glideFrom.y) * p
            ))
            if done { stopGlide() }
        }

        private func stopGlide() {
            gliding?.invalidate()
            gliding = nil
            ticking?.invalidate()
            ticking = nil
        }

        /// A pinch sizes it about the pointer: whatever is under your fingers
        /// stays under your fingers, and the rest grows away from it. Sizing
        /// about the centre instead makes the picture slide sideways under a
        /// hand that never moved, which is what felt wrong.
        private var pinching: CGFloat = 0

        override func magnify(with event: NSEvent) {
            guard let window else { return }
            if event.phase == .began { pinching = 0 }
            pinching += event.magnification

            // Every event would mean a window resize, a web view relayout and a
            // video re-fit sixty times a second, which is the stutter. Moving
            // in steps of a fiftieth is below what an eye reads as a jump and
            // an order of magnitude less work.
            guard abs(pinching) > 0.02 else { return }
            let by = pinching
            pinching = 0
            resize(
                to: window.frame.width * (1 + by),
                from: window.frame,
                around: NSEvent.mouseLocation
            )
        }

        private func resize(to width: CGFloat, from was: NSRect, around anchor: NSPoint? = nil) {
            guard let window, was.width > 0 else { return }
            let area = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            // Apply the same height bound during pinch/drag resize as metadata
            // fitting, so a portrait player cannot grow taller than its screen.
            let request = CGRect(x: was.minX, y: was.minY, width: max(window.minSize.width, width), height: was.height)
            let wide = Float.mediaFrame(request, ratio: was.width / max(1, was.height), in: area)?.width ?? window.minSize.width
            let tall = wide * was.height / was.width

            let spot: NSPoint
            if let anchor {
                // Where the pointer sits within the window, as a fraction, kept
                // at the same fraction of the new one.
                let across = (anchor.x - was.minX) / was.width
                let up = (anchor.y - was.minY) / was.height
                spot = NSPoint(x: anchor.x - across * wide, y: anchor.y - up * tall)
            } else {
                spot = NSPoint(x: was.minX, y: was.maxY - tall)
            }
            // Not display: true — asking for an immediate redraw on every step
            // is what makes a live resize stutter. The next frame is soon
            // enough.
            window.setFrame(
                NSRect(x: spot.x, y: spot.y, width: wide, height: tall),
                display: false
            )
        }

        @objc private func pressedClose() { onClose?() }
        @objc private func pressedReturn() { onReturn?() }
        @objc private func pressedRewind() { onSkip?(-15) }
        @objc private func pressedForward() { onSkip?(15) }
        @objc private func pressedPause() {
            if media.available && !media.failed { onPlayPause?() }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu(), speed = NSMenu()
            for rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
                let item = NSMenuItem(title: rate == 1 ? "Normal" : "\(rate)×", action: #selector(changedRate(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = rate
                item.state = abs(media.rate - rate) < 0.001 ? .on : .off
                item.isEnabled = media.available && !media.failed; speed.addItem(item)
            }
            speed.autoenablesItems = false
            let item = NSMenuItem(title: "Playback speed", action: nil, keyEquivalent: ""); item.submenu = speed; menu.addItem(item)
            return menu
        }
        @objc private func changedRate(_ sender: NSMenuItem) {
            guard media.available && !media.failed, let rate = sender.representedObject as? Double else { return }; onRate?(rate)
        }
        @objc private func pressedMute() { if media.available && !media.failed { onMute?() } }
        @objc private func sought() {
            guard media.seekable else { return }
            // Preview the requested position immediately; the next source
            // update confirms its real position within the seekable ranges.
            time.stringValue = FloatMediaState.clock(timeline.doubleValue * media.duration) + " / " + FloatMediaState.clock(media.duration)
            onSeek?(timeline.doubleValue)
        }
        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { fade(to: 1); return true }
        override func keyDown(with event: NSEvent) { if !takeKey(event) { super.keyDown(with: event) } }
        func takeKey(_ event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers?.lowercased() == "w" { pressedClose(); return true }; return false
            }
            guard event.modifierFlags.isDisjoint(with: [.control, .option]) else { return false }
            fade(to: 1)
            switch event.keyCode {
            case 49: pressedPause()
            case 123: if media.canSkip { onSkip?(-15) }
            case 124: if media.canSkip { onSkip?(15) }
            case 46: pressedMute()
            case 53: pressedClose()
            case 36: pressedReturn()
            default: return false
            }
            return true
        }
        private final class MediaSlider: NSSlider {
            var trackingSeek = false
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func mouseDown(with event: NSEvent) {
                trackingSeek = true; defer { trackingSeek = false }; super.mouseDown(with: event)
            }
        }
        private final class MediaButton: NSButton {
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        }

    }
}

/// Sites with a player worth following into the little window.
///
/// Anywhere else, a playing video is as likely to be a background as a film,
/// and the difference isn't something a script can tell from the outside. So
/// the list is of places people go to watch, and the shortcut covers the rest.
enum Players {
    /// A host suffix, and for a few shops that also stream, the path that
    /// separates the film from the product page.
    private static let known: [(host: String, path: String?)] = [
        ("youtube.com", nil), ("youtu.be", nil), ("netflix.com", nil),
        ("primevideo.com", nil), ("amazon.com", "/gp/video"), ("amazon.fr", "/gp/video"),
        ("amazon.co.uk", "/gp/video"), ("amazon.de", "/gp/video"),
        ("disneyplus.com", nil), ("tv.apple.com", nil), ("twitch.tv", nil),
        ("vimeo.com", nil), ("dailymotion.com", nil), ("max.com", nil), ("hbomax.com", nil),
        ("canalplus.com", nil), ("mycanal.fr", nil), ("arte.tv", nil), ("france.tv", nil),
        ("tf1.fr", nil), ("6play.fr", nil), ("crunchyroll.com", nil), ("plex.tv", nil),
        ("peacocktv.com", nil), ("hulu.com", nil), ("paramountplus.com", nil),
        ("molotov.tv", nil), ("ocs.fr", nil), ("mubi.com", nil), ("criterionchannel.com", nil),
        ("ted.com", nil), ("nebula.tv", nil), ("curiositystream.com", nil),
    ]

    static func knows(_ url: URL?) -> Bool {
        guard let url, let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        return known.contains { entry in
            guard host == entry.host || host.hasSuffix("." + entry.host) else { return false }
            guard let needle = entry.path else { return true }
            return path.hasPrefix(needle)
        }
    }
}

/// Sites whose videos never float out on their own: the site card's Don't
/// Float Videos Here (#267). Only switching tabs or apps is held back; ⇧⌘P
/// still lifts one by hand. Kept by host, as a site's sound is, and
/// forgotten with the other site choices (Browser.forgetCaptureChoices).
enum Grounded {
    static let prefix = "nofloat."

    static func holds(_ host: String) -> Bool {
        Store.settings.bool(forKey: prefix + host)
    }

    /// Off keeps nothing, as Autoplay's does.
    static func set(_ on: Bool, for host: String) {
        if on {
            Store.settings.set(true, forKey: prefix + host)
        } else {
            Store.settings.removeObject(forKey: prefix + host)
        }
    }
}

/// A panel that takes key status without bringing the whole app forward.
///
/// Borderless windows refuse to become key by default, and a window that never
/// becomes key is a window the system stops routing gestures to.
private final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum Isolate {
    /// Everything but the video, out of the way. Visibility is inherited, so
    /// hiding the body and turning it back on for the video alone leaves the
    /// player's own machinery running untouched — which is what keeps the
    /// stream alive where cutting the DOM about would kill it.
    static let on = """
    (function () {
      var videos = document.querySelectorAll('video');
      var best = null, area = 0;
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (v.paused || v.ended || v.readyState < 2) continue;
        var box = v.getBoundingClientRect();
        if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
      }
      if (!best) return 'none';

      // A landing still waiting for its tab is called off: the page is out
      // again.
      window.__officeFloatLanding = null;
      best.setAttribute('data-office-float', '');
      var known = new Set(videos), containers = [], parent = best.parentElement;
      while (parent && parent !== document.body && parent !== document.documentElement) { containers.push(parent); parent = parent.parentElement; }

      var sheet = document.getElementById('office-float');
      if (!sheet) {
        sheet = document.createElement('style');
        sheet.id = 'office-float';
        (document.head || document.documentElement).appendChild(sheet);
      }
      sheet.textContent = [
        'html.office-floating, html.office-floating body {',
        'background:#000 !important; overflow:hidden !important; margin:0 !important}',
        'html.office-floating body > * { visibility:hidden !important }',
        'html.office-floating [data-office-float] {',
        'visibility:visible !important; position:fixed !important;',
        'left:0 !important; top:0 !important; right:0 !important; bottom:0 !important;',
        'width:100vw !important; height:100vh !important;',
        'max-width:none !important; max-height:none !important;',
        // Players such as Netflix center the element with a translation.
        // With our top/left at zero, that moves it out of the floating window.
        'transform:none !important; translate:none !important; rotate:none !important; scale:none !important;',
        'opacity:1 !important; object-fit:contain !important; z-index:2147483647 !important}',
        // Netflix renders timed text after the video, in a layer of its own
        // beside it or one level up. Keep it above the video without
        // exposing the rest of the player.
        'html.office-floating [data-office-float] ~ .player-timedtext,',
        'html.office-floating :has(> [data-office-float]) > .player-timedtext,',
        'html.office-floating :has([data-office-float]) > .player-timedtext {',
        'visibility:visible !important; z-index:2147483647 !important}',
        // Fixed or not, the video is still cut to the box of any ancestor
        // that clips — YouTube's player does — and in a window this small
        // that box sits partly or wholly off screen, more so on a page that
        // was scrolled. That was the black window.
        'html.office-floating body :has([data-office-float]) {',
        'overflow:visible !important;',
        // And fixed is only fixed to the window while no ancestor makes a
        // box of its own for it: a transform, a filter, containment, a
        // perspective, a backdrop, a container query — Twitch's player has
        // some — and the video was placed and sized inside that box instead,
        // part of it or none of it in the window. An ancestor drawn only
        // when on screen (content-visibility) wasn't drawn at all once the
        // rest of the page was hidden, and one faded out hid the video too.
        'transform:none !important; translate:none !important; rotate:none !important; scale:none !important;',
        'filter:none !important; backdrop-filter:none !important; -webkit-backdrop-filter:none !important;',
        'perspective:none !important; contain:none !important; container-type:normal !important;',
        'will-change:auto !important; content-visibility:visible !important;',
        'clip-path:none !important; mask:none !important; -webkit-mask:none !important;',
        'opacity:1 !important}',
        // The player's own controls would sit under ours, and two sets of
        // buttons on one small window is one set too many.
        'html.office-floating [data-office-float]::-webkit-media-controls {',
        'display:none !important}'
      ].join('');
      document.documentElement.classList.add('office-floating');

      // The mark has to be defended.
      //
      // Everything but the marked element is hidden, so the moment a player
      // rebuilds its DOM — and they all do, on a quality change, an ad break,
      // a React re-render — the mark goes with the old element and the window
      // turns pure black while still holding a perfectly live page. That is the
      // black rectangle, and it is not an orphaned window at all.
      //
      // Follow replacements in the original player container, including a
      // paused or loading replacement, four times a second while floated.
      clearInterval(window.__officeFloatWatch);
      window.__officeFloatWatch = setInterval(function () {
        if (document.querySelector('[data-office-float]')) return;
        var again = null, most = -1;
        var container = containers.find(function (node) { return node.isConnected; });
        var all = (container || document).querySelectorAll('video');
        for (var j = 0; j < all.length; j++) {
          var one = all[j];
          // Elsewhere on the page, an existing background video is not our player.
          if (!container && known.has(one) && one !== best) continue;
          var shape = one.getBoundingClientRect();
          if (shape.width * shape.height > most) { most = shape.width * shape.height; again = one; }
        }
        if (again) again.setAttribute('data-office-float', '');
      }, 250);

      return 'floating';
    })();
    """

    /// Stop or start it, and say which it is now.
    /// Step over the bit you missed, or back to it.
    private static func seekCommand(_ expression: String, finite: Bool = true) -> String {
        """
        (function () {
          var video = document.querySelector('[data-office-float]') || (!document.documentElement.classList.contains('office-floating') ? document.querySelector('video') : null);
          if (!video || !video.seekable.length) return false;
          if (\(finite ? "true" : "false") && (!isFinite(video.duration) || video.duration <= 0)) return false;
          var wanted = Math.max(0, \(expression)), nearest = null, distance = Infinity;
          if (isFinite(video.duration) && video.duration > 0) wanted = Math.min(video.duration, wanted);
          for (var i = 0; i < video.seekable.length; i++) {
            var candidate = Math.max(video.seekable.start(i), Math.min(video.seekable.end(i), wanted));
            if (Math.abs(candidate - wanted) < distance) { nearest = candidate; distance = Math.abs(candidate - wanted); }
          }
          if (nearest === null) return false;
          try { video.currentTime = nearest; return true; } catch (_) { return false; }
        })();
        """
    }
    static func skip(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "false" }
        return seekCommand("video.currentTime + (\(seconds))", finite: false)
    }
    static func seek(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "false" }
        return seekCommand("video.duration * (\(min(1, max(0, fraction))))")
    }
    static func rate(_ value: Double) -> String {
        guard [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].contains(value) else { return "false" }
        return """
        (function () { var video = document.querySelector('[data-office-float]');
          if (!video) return false;
          try { video.playbackRate = \(value); return video.playbackRate === \(value); } catch (_) { return false; }
        })();
        """
    }

    static let mediaState = """
    (function () {
      var video = document.querySelector('[data-office-float]') || (!document.documentElement.classList.contains('office-floating') ? document.querySelector('video') : null);
      if (!video) return null;
      var finite = isFinite(video.duration) && video.duration > 0;
      return { available: true, loading: video.readyState < 2 && !video.error,
        buffering: !video.paused && !video.ended && video.readyState < 3,
        ended: video.ended, failed: !!video.error, live: video.duration === Infinity, rate: video.playbackRate, width: video.videoWidth, height: video.videoHeight,
        current: isFinite(video.currentTime) ? video.currentTime : 0,
        duration: finite ? video.duration : 0, playing: !video.paused && !video.ended,
        muted: video.muted || video.volume === 0, seekable: finite && video.seekable.length > 0, canSkip: video.seekable.length > 0 };
    })();
    """
    static let mute = """
    (function () { var video = document.querySelector('[data-office-float]') || (!document.documentElement.classList.contains('office-floating') ? document.querySelector('video') : null);
      if (!video) return false; video.muted = !(video.muted || video.volume === 0);
      if (!video.muted && video.volume === 0) video.volume = 1;
      return video.muted; })();
    """

    /// How far through, and whether it is running.
    static let where_ = """
    (function () {
      var video = document.querySelector('[data-office-float]')
        || (!document.documentElement.classList.contains('office-floating') ? document.querySelector('video') : null);
      if (!video || !video.duration || !isFinite(video.duration)) return [0, true];
      return [video.currentTime / video.duration, !video.paused];
    })();
    """

    static let toggle = """
    (function () {
      var video = document.querySelector('[data-office-float]')
        || (!document.documentElement.classList.contains('office-floating') ? document.querySelector('video') : null);
      if (!video) return false;
      if (video.paused || video.ended) {
        if (video.ended) { try { video.currentTime = video.seekable.length ? video.seekable.start(0) : 0; } catch (_) {} }
        video.play().catch(function () {});
      } else { video.pause(); }
      return !video.paused;
    })();
    """

    /// Everything back as it was — once the page is back in its tab and laid
    /// out at the tab's size. Put back at once, while the page still had
    /// the little window's size, the player fitted the video to that, and
    /// the tab's first frames could show it so: YouTube's, 720×240 in a
    /// 720×405 window, dropped to a strip before it grew again (#257).
    static let off = """
    (function () {
      // The engine may have put the video in its own floating window as well —
      // some players ask for that themselves. Leaving one and not the other
      // leaves you with two.
      try {
        var out = document.querySelector('video[data-office-float]')
          || (!document.documentElement.classList.contains('office-floating') ? document.querySelector('video') : null);
        if (out) {
          if (out.webkitPresentationMode === 'picture-in-picture') {
            out.webkitSetPresentationMode('inline');
          }
          if (document.pictureInPictureElement && document.exitPictureInPicture) {
            document.exitPictureInPicture();
          }
        }
      } catch (e) {}

      var root = document.documentElement;
      var landing = window.__officeFloatLanding = {};
      function put() {
        // Floated again in the meantime: that is the float's now.
        if (window.__officeFloatLanding !== landing) return;
        window.__officeFloatLanding = null;
        clearInterval(window.__officeFloatWatch);
        window.__officeFloatWatch = null;
        root.classList.remove('office-floating');
        var sheet = document.getElementById('office-float');
        if (sheet) sheet.textContent = '';
        var video = document.querySelector('[data-office-float]');
        if (video) video.removeAttribute('data-office-float');
      }
      // Each frame until the page is laid out at another size than the
      // little window's — the tab's — and its player has had that frame's
      // resize to fit the video to it. A page not drawn, its tab no longer
      // the one in front, is put back by the clock.
      var wide = innerWidth, high = innerHeight, began = Date.now();
      (function frame() {
        if (window.__officeFloatLanding !== landing) return;
        if (innerWidth !== wide || innerHeight !== high || Date.now() - began > 400) return put();
        requestAnimationFrame(frame);
      })();
      setTimeout(put, 1000);
      return 'landing';
    })();
    """
}
