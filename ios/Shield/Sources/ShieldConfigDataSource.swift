import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Renders the reminder screen shown before a tracked app opens. It reads the
/// accurate usage from the shared store *at display time* — this runs the
/// moment the user taps the app, which is exactly when we're allowed to run,
/// so the number is current (no background updating needed).
class ShieldConfigDataSource: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(for: application.token)
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(for: application.token)
    }

    private func makeConfiguration(for token: ApplicationToken?) -> ShieldConfiguration {
        let store = SharedStore.shared
        let app = token.flatMap { t in store.loadTrackedApps().first { $0.token == t } }
        let minutes = app.flatMap { store.todayUsage().apps[$0.id]?.minutes } ?? 0
        let limit = app?.limitMinutes ?? TrackedApp.defaultLimitMinutes
        let ratio = limit > 0 ? Double(minutes) / Double(limit) : 0
        let color = UsageMath.stateUIColor(ratio: ratio)

        let name = app?.nickname ?? "this app"
        let over = minutes >= limit
        let title: String
        let subtitle: String
        switch ratio {
        case ..<0.5:
            title = "A moment with \(name)"
            subtitle = "You're well within your limit — \(UsageMath.formatMinutes(max(0, limit - minutes))) left today. Enjoy it deliberately."
        case ..<0.8:
            title = "Halfway through \(name)"
            subtitle = "\(UsageMath.formatMinutes(max(0, limit - minutes))) left of today's \(UsageMath.formatMinutes(limit)). Still worth it?"
        case ..<1.0:
            title = "Almost at your limit"
            subtitle = "Only \(UsageMath.formatMinutes(max(0, limit - minutes))) of \(name) left today. Make it count."
        default:
            title = "You've hit your limit"
            subtitle = "That was the \(UsageMath.formatMinutes(limit)) you gave yourself for \(name) today."
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 0.6),
            icon: ShieldRing.image(minutes: minutes, limit: limit, ratio: ratio, color: color),
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: UIColor.white.withAlphaComponent(0.7)),
            primaryButtonLabel: ShieldConfiguration.Label(text: over ? "Open anyway" : "Continue", color: .black),
            primaryButtonBackgroundColor: color,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Not now", color: UIColor.white.withAlphaComponent(0.9))
        )
    }
}
