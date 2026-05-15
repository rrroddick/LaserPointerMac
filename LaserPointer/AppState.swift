import AppKit
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isLaserActive = false
    private(set) var isArrowDrawing = false
    private(set) var isFreehandDrawing = false
    var arrowStartPoint: CGPoint? = nil
    var currentMousePosition: CGPoint = .zero

    let settings = SettingsStore.shared
    let overlayManager = OverlayWindowManager()
    private let mouseTracker = MouseTracker()
    private let hotkeyManager = HotkeyManager()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupMouseBinding()
        hotkeyManager.configure(appState: self)
    }

    private func setupMouseBinding() {
        mouseTracker.$mouseLocation
            .sink { [weak self] position in
                self?.currentMousePosition = position
                self?.overlayManager.updateMousePosition(position)
            }
            .store(in: &cancellables)
    }

    func toggleLaser() {
        isLaserActive.toggle()
        if isLaserActive {
            mouseTracker.startTracking()
            overlayManager.showOverlay()
            hotkeyManager.startModifierPolling()
        } else {
            mouseTracker.stopTracking()
            overlayManager.hideOverlay()
            endArrowDraw()
            endFreehandDraw()
            hotkeyManager.stopModifierPolling()
        }
    }

    func startArrowDraw() {
        arrowStartPoint = currentMousePosition
        isArrowDrawing = true
        overlayManager.setArrowDrawing(true)
        overlayManager.setArrowStartPoint(currentMousePosition)
    }

    func endArrowDraw() {
        isArrowDrawing = false
        arrowStartPoint = nil
        overlayManager.setArrowDrawing(false)
        overlayManager.setArrowStartPoint(nil)
    }

    func startFreehandDraw() {
        isFreehandDrawing = true
        overlayManager.startFreehandDraw()
    }

    func endFreehandDraw() {
        guard isFreehandDrawing else { return }
        isFreehandDrawing = false
        overlayManager.endFreehandDraw()
    }
}
