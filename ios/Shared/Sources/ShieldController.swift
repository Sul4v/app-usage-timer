import Foundation
import ManagedSettings

/// Single source of truth for which tracked apps are shielded right now.
/// Called from the app (foreground), the monitor extension (each threshold
/// event) and the shield-action extension (after "Continue") so every process
/// applies the same rule set.
///
/// Rules, per tracked app with a token:
///  - in an active grace window  → not shielded (user just chose to continue)
///  - interstitial mode on        → shielded, so the reminder shows on open
///  - else block-over-limit on and over limit → shielded
public enum ShieldController {
    private static let store = ManagedSettingsStore()

    public static func reconcile() {
        let shared = SharedStore.shared
        let interstitial = shared.interstitialEnabled
        let blockOver = shared.shieldWhenOverLimit
        guard interstitial || blockOver else {
            store.shield.applications = nil
            return
        }

        let today = shared.todayUsage()
        let now = Date()
        var shielded = Set<ApplicationToken>()
        for app in shared.loadTrackedApps() {
            guard let token = app.token else { continue }
            if let until = shared.graceUntil(appID: app.id), until > now { continue }
            let minutes = today.apps[app.id]?.minutes ?? 0
            if interstitial {
                shielded.insert(token)
            } else if blockOver, minutes >= app.limitMinutes {
                shielded.insert(token)
            }
        }
        store.shield.applications = shielded.isEmpty ? nil : shielded
    }

    /// Let the user into an app for the grace window, then re-shield.
    public static func grantGrace(appID: UUID) {
        let shared = SharedStore.shared
        shared.setGrace(appID: appID, until: Date().addingTimeInterval(Double(shared.graceMinutes) * 60))
        reconcile()
    }

    public static func clearAll() {
        store.shield.applications = nil
    }
}
