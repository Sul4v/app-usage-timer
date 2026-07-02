import Foundation
import SwiftUI

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
        refresh()
        screenTime.checkAuthorization()
        phase = initialPhase()
    }

    private func initialPhase() -> Phase {
        guard account.isSignedIn || account.localMode else { return .auth }
        return store.hasCompletedOnboarding ? .main : .onboarding
    }

    func refresh() {
        trackedApps = store.loadTrackedApps()
        today = store.todayUsage()
        ensureCapsuleActivity()
    }

    /// Pre-start the Dynamic Island capsule from the app process. The
    /// DeviceActivity monitor extension can only *update* a running Live
    /// Activity — the system ignores start requests from extensions — so the
    /// app starts one showing today's most-used tracked app whenever it's
    /// foregrounded, and the extension keeps it current from then on.
    func ensureCapsuleActivity() {
        guard phase == .main, screenTime.isAuthorized,
              let app = trackedApps.max(by: {
                  (today.apps[$0.id]?.minutes ?? 0) < (today.apps[$1.id]?.minutes ?? 0)
              })
        else { return }
        CapsuleLiveActivity.ensureStarted(.init(
            appNickname: app.nickname,
            usedMinutes: today.apps[app.id]?.minutes ?? 0,
            limitMinutes: app.limitMinutes
        ))
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
        Task { await sync.syncNow() }
    }

    func didAuthenticate() {
        phase = store.hasCompletedOnboarding ? .main : .onboarding
        Task { await sync.syncNow(); refresh() }
    }

    func completeOnboarding() {
        store.hasCompletedOnboarding = true
        screenTime.scheduleMonitoring(apps: trackedApps)
        phase = .main
        ensureCapsuleActivity()
        Task { await sync.syncNow() }
    }

    func signOut() {
        account.signOut()
        phase = .auth
    }
}
