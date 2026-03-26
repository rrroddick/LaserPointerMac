import AppKit

final class OverlayWindowManager {
    private var overlayWindows: [NSScreen: OverlayWindow] = [:]
    private var currentMousePosition: CGPoint = .zero
    private var isArrowDrawing = false
    private var arrowStartPoint: CGPoint? = nil

    func showOverlay() {
        hideOverlay()

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            window.orderFrontRegardless()
            overlayWindows[screen] = window
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
        // Ensure overlay windows exist even if laser is not currently active
        if overlayWindows.isEmpty {
            for screen in NSScreen.screens {
                let window = OverlayWindow(screen: screen)
                window.orderFrontRegardless()
                overlayWindows[screen] = window
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

    func addFreehandPoint(_ point: CGPoint) {
        for (_, window) in overlayWindows {
            window.overlayView.addFreehandPoint(point)
        }
    }

    @objc private func screensChanged() {
        showOverlay()
        updateMousePosition(currentMousePosition)
        setArrowDrawing(isArrowDrawing)
        setArrowStartPoint(arrowStartPoint)
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

// MARK: - Overlay View (renders laser, arrow, and freehand)

final class OverlayView: NSView {
    var mousePosition: CGPoint = .zero {
        didSet { needsDisplay = true }
    }

    var isArrowDrawing: Bool = false {
        didSet { needsDisplay = true }
    }

    var arrowStartPoint: CGPoint? = nil {
        didSet { needsDisplay = true }
    }

    // MARK: Freehand State
    private(set) var isFreehandDrawing: Bool = false
    private var freehandPoints: [CGPoint] = []
    private var freehandAlpha: CGFloat = 1.0
    private var isFading: Bool = false
    private var fadeStartTime: CFTimeInterval = 0
    private var fadeDuration: CFTimeInterval = 1.0

    private let settings = SettingsStore.shared
    private var displayLink: CVDisplayLink?
    private var animationPhase: CGFloat = 0

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
        // Cancel any ongoing fade first
        isFading = false
        freehandAlpha = 1.0
        freehandPoints = []
        isFreehandDrawing = true
        needsDisplay = true
    }

    func addFreehandPoint(_ screenPoint: CGPoint) {
        guard isFreehandDrawing else { return }
        freehandPoints.append(screenPoint)
        needsDisplay = true
    }

    func endFreehandDraw() {
        isFreehandDrawing = false
        guard !freehandPoints.isEmpty else { return }
        fadeDuration = settings.freehandFadeDuration
        freehandAlpha = 1.0
        fadeStartTime = CACurrentMediaTime()
        isFading = true
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }

        CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
            let view = Unmanaged<OverlayView>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                view.animationPhase += 0.03
                if view.animationPhase > .pi * 2 { view.animationPhase -= .pi * 2 }

                // Update freehand fade
                if view.isFading {
                    let elapsed = CACurrentMediaTime() - view.fadeStartTime
                    let progress = min(elapsed / view.fadeDuration, 1.0)
                    view.freehandAlpha = CGFloat(1.0 - progress)
                    if progress >= 1.0 {
                        view.isFading = false
                        view.freehandPoints = []
                        view.freehandAlpha = 0
                    }
                }

                view.needsDisplay = true
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(displayLink)
    }

    private func stopDisplayLink() {
        guard let displayLink else { return }
        CVDisplayLinkStop(displayLink)
        self.displayLink = nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        let viewPoint = convertScreenToView(mousePosition)

        // Only draw laser if there is an active laser (mousePosition is tracked)
        // We draw laser when the overlay is shown via showOverlay()
        // Freehand can show independently — check if we have points or drawing state
        let hasFreehand = isFreehandDrawing || isFading

        if !hasFreehand || AppState.shared.isLaserActive {
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

    // MARK: - Laser Rendering

    private func drawLaser(in context: CGContext, at point: CGPoint) {
        let size = CGFloat(settings.laserSize)
        let opacity = CGFloat(settings.laserOpacity)
        let color = settings.laserNSColor.withAlphaComponent(opacity)
        let borderWidth = CGFloat(settings.laserBorderWidth)
        let animated = settings.laserAnimationEnabled
        let pulse: CGFloat = animated ? 1.0 + 0.1 * sin(animationPhase) : 1.0

        switch settings.laserType {
        case .dot:
            drawDot(in: context, at: point, size: size * pulse, color: color)
        case .ring:
            drawRing(in: context, at: point, size: size * pulse, color: color, borderWidth: borderWidth)
        case .glow:
            drawGlow(in: context, at: point, size: size * pulse, color: color)
        case .spotlight:
            drawSpotlight(in: context, at: point, size: size * pulse, color: color)
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
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.cgColor,
                color.withAlphaComponent(0.3).cgColor,
                color.withAlphaComponent(0.0).cgColor
            ] as CFArray,
            locations: [0, 0.4, 1.0]
        )!

        context.drawRadialGradient(
            gradient,
            startCenter: point, startRadius: 0,
            endCenter: point, endRadius: size,
            options: .drawsAfterEndLocation
        )
    }

    private func drawSpotlight(in context: CGContext, at point: CGPoint, size: CGFloat, color: NSColor) {
        let coreSize = size * 0.3
        let coreRect = CGRect(x: point.x - coreSize / 2, y: point.y - coreSize / 2, width: coreSize, height: coreSize)
        context.setFillColor(color.withAlphaComponent(0.9).cgColor)
        context.fillEllipse(in: coreRect)

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlphaComponent(0.6).cgColor,
                color.withAlphaComponent(0.2).cgColor,
                color.withAlphaComponent(0.0).cgColor
            ] as CFArray,
            locations: [0, 0.5, 1.0]
        )!

        context.drawRadialGradient(
            gradient,
            startCenter: point, startRadius: coreSize / 2,
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

        context.setStrokeColor(color.cgColor)
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

        context.setFillColor(color.cgColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    // MARK: - Freehand Rendering

    private func drawFreehand(in context: CGContext) {
        guard freehandPoints.count > 1 else { return }

        let baseColor = settings.freehandNSColor
        let baseOpacity = CGFloat(settings.freehandOpacity)
        let lineWidth = CGFloat(settings.freehandLineWidth)
        let alpha = baseOpacity * freehandAlpha
        let color = baseColor.withAlphaComponent(alpha)

        let viewPoints = freehandPoints.map { convertScreenToView($0) }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: viewPoints[0])
        for point in viewPoints.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }
}
