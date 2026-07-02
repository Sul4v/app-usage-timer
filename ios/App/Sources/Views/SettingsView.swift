import FamilyControls
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()
    @State private var shieldOn = SharedStore.shared.shieldWhenOverLimit
    @State private var interstitialOn = SharedStore.shared.interstitialEnabled

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if appState.screenTime.isAuthorized {
                        LabeledContent("Tracking") {
                            if appState.screenTime.isMonitoring {
                                Text("Active").foregroundStyle(UsageMath.green)
                            } else if appState.trackedApps.contains(where: { $0.tokenData != nil }) {
                                Button("Inactive — tap to restart") {
                                    appState.screenTime.scheduleMonitoring(apps: appState.trackedApps)
                                }
                                .foregroundStyle(UsageMath.red)
                            } else {
                                Text("No apps selected").foregroundStyle(.secondary)
                            }
                        }
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
                    Toggle("Remind me before opening", isOn: $interstitialOn)
                        .onChange(of: interstitialOn) { _, on in
                            SharedStore.shared.interstitialEnabled = on
                            ShieldController.reconcile()
                        }
                    Toggle("Block apps when over limit", isOn: $shieldOn)
                        .onChange(of: shieldOn) { _, on in
                            SharedStore.shared.shieldWhenOverLimit = on
                            ShieldController.reconcile()
                        }
                } header: {
                    Text("Tracked apps")
                } footer: {
                    Text("“Remind me” shows a screen with today's usage each time you open a tracked app, so you decide with the number in front of you. After you continue, it waits \(SharedStore.shared.graceMinutes) minutes before asking again.")
                }

                Section {
                    LabeledContent("Last usage event") {
                        Text(relative(SharedStore.shared.lastThresholdAt))
                    }
                    if let diag = SharedStore.shared.lastCapsuleDiag {
                        let ok = diag.result == "pushed" || diag.result == "updated"
                        LabeledContent("Last capsule update") {
                            Text("\(diag.result) · \(UsageMath.formatMinutes(diag.targetMinutes)) · \(relative(diag.at))")
                                .foregroundStyle(ok ? UsageMath.green : UsageMath.red)
                                .multilineTextAlignment(.trailing)
                        }
                        if !ok {
                            Text(diag.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No capsule update recorded yet — use a tracked app for a full minute.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Capsule diagnostics")
                } footer: {
                    Text("“Last usage event” shows Screen Time is reporting; “Last capsule update” shows whether the Dynamic Island capsule is being driven.")
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

    private func relative(_ date: Date?) -> String {
        guard let date else { return "never" }
        let f = RelativeDateTimeFormatter()
        return f.localizedString(for: date, relativeTo: Date())
    }
}
