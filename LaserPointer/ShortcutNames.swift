import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleLaser = Self("toggleLaser", default: .init(.l, modifiers: [.control, .option]))
    static let drawArrow = Self("drawArrow")
    static let drawFreehand = Self("drawFreehand")
}
