import DeviceActivity
import Foundation
import ManagedSettings
import UserNotifications

/// Runs in its own sandboxed process. The system calls
/// `eventDidReachThreshold` each time a tracked app crosses one of the
/// per-minute cumulative-usage thresholds registered by the main app
/// (see `ScreenTimeService.scheduleMonitoring`).
///
/// Event names are "<trackedAppUUID>|<minutes>".
final class UsageMonitorExtension: DeviceActivityMonitor {
    private let store = SharedStore.shared

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // New day: re-apply shields for the fresh day (interstitial re-arms,
        // yesterday's over-limit blocks lift).
        ShieldController.reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let done = DispatchSemaphore(value: 0)
        Task { await CapsuleLiveActivity.endAll(); done.signal() }
        _ = done.wait(timeout: .now() + 8)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        // Proof-of-life: monitoring delivered an event to us.
        store.lastThresholdAt = Date()

        let parts = event.rawValue.split(separator: "|")
        guard parts.count == 2,
              let appID = UUID(uuidString: String(parts[0])),
              let minutes = Int(parts[1]),
              let app = store.trackedApp(id: appID)
        else { return }

        let day = store.recordThreshold(appID: appID, cumulativeMinutes: minutes)
        let usage = day.apps[appID] ?? AppDayUsage()

        // Do the synchronous work (shield, notifications) first — it always
        // completes — then block for the async capsule update below.
        notifyMilestones(app: app, usage: usage)

        // Re-apply shields: re-arms the interstitial once a grace window has
        // expired, and blocks apps that just crossed their limit.
        ShieldController.reconcile()

        // Drive the Dynamic Island capsule. ActivityKit refuses updates from
        // this extension (unsupportedTarget), so instead ask the server to
        // push the new value to our Live Activity via APNs. The extension is
        // suspended the instant this callback returns, so block until the
        // network request finishes.
        let done = DispatchSemaphore(value: 0)
        Task {
            let outcome = await CapsulePush.reportUsage(
                deviceID: self.store.deviceID,
                appNickname: app.nickname,
                usedMinutes: usage.minutes,
                limitMinutes: app.limitMinutes
            )
            self.store.lastCapsuleDiag = SharedStore.CapsuleDiag(
                at: Date(), targetMinutes: usage.minutes,
                result: outcome.ok ? "pushed" : "push failed", detail: outcome.detail
            )
            done.signal()
        }
        _ = done.wait(timeout: .now() + 7)
    }

    private func notifyMilestones(app: TrackedApp, usage: AppDayUsage) {
        let ratio = app.limitMinutes > 0 ? Double(usage.minutes) / Double(app.limitMinutes) : 0

        if ratio >= 1.0, !usage.notifiedOverLimit {
            store.markNotified(appID: app.id, overLimit: true)
            sendNotification(
                title: "\(app.nickname): limit reached",
                body: "You've used \(app.nickname) for \(UsageMath.formatMinutes(usage.minutes)) today — that's your \(UsageMath.formatMinutes(app.limitMinutes)) limit."
            )
        } else if ratio >= 0.8, !usage.notifiedNearLimit {
            store.markNotified(appID: app.id, overLimit: false)
            let left = max(0, app.limitMinutes - usage.minutes)
            sendNotification(
                title: "\(app.nickname): \(UsageMath.formatMinutes(left)) left",
                body: "You're at \(UsageMath.formatMinutes(usage.minutes)) of your \(UsageMath.formatMinutes(app.limitMinutes)) daily limit."
            )
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
