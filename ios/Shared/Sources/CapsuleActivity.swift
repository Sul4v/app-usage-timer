import Foundation
import ActivityKit

/// The Live Activity behind the Dynamic Island / Lock Screen capsule.
/// One activity is kept alive and its state switched to whichever tracked
/// app most recently accumulated usage.
public struct CapsuleActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var appNickname: String
        public var usedMinutes: Int
        public var limitMinutes: Int
        public var updatedAt: Date

        public init(appNickname: String, usedMinutes: Int, limitMinutes: Int, updatedAt: Date = Date()) {
            self.appNickname = appNickname
            self.usedMinutes = usedMinutes
            self.limitMinutes = limitMinutes
            self.updatedAt = updatedAt
        }

        public var ratio: Double {
            limitMinutes > 0 ? Double(usedMinutes) / Double(limitMinutes) : 0
        }
    }

    public init() {}
}

public enum CapsuleLiveActivity {
    /// Start a capsule (from the app) or update the existing one (works from
    /// the monitor extension too — `Activity.request` is unreliable outside
    /// the app process, but updating an already-running activity works).
    /// Threshold events arrive at most once a minute while a tracked app is
    /// in use, so ~3.5 quiet minutes means usage stopped: the capsule goes
    /// stale (dimmed) then, and the app clears it next time it's opened.
    private static let staleAfter: TimeInterval = 3.5 * 60

    public static func startOrUpdate(_ state: CapsuleActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
        if let existing = Activity<CapsuleActivityAttributes>.activities.first {
            await existing.update(content)
            for extra in Activity<CapsuleActivityAttributes>.activities.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
        } else {
            _ = try? Activity.request(attributes: CapsuleActivityAttributes(), content: content)
        }
    }

    /// Start the capsule if none is running, without touching an existing
    /// one. Called from the app on foreground: only the app process can
    /// reliably *request* a Live Activity, so it pre-starts the capsule and
    /// the monitor extension merely updates it as usage accumulates.
    public static func ensureStarted(_ state: CapsuleActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              Activity<CapsuleActivityAttributes>.activities.isEmpty
        else { return }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
        _ = try? Activity.request(attributes: CapsuleActivityAttributes(), content: content)
    }

    public static func endAll() async {
        for activity in Activity<CapsuleActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
