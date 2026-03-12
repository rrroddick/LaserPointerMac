import AppKit
import KeyboardShortcuts

final class HotkeyManager {
    private weak var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
        setupToggleLaser()
        setupArrowDraw()
    }

    // MARK: - Toggle Laser

    private func setupToggleLaser() {
        KeyboardShortcuts.onKeyUp(for: .toggleLaser) { [weak self] in
            self?.appState?.toggleLaser()
        }
    }

    // MARK: - Arrow Draw (press-and-hold)
    //
    // Uses KeyboardShortcuts.onKeyDown / onKeyUp to detect hold behavior.
    // The Carbon hot key system fires kEventHotKeyPressed on press and
    // kEventHotKeyReleased when either the key or modifier is released,
    // which gives us correct hold-to-draw semantics.
    //
    // This approach automatically handles shortcut changes made via the
    // KeyboardShortcuts.Recorder in settings.

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
}
