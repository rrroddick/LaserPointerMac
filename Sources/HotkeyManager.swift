import AppKit
import KeyboardShortcuts

final class HotkeyManager {
    private weak var appState: AppState?

    /// Track modifier-only state to detect press vs. release transitions
    private var isControlOnlyActive = false
    private var isOptionOnlyActive = false
    private var pollingTimer: Timer?

    func configure(appState: AppState) {
        self.appState = appState
        setupToggleLaser()
        setupArrowDraw()
        setupFreehandDraw()
        setupModifierOnlyShortcuts()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    // MARK: - Toggle Laser

    private func setupToggleLaser() {
        KeyboardShortcuts.onKeyUp(for: .toggleLaser) { [weak self] in
            self?.appState?.toggleLaser()
        }
    }

    // MARK: - Arrow Draw (configured shortcut, press-and-hold)

    private func setupArrowDraw() {
        KeyboardShortcuts.onKeyDown(for: .drawArrow) { [weak self] in
            guard let appState = self?.appState else { return }
            guard appState.isLaserActive, !appState.isArrowDrawing else { return }
            appState.startArrowDraw()
        }
        KeyboardShortcuts.onKeyUp(for: .drawArrow) { [weak self] in
            guard let appState = self?.appState else { return }
            guard appState.isArrowDrawing else { return }
            appState.endArrowDraw()
        }
    }

    // MARK: - Freehand Draw (configured shortcut, press-and-hold)

    private func setupFreehandDraw() {
        KeyboardShortcuts.onKeyDown(for: .drawFreehand) { [weak self] in
            guard let appState = self?.appState else { return }
            guard !appState.isFreehandDrawing else { return }
            appState.startFreehandDraw()
        }
        KeyboardShortcuts.onKeyUp(for: .drawFreehand) { [weak self] in
            guard let appState = self?.appState else { return }
            guard appState.isFreehandDrawing else { return }
            appState.endFreehandDraw()
        }
    }

    // MARK: - Modifier-only shortcuts (Ctrl alone = arrow, Option alone = freehand)
    //
    // NSEvent.addGlobalMonitorForEvents is unreliable for flagsChanged on macOS 14+.
    // Instead we poll NSEvent.modifierFlags at 60 fps — reads hardware state directly,
    // works regardless of which app is frontmost, requires no extra permissions.
    //
    // Rules:
    //  • Modifier-only is active only when the laser is on.
    //  • If a custom shortcut is configured for an action, modifier-only is disabled
    //    for that action (and any in-progress draw is stopped immediately).

    private func setupModifierOnlyShortcuts() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.checkModifierFlags()
        }
        RunLoop.main.add(pollingTimer!, forMode: .common)
    }

    private func checkModifierFlags() {
        guard let appState, appState.isLaserActive else {
            isControlOnlyActive = false
            isOptionOnlyActive = false
            return
        }

        let active = NSEvent.modifierFlags.intersection([.option, .control, .command, .shift])

        // --- Ctrl alone → Arrow ---
        if KeyboardShortcuts.getShortcut(for: .drawArrow) == nil {
            let ctrlOnly = active == .control
            if ctrlOnly && !isControlOnlyActive {
                isControlOnlyActive = true
                if !appState.isArrowDrawing { appState.startArrowDraw() }
            } else if ctrlOnly && isControlOnlyActive && !appState.isArrowDrawing {
                // Ctrl still held but draw was stopped externally — restart it
                appState.startArrowDraw()
            } else if !ctrlOnly && isControlOnlyActive {
                isControlOnlyActive = false
                if appState.isArrowDrawing { appState.endArrowDraw() }
            }
        } else if isControlOnlyActive {
            // Custom shortcut just registered — cleanly stop any modifier-only draw
            isControlOnlyActive = false
            if appState.isArrowDrawing { appState.endArrowDraw() }
        }

        // --- Option alone → Freehand ---
        if KeyboardShortcuts.getShortcut(for: .drawFreehand) == nil {
            let optionOnly = active == .option
            if optionOnly && !isOptionOnlyActive {
                isOptionOnlyActive = true
                if !appState.isFreehandDrawing { appState.startFreehandDraw() }
            } else if optionOnly && isOptionOnlyActive && !appState.isFreehandDrawing {
                // Option still held but draw was stopped externally — restart it
                appState.startFreehandDraw()
            } else if !optionOnly && isOptionOnlyActive {
                isOptionOnlyActive = false
                if appState.isFreehandDrawing { appState.endFreehandDraw() }
            }
        } else if isOptionOnlyActive {
            // Custom shortcut just registered — cleanly stop any modifier-only draw
            isOptionOnlyActive = false
            if appState.isFreehandDrawing { appState.endFreehandDraw() }
        }
    }
}
