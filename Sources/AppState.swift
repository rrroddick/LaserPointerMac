import AppKit
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isLaserActive = false
    @Published private(set) var isArrowDrawing = false
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
        }
    }

    func startArrowDraw() {
        guard isLaserActive else { return }
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
}
