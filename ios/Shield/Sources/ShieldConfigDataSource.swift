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

        let over = minutes >= limit
        let title = over
            ? "You're past your limit"
            : "You've used \(UsageMath.formatMinutes(minutes)) today"
        let subtitle = over
            ? "That's \(UsageMath.formatMinutes(minutes)) of your \(UsageMath.formatMinutes(limit)) limit. Sure you want to keep going?"
            : "\(UsageMath.formatMinutes(max(0, limit - minutes))) left of your \(UsageMath.formatMinutes(limit)) limit. Still want to open it?"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.55),
            icon: nil,
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: UIColor.white.withAlphaComponent(0.75)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Continue anyway", color: .white),
            primaryButtonBackgroundColor: color,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Not now", color: UIColor.white.withAlphaComponent(0.9))
        )
    }
}
