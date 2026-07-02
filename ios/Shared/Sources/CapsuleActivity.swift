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
        /// Unix epoch seconds. A plain Double (not Date) so the APNs
        /// `content-state` JSON the server sends decodes identically to what
        /// the app encodes — Date's push decoding is environment-dependent.
        public var updatedAt: Double

        public init(appNickname: String, usedMinutes: Int, limitMinutes: Int,
                    updatedAt: Double = Date().timeIntervalSince1970) {
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
    /// A push-updated capsule is refreshed by the server every minute of use.
    /// The stale window is a touch over 2 minutes so a genuinely-ended session
    /// dims, while normal minute-by-minute pushes keep it fresh.
    private static let staleAfter: TimeInterval = 135

    /// Guards against stacking duplicate token-observer tasks per activity.
    private static var observedActivityID: String?

    public struct UpdateOutcome {
        public var result: String
        public var detail: String
    }

    /// App-side: correct a live capsule to an exact value right now (a direct
    /// ActivityKit update works from the app process), or start one. Starting
    /// always uses a push token so the server can drive it while backgrounded.
    @discardableResult
    public static func startOrUpdate(_ state: CapsuleActivityAttributes.ContentState) async -> UpdateOutcome {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return UpdateOutcome(result: "disabled", detail: "Live Activities off in Settings")
        }
        if let existing = Activity<CapsuleActivityAttributes>.activities.first {
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
            await existing.update(content)
            observeToken(existing)
            return UpdateOutcome(result: "updated", detail: "app")
        }
        requestActivity(state)
        return UpdateOutcome(result: "started", detail: "app")
    }

    /// App-side: ensure a capsule exists (started with a push token), or just
    /// re-attach token observation if one is already live.
    public static func ensureStarted(_ state: CapsuleActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = Activity<CapsuleActivityAttributes>.activities.first {
            observeToken(existing)
        } else {
            requestActivity(state)
        }
    }

    private static func requestActivity(_ state: CapsuleActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
        guard let activity = try? Activity.request(
            attributes: CapsuleActivityAttributes(),
            content: content,
            pushType: .token
        ) else { return }
        observeToken(activity)
    }

    /// Stream the activity's APNs push token to the server. The token is
    /// issued asynchronously after `request` and can rotate, so we keep the
    /// stream open and re-register whenever it changes.
    private static func observeToken(_ activity: Activity<CapsuleActivityAttributes>) {
        guard observedActivityID != activity.id else { return }
        observedActivityID = activity.id
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                SharedStore.shared.capsulePushToken = hex
                if await CapsulePush.registerToken(hex, deviceID: SharedStore.shared.deviceID) {
                    SharedStore.shared.registeredPushToken = hex
                }
            }
        }
    }

    /// Retry token registration if the last attempt didn't confirm (e.g. the
    /// token was first issued while offline). Cheap idempotent upsert; called
    /// on app foreground.
    public static func retryTokenRegistrationIfNeeded() async {
        let store = SharedStore.shared
        guard let token = store.capsulePushToken, token != store.registeredPushToken else { return }
        if await CapsulePush.registerToken(token, deviceID: store.deviceID) {
            store.registeredPushToken = token
        }
    }

    public static func endAll() async {
        observedActivityID = nil
        for activity in Activity<CapsuleActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
