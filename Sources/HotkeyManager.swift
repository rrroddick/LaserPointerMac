import AppKit
import KeyboardShortcuts

final class HotkeyManager {
    private weak var appState: AppState?

    // Track modifier-only state to detect press vs release
    private var isControlOnlyActive = false
    private var isOptionOnlyActive = false
    private var flagsMonitor: Any?

    func configure(appState: AppState) {
        self.appState = appState
        setupToggleLaser()
        setupArrowDraw()
        setupFreehandDraw()
        setupModifierOnlyShortcuts()
    }

    deinit {
        (flagsMonitor as? Timer)?.invalidate()
    }

    // MARK: - Toggle Laser

    private func setupToggleLaser() {
        KeyboardShortcuts.onKeyUp(for: .toggleLaser) { [weak self] in
            self?.appState?.toggleLaser()
        }
    }

    // MARK: - Arrow Draw (press-and-hold via KeyboardShortcuts)

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

    // MARK: - Freehand Draw (press-and-hold via KeyboardShortcuts)

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

    // MARK: - Modifier-only shortcuts via polling (Option alone = freehand, Ctrl alone = arrow)
    //
    // NSEvent.addGlobalMonitorForEvents is unreliable for flagsChanged on macOS 14+.
    // Instead, we poll NSEvent.modifierFlags at 60fps — it reads hardware state directly
    // and works regardless of which app is frontmost, with no extra permissions needed.

    private func setupModifierOnlyShortcuts() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkModifierFlags() }
        }
        RunLoop.main.add(timer, forMode: .common)
        flagsMonitor = timer
    }

    private func checkModifierFlags() {
        guard let appState else { return }
        guard appState.isLaserActive else {
            isControlOnlyActive = false
            isOptionOnlyActive = false
            return
        }

        let active = NSEvent.modifierFlags.intersection([.option, .control, .command, .shift])

        // Ctrl alone → Arrow (only when no custom shortcut is configured for drawArrow)
        let arrowShortcutConfigured = KeyboardShortcuts.getShortcut(for: .drawArrow) != nil
        if !arrowShortcutConfigured {
            let ctrlOnly = active == .control
            if ctrlOnly && !isControlOnlyActive {
                isControlOnlyActive = true
                if !appState.isArrowDrawing { appState.startArrowDraw() }
            } else if ctrlOnly && isControlOnlyActive && !appState.isArrowDrawing {
                appState.startArrowDraw()
            } else if !ctrlOnly && isControlOnlyActive {
                isControlOnlyActive = false
                if appState.isArrowDrawing { appState.endArrowDraw() }
            }
        } else {
            isControlOnlyActive = false
        }

        // Option alone → Freehand (only when no custom shortcut is configured for drawFreehand)
        let freehandShortcutConfigured = KeyboardShortcuts.getShortcut(for: .drawFreehand) != nil
        if !freehandShortcutConfigured {
            let optionOnly = active == .option
            if optionOnly && !isOptionOnlyActive {
                isOptionOnlyActive = true
                if !appState.isFreehandDrawing { appState.startFreehandDraw() }
            } else if optionOnly && isOptionOnlyActive && !appState.isFreehandDrawing {
                appState.startFreehandDraw()
            } else if !optionOnly && isOptionOnlyActive {
                isOptionOnlyActive = false
                if appState.isFreehandDrawing { appState.endFreehandDraw() }
            }
        } else {
            isOptionOnlyActive = false
        }
    }
}
