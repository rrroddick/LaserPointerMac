import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // MARK: - Laser Settings

    @AppStorage("laserType") var laserType: LaserType = .glow
    @AppStorage("laserSize") var laserSize: Double = 40
    @AppStorage("laserOpacity") var laserOpacity: Double = 0.8
    @AppStorage("laserBorderWidth") var laserBorderWidth: Double = 3
    @AppStorage("laserAnimationEnabled") var laserAnimationEnabled: Bool = true

    // Color stored as hex string
    @AppStorage("laserColorHex") var laserColorHex: String = "#FF3B30"

    var laserColor: Color {
        get { Color(hex: laserColorHex) ?? .red }
        set { laserColorHex = newValue.toHex() ?? "#FF3B30" }
    }

    var laserNSColor: NSColor {
        NSColor(laserColor)
    }

    // MARK: - Arrow Settings

    @AppStorage("arrowColorHex") var arrowColorHex: String = "#007AFF"
    @AppStorage("arrowLineWidth") var arrowLineWidth: Double = 3
    @AppStorage("arrowHeadSize") var arrowHeadSize: Double = 16

    var arrowColor: Color {
        get { Color(hex: arrowColorHex) ?? .blue }
        set { arrowColorHex = newValue.toHex() ?? "#007AFF" }
    }

    var arrowNSColor: NSColor {
        NSColor(arrowColor)
    }

    // MARK: - Freehand Draw Settings

    @AppStorage("freehandColorHex") var freehandColorHex: String = "#00F514"
    @AppStorage("freehandLineWidth") var freehandLineWidth: Double = 3
    @AppStorage("freehandOpacity") var freehandOpacity: Double = 1.0
    @AppStorage("freehandFadeDuration") var freehandFadeDuration: Double = 1.0

    var freehandColor: Color {
        get { Color(hex: freehandColorHex) ?? .green }
        set { freehandColorHex = newValue.toHex() ?? "#00F514" }
    }

    var freehandNSColor: NSColor {
        NSColor(freehandColor)
    }

    private init() {}
}

// MARK: - Laser Type

enum LaserType: String, CaseIterable, Identifiable {
    case dot
    case ring
    case glow
    case spotlight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dot: return "Dot"
        case .ring: return "Ring"
        case .glow: return "Glow"
        case .spotlight: return "Spotlight"
        }
    }
}

// MARK: - Color Hex Conversion

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else {
            return nil
        }
        let r = Int((components[safe: 0] ?? 0) * 255)
        let g = Int((components[safe: 1] ?? 0) * 255)
        let b = Int((components[safe: 2] ?? 0) * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
