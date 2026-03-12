import SwiftUI

@main
struct LaserPointerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
        } label: {
            if appState.isLaserActive {
                Image(nsImage: .coloredSymbol(name: "light.max", color: .systemRed))
            } else {
                Image(systemName: "light.min")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(SettingsStore.shared)
        }
    }
}

extension NSImage {
    static func coloredSymbol(name: String, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return NSImage()
        }
        let coloredImage = NSImage(size: symbol.size)
        coloredImage.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: symbol.size)
        rect.fill()
        symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        coloredImage.unlockFocus()
        coloredImage.isTemplate = false
        return coloredImage
    }
}

struct MenuBarMenu: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        Button(appState.isLaserActive ? "Disable Laser" : "Enable Laser") {
            AppState.shared.toggleLaser()
        }

        if appState.isLaserActive {
            Text("● Laser Active")
        } else {
            Text("○ Laser Inactive")
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit LaserPointer") {
            NSApplication.shared.terminate(nil)
        }
    }
}
