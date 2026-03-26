import AppKit
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isLaserActive = false
    @Published private(set) var isArrowDrawing = false
    @Published private(set) var isFreehandDrawing = false
    @Published var arrowStartPoint: CGPoint? = nil
    @Published var currentMousePosition: CGPoint = .zero

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
            .receive(on: RunLoop.main)
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
        } else {
            mouseTracker.stopTracking()
            overlayManager.hideOverlay()
            endArrowDraw()
            endFreehandDraw()
        }
    }

    func startArrowDraw() {
        arrowStartPoint = currentMousePosition
        isArrowDrawing = true
        if !isLaserActive {
            mouseTracker.startTracking()
            overlayManager.showOverlay()
        }
        overlayManager.setArrowDrawing(true)
        overlayManager.setArrowStartPoint(currentMousePosition)
    }

    func endArrowDraw() {
        isArrowDrawing = false
        arrowStartPoint = nil
        overlayManager.setArrowDrawing(false)
        overlayManager.setArrowStartPoint(nil)
        if !isLaserActive {
            mouseTracker.stopTracking()
            overlayManager.hideOverlay()
        }
    }

    func startFreehandDraw() {
        isFreehandDrawing = true
        // Start tracking mouse even if laser is off, so points are collected
        if !isLaserActive {
            mouseTracker.startTracking()
            overlayManager.startFreehandDraw()
        } else {
            overlayManager.startFreehandDraw()
        }
    }

    func endFreehandDraw() {
        guard isFreehandDrawing else { return }
        isFreehandDrawing = false
        overlayManager.endFreehandDraw()
        // Stop the tracker only if we started it (i.e. laser is still off)
        if !isLaserActive {
            mouseTracker.stopTracking()
        }
    }
}
