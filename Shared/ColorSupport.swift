import SwiftUI
import UIKit

extension Color {
    /// "#1F8A70" / "1F8A70" / "#1F8A70CC" → Color (sRGB).
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// Adaptive colour that follows light/dark appearance (works in widgets too). Both variants are parsed once, here –
    /// the provider runs on every trait resolution and only picks one (UIColor is immutable, safe to capture).
    init(light: String, dark: String) {
        let light = UIColor(hex: light), dark = UIColor(hex: dark)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    init(light: Color, dark: Color) {
        let light = UIColor(light), dark = UIColor(dark)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        switch s.count {
        case 8:
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        default:
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
