import AppKit
import KeyboardShortcuts

final class HotkeyManager {
    private weak var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
        setupToggleLaser()
        setupArrowDraw()
        setupFreehandDraw()
    }

    // MARK: - Toggle Laser

    private func setupToggleLaser() {
        KeyboardShortcuts.onKeyUp(for: .toggleLaser) { [weak self] in
            self?.appState?.toggleLaser()
        }
    }

    // MARK: - Arrow Draw (press-and-hold)

    private func setupArrowDraw() {
        KeyboardShortcuts.onKeyDown(for: .drawArrow) { [weak self] in
            guard let self, let appState = self.appState else { return }
            guard appState.isLaserActive, !appState.isArrowDrawing else { return }
            appState.startArrowDraw()
        }

        KeyboardShortcuts.onKeyUp(for: .drawArrow) { [weak self] in
            guard let self, let appState = self.appState else { return }
            guard appState.isArrowDrawing else { return }
            appState.endArrowDraw()
        }
    }

    // MARK: - Freehand Draw (press-and-hold, works independently of laser)

    private func setupFreehandDraw() {
        KeyboardShortcuts.onKeyDown(for: .drawFreehand) { [weak self] in
            guard let self, let appState = self.appState else { return }
            guard !appState.isFreehandDrawing else { return }
            appState.startFreehandDraw()
        }

        KeyboardShortcuts.onKeyUp(for: .drawFreehand) { [weak self] in
            guard let self, let appState = self.appState else { return }
            guard appState.isFreehandDrawing else { return }
            appState.endFreehandDraw()
        }
    }
}
