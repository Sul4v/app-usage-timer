import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Wraps the Screen Time API: authorization, mapping the user's
/// `FamilyActivityPicker` selection onto our `TrackedApp` records, and
/// registering the DeviceActivity schedule + per-minute threshold events
/// that drive the monitor extension.
@MainActor
final class ScreenTimeService: ObservableObject {
    @Published var isAuthorized = false

    private let center = DeviceActivityCenter()
    private static let activityName = DeviceActivityName("daily")

    func checkAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            // Denied, or unsupported environment (e.g. the simulator).
            isAuthorized = false
        }
        return isAuthorized
    }

    /// Merge a fresh picker selection into the existing tracked apps:
    /// keep apps whose token is still selected (preserving nickname/limit),
    /// create records for newly selected tokens, drop deselected ones.
    /// Nickname-only apps (no token — demo mode) are always kept.
    func apply(selection: FamilyActivitySelection, to existing: [TrackedApp]) -> [TrackedApp] {
        SharedStore.shared.familySelectionData = try? JSONEncoder().encode(selection)

        var result = existing.filter { $0.tokenData == nil }
        var claimed = Set<UUID>()
        for token in selection.applicationTokens {
            if let match = existing.first(where: { $0.token == token && !claimed.contains($0.id) }) {
                claimed.insert(match.id)
                result.append(match)
            } else {
                let n = result.count + 1
                result.append(TrackedApp(nickname: "App \(n)", tokenData: TrackedApp.encode(token: token)))
            }
        }
        return result
    }

    func savedSelection() -> FamilyActivitySelection {
        guard let data = SharedStore.shared.familySelectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    /// Whether the system currently has our daily schedule registered.
    var isMonitoring: Bool {
        center.activities.contains(Self.activityName)
    }

    /// Re-arm monitoring if the system lost it (app reinstall/update clears
    /// DeviceActivity schedules). Deliberately does nothing while a schedule
    /// is active: re-registering mid-day resets the accumulated usage that
    /// threshold events count against, which would stall the day's counting.
    func ensureMonitoring(apps: [TrackedApp]) {
        guard isAuthorized, !isMonitoring,
              apps.contains(where: { $0.token != nil })
        else { return }
        scheduleMonitoring(apps: apps)
    }

    /// (Re)register the repeating all-day schedule. DeviceActivity only tells
    /// us when *cumulative* usage crosses a pre-registered threshold, so we
    /// register a ladder of thresholds per app: every minute near and below
    /// the limit, coarser beyond it. The monitor extension turns those events
    /// into the usage log and capsule updates.
    func scheduleMonitoring(apps: [TrackedApp]) {
        center.stopMonitoring([Self.activityName])

        let monitored = apps.filter { $0.token != nil }
        guard isAuthorized, !monitored.isEmpty else { return }

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for app in monitored {
            guard let token = app.token else { continue }
            for minute in thresholdLadder(limitMinutes: app.limitMinutes) {
                events[DeviceActivityEvent.Name("\(app.id.uuidString)|\(minute)")] =
                    DeviceActivityEvent(applications: [token], threshold: DateComponents(minute: minute))
            }
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        try? center.startMonitoring(Self.activityName, during: schedule, events: events)
    }

    /// Minute marks at which threshold events fire. The system tolerates a
    /// limited number of registered events, so: 1-minute steps up to the
    /// limit (capped at 90), then 5-minute steps until double the limit.
    private func thresholdLadder(limitMinutes: Int) -> [Int] {
        let fineCap = min(max(limitMinutes + 10, 30), 90)
        var marks = Array(1...fineCap)
        let coarseEnd = min(max(limitMinutes * 2, fineCap + 30), 300)
        var m = fineCap + 5
        while m <= coarseEnd {
            marks.append(m)
            m += 5
        }
        return marks
    }
}
