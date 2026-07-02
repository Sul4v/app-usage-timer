import SwiftUI

@main
struct CapsuleApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(.primary)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.phase {
            case .auth:
                AuthView()
            case .onboarding:
                OnboardingView()
            case .main:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.phase)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { appState.refresh() }
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("--tab-stats") ? 1 : 0
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "timer") }
                .tag(0)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-capsule") {
                await CapsuleLiveActivity.startOrUpdate(.init(
                    appNickname: appState.trackedApps.first?.nickname ?? "Instagram",
                    usedMinutes: 38,
                    limitMinutes: 45
                ))
            }
            #endif
        }
    }
}
