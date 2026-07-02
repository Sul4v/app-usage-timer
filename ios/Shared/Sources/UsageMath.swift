import SwiftUI

/// The one bold color in the app: green when well under the limit, drifting
/// through yellow and orange as the limit approaches, red at and past it.
public enum UsageMath {
    public static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    public static let yellow = Color(red: 1.00, green: 0.80, blue: 0.00)
    public static let orange = Color(red: 1.00, green: 0.58, blue: 0.00)
    public static let red = Color(red: 1.00, green: 0.23, blue: 0.19)

    /// ratio = used / limit. 0…0.5 solid green, 0.5…0.8 green→yellow,
    /// 0.8…1.0 yellow→red (through orange), ≥1.0 solid red.
    public static func stateColor(ratio: Double) -> Color {
        switch ratio {
        case ..<0.5:
            return green
        case ..<0.8:
            return blend(green, yellow, t: (ratio - 0.5) / 0.3)
        case ..<1.0:
            let t = (ratio - 0.8) / 0.2
            return t < 0.5 ? blend(yellow, orange, t: t * 2) : blend(orange, red, t: (t - 0.5) * 2)
        default:
            return red
        }
    }

    private static func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        let t = min(max(t, 0), 1)
        let ca = UIColor(a), cb = UIColor(b)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        ca.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        cb.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }

    /// UIColor version of `stateColor`, for the shield UI (ManagedSettingsUI
    /// takes UIColor, not SwiftUI Color).
    public static func stateUIColor(ratio: Double) -> UIColor {
        UIColor(stateColor(ratio: ratio))
    }

    public static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    public static func formatSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return formatMinutes(seconds / 60)
    }
}
