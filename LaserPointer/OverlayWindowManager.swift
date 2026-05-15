import AppKit

final class OverlayWindowManager {
    private var overlayWindows: [NSScreen: OverlayWindow] = [:]
    private var currentMousePosition: CGPoint = .zero
    private var isArrowDrawing = false
    private var arrowStartPoint: CGPoint? = nil

    func showOverlay() {
        hideOverlay()

        for screen in NSScreen.screens {
            overlayWindows[screen] = makeOverlayWindow(screen: screen, laserActive: true)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func hideOverlay() {
        for (_, window) in overlayWindows {
            // Invalidate the display link before releasing the window so the
            // CADisplayLink strong-target reference is dropped here, letting
            // OverlayView reach retain count 0 and deinit normally.
            window.overlayView.stopDisplayLink()
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func updateMousePosition(_ position: CGPoint) {
        currentMousePosition = position
        for (_, window) in overlayWindows {
            window.overlayView.mousePosition = position
            if window.overlayView.isFreehandDrawing {
                window.overlayView.addFreehandPoint(position)
            }
        }
    }

    func setArrowDrawing(_ drawing: Bool) {
        isArrowDrawing = drawing
        for (_, window) in overlayWindows {
            window.overlayView.isArrowDrawing = drawing
        }
    }

    func setArrowStartPoint(_ point: CGPoint?) {
        arrowStartPoint = point
        for (_, window) in overlayWindows {
            window.overlayView.arrowStartPoint = point
        }
    }

    // MARK: - Freehand

    func startFreehandDraw() {
        if overlayWindows.isEmpty {
            for screen in NSScreen.screens {
                overlayWindows[screen] = makeOverlayWindow(screen: screen, laserActive: false)
            }
        }
        for (_, window) in overlayWindows {
            window.overlayView.startFreehandDraw()
        }
    }

    func endFreehandDraw() {
        for (_, window) in overlayWindows {
            window.overlayView.endFreehandDraw()
        }
    }

    @objc private func screensChanged() {
        showOverlay()
        updateMousePosition(currentMousePosition)
        setArrowDrawing(isArrowDrawing)
        setArrowStartPoint(arrowStartPoint)
    }

    private func makeOverlayWindow(screen: NSScreen, laserActive: Bool) -> OverlayWindow {
        let window = OverlayWindow(screen: screen)
        window.overlayView.isLaserActive = laserActive
        window.orderFrontRegardless()
        return window
    }
}

// MARK: - Overlay Window

final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    init(screen: NSScreen) {
        let frame = screen.frame
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.contentView = overlayView
        self.isMovableByWindowBackground = false
    }
}

// MARK: - Display Link Proxy
// Holds a weak reference to OverlayView so CADisplayLink (which strongly retains
// its target) does not form a retain cycle with the view.

private final class DisplayLinkProxy: NSObject {
    weak var view: OverlayView?

    @objc func tick(_ link: CADisplayLink) {
        view?.displayLinkTick(link)
    }
}

// MARK: - Overlay View (renders laser, arrow, and freehand)

final class OverlayView: NSView {
    var isLaserActive: Bool = false

    var mousePosition: CGPoint = .zero {
        didSet {
            guard mousePosition != oldValue else { return }
            // When only the laser dot is visible, invalidate just the area it occupies
            // (old position + new position) rather than the entire screen.
            if !isArrowDrawing, !isFreehandDrawing, !isFading, window != nil {
                let oldView = convertScreenToView(oldValue)
                let newView = convertScreenToView(mousePosition)
                setNeedsDisplay(laserDirtyRect(from: oldView, to: newView))
            } else {
                needsDisplay = true
            }
        }
    }

    var isArrowDrawing: Bool = false {
        didSet { if isArrowDrawing != oldValue { needsDisplay = true } }
    }

    var arrowStartPoint: CGPoint? = nil {
        didSet { if arrowStartPoint != oldValue { needsDisplay = true } }
    }

    // MARK: Freehand State
    private(set) var isFreehandDrawing: Bool = false
    private var freehandViewPoints: [CGPoint] = []
    private var freehandAlpha: CGFloat = 1.0
    private var isFading: Bool = false
    private var fadeStartTime: CFTimeInterval = 0
    private var fadeDuration: CFTimeInterval = 1.0

    private let settings = SettingsStore.shared
    private var caDisplayLink: CADisplayLink?
    private var caDisplayLinkProxy: DisplayLinkProxy?
    private var animationPhase: CGFloat = 0

    private var cachedGradient: CGGradient?
    private var cachedGradientColorHex: String = ""
    private var cachedGradientOpacity: Double = -1
    private var lastDisplayLinkTime: CFTimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        startDisplayLink()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        stopDisplayLink()
    }

    // MARK: - Freehand Public API

    func startFreehandDraw() {
        isFading = false
        freehandAlpha = 1.0
        freehandViewPoints.removeAll(keepingCapacity: true)
        isFreehandDrawing = true
        needsDisplay = true
    }

    // Minimum squared distance (2pt) between consecutive freehand points.
    // Prevents unbounded CGPath growth during slow or long drawing strokes.
    private static let minFreehandDistanceSq: CGFloat = 4

    func addFreehandPoint(_ screenPoint: CGPoint) {
        guard isFreehandDrawing else { return }
        let viewPoint = convertScreenToView(screenPoint)
        if let last = freehandViewPoints.last {
            let dx = viewPoint.x - last.x
            let dy = viewPoint.y - last.y
            guard dx * dx + dy * dy >= Self.minFreehandDistanceSq else { return }
        }
        freehandViewPoints.append(viewPoint)
        // needsDisplay is already set by mousePosition.didSet for the same position update
    }

    func endFreehandDraw() {
        isFreehandDrawing = false
        guard !freehandViewPoints.isEmpty else { return }
        fadeDuration = settings.freehandFadeDuration
        freehandAlpha = 1.0
        fadeStartTime = CACurrentMediaTime()
        isFading = true
        // Ensure the display link is running for the fade animation.
        caDisplayLink?.isPaused = false
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        let proxy = DisplayLinkProxy()
        proxy.view = self
        // NSView.displayLink automatically uses the refresh rate of the screen
        // this view is displayed on, updating correctly when the window moves screens.
        let link = displayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        caDisplayLink = link
        caDisplayLinkProxy = proxy
    }

    fileprivate func stopDisplayLink() {
        caDisplayLink?.invalidate()
        caDisplayLink = nil
        caDisplayLinkProxy = nil
    }

    // Fired directly on the main thread by CADisplayLink — no DispatchQueue.main.async needed.
    fileprivate func displayLinkTick(_ link: CADisplayLink) {
        // link.timestamp is the vsync time; cap dt so sleep/wake never causes a phase jump.
        let now = link.timestamp
        let dt = lastDisplayLinkTime > 0
            ? min(now - lastDisplayLinkTime, 1.0 / 30.0)
            : 0
        lastDisplayLinkTime = now

        let animating = settings.laserAnimationEnabled
        if animating {
            // 1.8 rad/s = constant pulse speed regardless of display refresh rate
            animationPhase += CGFloat(dt * 1.8)
            if animationPhase > .pi * 2 { animationPhase -= .pi * 2 }
        }

        if isFading {
            let elapsed = now - fadeStartTime
            let progress = min(elapsed / fadeDuration, 1.0)
            freehandAlpha = CGFloat(1.0 - progress)
            if progress >= 1.0 {
                isFading = false
                freehandViewPoints.removeAll(keepingCapacity: true)
                freehandAlpha = 0
            }
        }

        // Only redraw if the display link itself has something to animate.
        // Mouse-movement redraws are handled by the mousePosition property observer.
        if animating || isFading {
            needsDisplay = true
        } else {
            // Nothing to animate — suspend until animation or fading resumes.
            caDisplayLink?.isPaused = true
            lastDisplayLinkTime = 0
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Clear only the invalidated region, not the entire screen surface.
        context.clear(dirtyRect)

        let hasFreehand = isFreehandDrawing || isFading
        let needsViewPoint = isLaserActive || !hasFreehand || isArrowDrawing
        let viewPoint = needsViewPoint ? convertScreenToView(mousePosition) : .zero

        if !hasFreehand || isLaserActive {
            drawLaser(in: context, at: viewPoint)
        }

        if isArrowDrawing, let start = arrowStartPoint {
            let startView = convertScreenToView(start)
            drawArrow(in: context, from: startView, to: viewPoint)
        }

        if isFreehandDrawing || (isFading && freehandAlpha > 0) {
            drawFreehand(in: context)
        }
    }

    private func convertScreenToView(_ screenPoint: CGPoint) -> CGPoint {
        guard let window = self.window else { return screenPoint }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        return convert(windowPoint, from: nil)
    }

    private func laserDirtyRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        // Read laserSize once; padding covers pulse (±10%) and glow gradient edge.
        let radius = CGFloat(settings.laserSize) * 1.2 + 10
        let rectA = CGRect(x: a.x - radius, y: a.y - radius, width: radius * 2, height: radius * 2)
        let rectB = CGRect(x: b.x - radius, y: b.y - radius, width: radius * 2, height: radius * 2)
        return rectA.union(rectB)
    }

    // MARK: - Laser Rendering

    private func drawLaser(in context: CGContext, at point: CGPoint) {
        let size = CGFloat(settings.laserSize)
        let color = settings.laserDisplayColor
        let borderWidth = CGFloat(settings.laserBorderWidth)
        let animated = settings.laserAnimationEnabled
        // If animation was just re-enabled while the link was suspended, wake it.
        if animated, caDisplayLink?.isPaused == true {
            caDisplayLink?.isPaused = false
        }
        let pulse: CGFloat = animated ? 1.0 + 0.1 * sin(animationPhase) : 1.0

        switch settings.laserType {
        case .dot:
            drawDot(in: context, at: point, size: size * pulse, color: color)
        case .ring:
            drawRing(in: context, at: point, size: size * pulse, color: color, borderWidth: borderWidth)
        case .glow:
            drawGlow(in: context, at: point, size: size * pulse, color: color)
        }
    }

    private func drawDot(in context: CGContext, at point: CGPoint, size: CGFloat, color: NSColor) {
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)
    }

    private func drawRing(in context: CGContext, at point: CGPoint, size: CGFloat, color: NSColor, borderWidth: CGFloat) {
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(borderWidth)
        context.strokeEllipse(in: rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
    }

    private func drawGlow(in context: CGContext, at point: CGPoint, size: CGFloat, color: NSColor) {
        if cachedGradient == nil
            || cachedGradientColorHex != settings.laserColorHex
            || cachedGradientOpacity != settings.laserOpacity {
            cachedGradientColorHex = settings.laserColorHex
            cachedGradientOpacity = settings.laserOpacity
            cachedGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    color.cgColor,
                    color.withAlphaComponent(0.3).cgColor,
                    color.withAlphaComponent(0.0).cgColor
                ] as CFArray,
                locations: [0, 0.4, 1.0]
            )
        }
        guard let gradient = cachedGradient else { return }

        context.drawRadialGradient(
            gradient,
            startCenter: point, startRadius: 0,
            endCenter: point, endRadius: size,
            options: .drawsAfterEndLocation
        )
    }

