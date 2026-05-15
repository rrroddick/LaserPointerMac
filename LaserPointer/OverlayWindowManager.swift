import AppKit
import Combine

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
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func hideOverlay() {
        for (_, window) in overlayWindows { window.orderOut(nil) }
        overlayWindows.removeAll()
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
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
        for (_, window) in overlayWindows { window.overlayView.isArrowDrawing = drawing }
    }

    func setArrowStartPoint(_ point: CGPoint?) {
        arrowStartPoint = point
        for (_, window) in overlayWindows { window.overlayView.arrowStartPoint = point }
    }

    func startFreehandDraw() {
        if overlayWindows.isEmpty {
            for screen in NSScreen.screens {
                overlayWindows[screen] = makeOverlayWindow(screen: screen, laserActive: false)
            }
        }
        for (_, window) in overlayWindows { window.overlayView.startFreehandDraw() }
    }

    func endFreehandDraw() {
        for (_, window) in overlayWindows { window.overlayView.endFreehandDraw() }
    }

    @objc private func screensChanged() {
        showOverlay()
        updateMousePosition(currentMousePosition)
        setArrowDrawing(isArrowDrawing)
        setArrowStartPoint(arrowStartPoint)
    }

    private func makeOverlayWindow(screen: NSScreen, laserActive: Bool) -> OverlayWindow {
        let window = OverlayWindow(screen: screen)
        window.orderFrontRegardless()               // window on screen BEFORE setting state
        window.overlayView.isLaserActive = laserActive
        return window
    }
}

// MARK: - Overlay Window

