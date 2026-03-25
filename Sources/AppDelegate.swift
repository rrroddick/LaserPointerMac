import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize AppState early to register hotkeys
        _ = AppState.shared
        checkPermissions()
    }

    // MARK: - Permissions

    private func checkPermissions() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showPermissionAlert()
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            LaserPointer needs Accessibility access to monitor global keyboard shortcuts \
            and mouse position.

            Please go to System Settings → Privacy & Security → Accessibility \
            and enable LaserPointer.

            You may also need to enable Input Monitoring for global event listening.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

extension Notification.Name {
    static let laserStateDidChange = Notification.Name("laserStateDidChange")
}
