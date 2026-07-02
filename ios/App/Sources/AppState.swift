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
        Task { await sync.syncNow() }
    }

    func signOut() {
        account.signOut()
        phase = .auth
    }
}
