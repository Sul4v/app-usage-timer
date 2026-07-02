import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable { case auth, onboarding, main }

    @Published var phase: Phase = .auth
    @Published var trackedApps: [TrackedApp] = []
    @Published var today = DayUsage(day: DayKey.today)

    let store = SharedStore.shared
    let account = AccountManager()
    let screenTime = ScreenTimeService()
    private(set) lazy var sync = SyncEngine(account: account, store: store)

    init() {
        #if targetEnvironment(simulator)
        SampleData.seedIfNeeded(store: store)
        #endif
        screenTime.checkAuthorization()
        refresh()
        phase = initialPhase()
    }

    private func initialPhase() -> Phase {
        guard account.isSignedIn || account.localMode else { return .auth }
        return store.hasCompletedOnboarding ? .main : .onboarding
    }

    func refresh() {
        trackedApps = store.loadTrackedApps()
        today = store.todayUsage()
        screenTime.checkAuthorization()
        screenTime.ensureMonitoring(apps: trackedApps)
        ShieldController.reconcile()
        ensureCapsuleActivity()
        WidgetCenter.shared.reloadTimelines(ofKind: "CapsuleToday")
        Task { await CapsuleLiveActivity.retryTokenRegistrationIfNeeded() }
    }

    /// Keep the Dynamic Island capsule in sync with *recent* usage. Only the
    /// app process can start a Live Activity (the system ignores requests
    /// from the monitor extension), so on every foreground:
    /// - tracked app used in the last 10 minutes → make sure the capsule is
    ///   up, showing that app; the extension updates it each further minute.
    /// - nothing recent → end it, so the capsule doesn't squat in the island
    ///   all day. (iOS gives no "app opened" callback and Live Activities
    ///   are global, so exact show-only-while-in-app isn't possible.)
    func ensureCapsuleActivity() {
        guard phase == .main, screenTime.isAuthorized else { return }
        let recent = trackedApps
            .compactMap { app -> (TrackedApp, AppDayUsage, Date)? in
                guard let usage = today.apps[app.id],
                      let lastAt = usage.sessions.map(\.end).max()
                else { return nil }
                return (app, usage, lastAt)
            }
            .max { $0.2 < $1.2 }
        guard let (app, usage, lastAt) = recent,
              Date().timeIntervalSince(lastAt) < 10 * 60
        else {
            Task { await CapsuleLiveActivity.endAll() }
            return
        }
        // startOrUpdate (not ensureStarted): if a capsule is already live but
        // lagging behind because the extension's updates got throttled, this
        // snaps it to the accurate on-disk value every time the app opens.
        Task {
            await CapsuleLiveActivity.startOrUpdate(.init(
                appNickname: app.nickname,
                usedMinutes: usage.minutes,
                limitMinutes: app.limitMinutes
            ))
        }
    }

    /// Persist app/limit changes, re-register Screen Time monitoring so the
    /// per-minute thresholds match the new limits, and push to the server.
    func saveTrackedApps(_ apps: [TrackedApp]) {
        var stamped = apps
        let old = Dictionary(uniqueKeysWithValues: trackedApps.map { ($0.id, $0) })
        for i in stamped.indices where old[stamped[i].id] != stamped[i] {
            stamped[i].updatedAt = Date()
        }
        store.saveTrackedApps(stamped)
        trackedApps = stamped
        screenTime.scheduleMonitoring(apps: stamped)
        ShieldController.reconcile()
        Task { await sync.syncNow() }
    }

    func didAuthenticate() {
        phase = store.hasCompletedOnboarding ? .main : .onboarding
        Task { await sync.syncNow(); refresh() }
    }

    func completeOnboarding() {
        store.hasCompletedOnboarding = true
        screenTime.scheduleMonitoring(apps: trackedApps)
        ShieldController.reconcile()
        phase = .main
        ensureCapsuleActivity()
        Task { await sync.syncNow() }
    }

    func signOut() {
        account.signOut()
        phase = .auth
    }
}
