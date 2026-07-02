import FamilyControls
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()
    @State private var shieldOn = SharedStore.shared.shieldWhenOverLimit

    var body: some View {
        NavigationStack {
            List {
                Section("Tracked apps") {
                    if appState.screenTime.isAuthorized {
                        Button("Change tracked apps") {
                            selection = appState.screenTime.savedSelection()
                            showPicker = true
                        }
                    } else {
                        Button("Allow Screen Time access") {
                            Task { _ = await appState.screenTime.requestAuthorization() }
                        }
                        Text("Without Screen Time access, Capsule can't measure real usage on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Block apps when over limit", isOn: $shieldOn)
                        .onChange(of: shieldOn) { _, on in
                            SharedStore.shared.shieldWhenOverLimit = on
                        }
                }

                Section("Account") {
                    if let session = appState.account.session {
                        LabeledContent("Signed in as", value: session.email)
                        LabeledContent("Last sync") {
                            Text(lastSyncText)
                        }
                        Button("Sync now") {
                            Task { await appState.sync.syncNow(); appState.refresh() }
                        }
                        if let error = appState.sync.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(UsageMath.red)
                        }
                        Button("Sign out", role: .destructive) {
                            appState.signOut()
                        }
                    } else {
                        Text(appState.account.isConfigured
                             ? "You're using Capsule without an account. Data stays on this device."
                             : "This build has no sync server configured — data stays on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if appState.account.isConfigured {
                            Button("Sign in to sync") { appState.signOut() }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    Text("The capsule lives in the Dynamic Island while you use a tracked app: green when you're well under your limit, red once you're past it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .familyActivityPicker(isPresented: $showPicker, selection: $selection)
            .onChange(of: selection) { _, newSelection in
                let apps = appState.screenTime.apply(selection: newSelection, to: appState.trackedApps)
                appState.saveTrackedApps(apps)
            }
        }
    }

    private var lastSyncText: String {
        guard let date = SharedStore.shared.lastSyncAt else { return "never" }
        let f = RelativeDateTimeFormatter()
        return f.localizedString(for: date, relativeTo: Date())
    }
}