final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    init(screen: NSScreen) {
        let frame = screen.frame
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
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

// MARK: - Overlay View

final class OverlayView: NSView {

    var isLaserActive: Bool = false {
        didSet { if isLaserActive != oldValue { updateLaserVisibility() } }
    }

    var mousePosition: CGPoint = .zero {
        didSet {
            guard mousePosition != oldValue else { return }
            updatePositions()
        }
    }

    var isArrowDrawing: Bool = false {
        didSet {
            guard isArrowDrawing != oldValue else { return }
            if !isArrowDrawing {
                noAnimation { arrowLayer.path = nil; arrowLayer.isHidden = true }
            }
        }
    }

    var arrowStartPoint: CGPoint? = nil {
        didSet { if arrowStartPoint != oldValue { updateArrowPath() } }
    }

    private(set) var isFreehandDrawing: Bool = false
    private var freehandViewPoints: [CGPoint] = []
    private var freehandPath = CGMutablePath()

    private let settings = SettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    // Dot / Ring rendered by CAShapeLayer.
    private let laserShapeLayer = CAShapeLayer()
    // Glow rendered as a pre-baked CGImage inside a plain CALayer.
    // Using CALayer (not CAGradientLayer) so that transform and opacity
    // animations work reliably on macOS — CAGradientLayer ignores them.
    private let laserGlowLayer  = CALayer()

    private let arrowLayer    = CAShapeLayer()
    private let freehandLayer = CAShapeLayer()

    private static let minFreehandDistanceSq: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
        observeSettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Layout

    override func layout() {
        super.layout()
        noAnimation {
            arrowLayer.bounds    = bounds
            freehandLayer.bounds = bounds
        }
    }

    // MARK: - Layer Setup

    private func setupLayers() {
        guard let root = layer else { return }
        root.isOpaque = false

        laserShapeLayer.isHidden    = true
        laserShapeLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        root.addSublayer(laserShapeLayer)

        laserGlowLayer.isHidden       = true
        laserGlowLayer.anchorPoint    = CGPoint(x: 0.5, y: 0.5)
        laserGlowLayer.contentsGravity = .resize
        root.addSublayer(laserGlowLayer)

        arrowLayer.isHidden    = true
        arrowLayer.anchorPoint = .zero
        arrowLayer.position    = .zero
        arrowLayer.bounds      = bounds
        arrowLayer.lineCap     = .round
        arrowLayer.lineJoin    = .round
        root.addSublayer(arrowLayer)

        freehandLayer.isHidden    = true
        freehandLayer.anchorPoint = .zero
        freehandLayer.position    = .zero
        freehandLayer.bounds      = bounds
        freehandLayer.fillColor   = nil
        freehandLayer.lineCap     = .round
        freehandLayer.lineJoin    = .round
        root.addSublayer(freehandLayer)

        updateLaserStyle()
    }

    // MARK: - Settings Observation

    private func observeSettings() {
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateLaserStyle() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Laser Style & Visibility

    private func updateLaserStyle() {
        let size  = CGFloat(settings.laserSize)
        let color = settings.laserDisplayColor
        let bw    = CGFloat(settings.laserBorderWidth)

        switch settings.laserType {
        case .dot:
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            noAnimation {
                laserShapeLayer.path        = CGPath(ellipseIn: rect, transform: nil)
                laserShapeLayer.bounds      = rect
                laserShapeLayer.fillColor   = color.cgColor
                laserShapeLayer.strokeColor = nil
                laserShapeLayer.lineWidth   = 0
            }

        case .ring:
            let outerRect = CGRect(x: 0, y: 0, width: size, height: size)
            let inset = bw / 2
            noAnimation {
                laserShapeLayer.path        = CGPath(ellipseIn: outerRect.insetBy(dx: inset, dy: inset), transform: nil)
                laserShapeLayer.bounds      = outerRect
                laserShapeLayer.fillColor   = nil
                laserShapeLayer.strokeColor = color.cgColor
                laserShapeLayer.lineWidth   = bw
            }

        case .glow:
            // Pre-render the radial gradient into a CGImage at 2× for Retina quality.
            // This runs only on settings changes — the animation itself is GPU-driven.
            let diameter = size * 2
            let scale: CGFloat = 2
            let px = Int(diameter * scale)
            if let img = makeGlowImage(pixels: px, color: color) {
                noAnimation {
                    laserGlowLayer.contents      = img
                    laserGlowLayer.contentsScale = scale
                    laserGlowLayer.bounds        = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                }
            }
        }

        updateLaserVisibility()
        updateArrowStyle()
        updateFreehandStyle()
    }

    // Renders a radial gradient into a square CGImage of `pixels × pixels` resolution.
    private func makeGlowImage(pixels: Int, color: NSColor) -> CGImage? {
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: bitmapInfo.rawValue) else { return nil }
        let center = CGFloat(pixels) / 2
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color.cgColor,
                     color.withAlphaComponent(0.3).cgColor,
                     color.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 0.4, 1.0]) else { return nil }
        ctx.drawRadialGradient(gradient,
                               startCenter: CGPoint(x: center, y: center), startRadius: 0,
                               endCenter:   CGPoint(x: center, y: center), endRadius: center,
                               options: .drawsAfterEndLocation)
        return ctx.makeImage()
    }

    // MARK: - Visibility & Pulse

    private func updateLaserVisibility() {
        let on    = isLaserActive
        let isGlow = settings.laserType == .glow
        noAnimation {
            laserShapeLayer.isHidden = !on || isGlow
            laserGlowLayer.isHidden  = !on || !isGlow
        }
        updatePulseAnimation()
    }

    private func updatePulseAnimation() {
        for key in ["pulseScale", "pulseOpacity"] {
            laserShapeLayer.removeAnimation(forKey: key)
            laserGlowLayer.removeAnimation(forKey: key)
        }
        noAnimation {
            laserShapeLayer.transform = CATransform3DIdentity
            laserGlowLayer.transform  = CATransform3DIdentity
            laserShapeLayer.opacity   = 1
            laserGlowLayer.opacity    = 1
        }

        guard isLaserActive, settings.laserAnimationEnabled else { return }

        let halfPeriod = Double.pi / 1.8
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        let scaleAnim = CABasicAnimation(keyPath: "transform")
        scaleAnim.fromValue      = NSValue(caTransform3D: CATransform3DScale(CATransform3DIdentity, 0.9, 0.9, 1))
        scaleAnim.toValue        = NSValue(caTransform3D: CATransform3DScale(CATransform3DIdentity, 1.1, 1.1, 1))
        scaleAnim.duration       = halfPeriod
        scaleAnim.autoreverses   = true
        scaleAnim.repeatCount    = .infinity
        scaleAnim.timingFunction = timing

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue      = Float(0.65)
        opacityAnim.toValue        = Float(1.0)
        opacityAnim.duration       = halfPeriod
        opacityAnim.autoreverses   = true
        opacityAnim.repeatCount    = .infinity
        opacityAnim.timingFunction = timing

        let target: CALayer = settings.laserType == .glow ? laserGlowLayer : laserShapeLayer
        target.add(scaleAnim,   forKey: "pulseScale")
        target.add(opacityAnim, forKey: "pulseOpacity")
    }

    private func updateArrowStyle() {
        let color = settings.arrowNSColor
        noAnimation {
            arrowLayer.strokeColor = color.cgColor
            arrowLayer.fillColor   = color.cgColor
            arrowLayer.lineWidth   = CGFloat(settings.arrowLineWidth)
        }
    }

    private func updateFreehandStyle() {
        let color   = settings.freehandNSColor
        let opacity = CGFloat(settings.freehandOpacity)
        noAnimation {
            freehandLayer.strokeColor = color.withAlphaComponent(opacity).cgColor
            freehandLayer.lineWidth   = CGFloat(settings.freehandLineWidth)
        }
    }

    // MARK: - Position Updates

    private func updatePositions() {
        guard window != nil else { return }
        let viewPt = convertScreenToView(mousePosition)
        noAnimation {
            laserShapeLayer.position = viewPt
            laserGlowLayer.position  = viewPt
        }
        if isArrowDrawing { updateArrowPath() }
    }

    private func updateArrowPath() {
        guard isArrowDrawing, let start = arrowStartPoint, window != nil else { return }
        let startView = convertScreenToView(start)
        let endView   = convertScreenToView(mousePosition)

        let dx = endView.x - startView.x
        let dy = endView.y - startView.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 5 else { return }

        let angle     = atan2(dy, dx)
        let headSize  = CGFloat(settings.arrowHeadSize)
        let headAngle: CGFloat = .pi / 6

        let p1 = CGPoint(x: endView.x - headSize * cos(angle - headAngle),
                         y: endView.y - headSize * sin(angle - headAngle))
        let p2 = CGPoint(x: endView.x - headSize * cos(angle + headAngle),
                         y: endView.y - headSize * sin(angle + headAngle))

        let path = CGMutablePath()
        path.move(to: startView)
        path.addLine(to: endView)
        path.move(to: endView)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()

        noAnimation { arrowLayer.path = path; arrowLayer.isHidden = false }
    }

    // MARK: - Freehand

    func startFreehandDraw() {
        freehandLayer.removeAnimation(forKey: "fade")
        freehandPath = CGMutablePath()
        freehandViewPoints.removeAll(keepingCapacity: true)
        isFreehandDrawing = true
        noAnimation { freehandLayer.opacity = 1; freehandLayer.path = nil; freehandLayer.isHidden = false }
    }

    func addFreehandPoint(_ screenPoint: CGPoint) {
        guard isFreehandDrawing else { return }
        let viewPoint = convertScreenToView(screenPoint)

        if let last = freehandViewPoints.last {
            let dx = viewPoint.x - last.x
            let dy = viewPoint.y - last.y
            guard dx * dx + dy * dy >= Self.minFreehandDistanceSq else { return }
        }

        if freehandViewPoints.isEmpty { freehandPath.move(to: viewPoint) }
        else { freehandPath.addLine(to: viewPoint) }
        freehandViewPoints.append(viewPoint)
        noAnimation { freehandLayer.path = freehandPath }
    }

    func endFreehandDraw() {
        isFreehandDrawing = false
        guard !freehandViewPoints.isEmpty else { freehandLayer.isHidden = true; return }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue   = 0.0
        fade.duration  = settings.freehandFadeDuration
        fade.fillMode  = .forwards
        fade.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.noAnimation { self.freehandLayer.isHidden = true; self.freehandLayer.opacity = 1 }
            self.freehandLayer.removeAnimation(forKey: "fade")
            self.freehandLayer.path = nil
            self.freehandPath = CGMutablePath()
            self.freehandViewPoints.removeAll(keepingCapacity: true)
        }
        freehandLayer.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    // MARK: - Utilities

    private func convertScreenToView(_ screenPoint: CGPoint) -> CGPoint {
        guard let window = self.window else { return screenPoint }
        return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
    }

    private func noAnimation(_ block: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        block()
        CATransaction.commit()
    }
}