    // MARK: - Arrow Rendering

    private func drawArrow(in context: CGContext, from start: CGPoint, to end: CGPoint) {
        let color = settings.arrowNSColor
        let lineWidth = CGFloat(settings.arrowLineWidth)
        let headSize = CGFloat(settings.arrowHeadSize)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)

        guard length > 5 else { return }

        let angle = atan2(dy, dx)
        let cgColor = color.cgColor

        context.setStrokeColor(cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let headAngle: CGFloat = .pi / 6
        let p1 = CGPoint(
            x: end.x - headSize * cos(angle - headAngle),
            y: end.y - headSize * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headSize * cos(angle + headAngle),
            y: end.y - headSize * sin(angle + headAngle)
        )

        context.setFillColor(cgColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    // MARK: - Freehand Rendering

    private func drawFreehand(in context: CGContext) {
        guard freehandViewPoints.count > 1 else { return }

        let baseOpacity = CGFloat(settings.freehandOpacity)
        let lineWidth = CGFloat(settings.freehandLineWidth)
        let alpha = baseOpacity * freehandAlpha
        // CGColor.copy(alpha:) is a CF-level operation — much cheaper than NSColor.withAlphaComponent
        // which allocates a full NSColor object on every fade frame.
        let baseCGColor = settings.freehandNSColor.cgColor
        let cgColor = baseCGColor.copy(alpha: alpha) ?? baseCGColor

        context.setStrokeColor(cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: freehandViewPoints[0])
        for point in freehandViewPoints.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }
}
