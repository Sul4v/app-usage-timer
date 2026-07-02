import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingApp: TrackedApp?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if appState.trackedApps.contains(where: { $0.nickname.wholeMatch(of: /App \d+/) != nil }) {
                        Card {
                            Text("Some apps still have placeholder names. Tap a row and give it its real name — widgets, alerts and the reminder screen all use it (Apple doesn't let us read the actual name).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(appState.trackedApps) { app in
                            Button {
                                editingApp = app
                            } label: {
                                TodayAppCard(app: app, usage: appState.today.apps[app.id] ?? AppDayUsage())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if appState.trackedApps.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .sheet(item: $editingApp) { app in
                EditAppSheet(app: app)
                    .presentationDetents([.medium])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UsageMath.formatMinutes(appState.today.totalMinutes))
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("across \(appState.trackedApps.count) tracked app\(appState.trackedApps.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No apps tracked yet")
                .font(.headline)
            Text("Add apps in Settings to start seeing your time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }
}

struct TodayAppCard: View {
    let app: TrackedApp
    let usage: AppDayUsage

    private var ratio: Double {
        app.limitMinutes > 0 ? Double(usage.minutes) / Double(app.limitMinutes) : 0
    }

    var body: some View {
        Card {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    AppIconView(app: app)
                    VStack(alignment: .leading, spacing: 2) {
                        AppTitleView(app: app)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(usage.opens) open\(usage.opens == 1 ? "" : "s") today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UsageMath.formatMinutes(usage.minutes))
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(UsageMath.stateColor(ratio: ratio))
                        Text("of \(UsageMath.formatMinutes(app.limitMinutes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                UsageBar(ratio: ratio)
            }
        }
    }
}

struct EditAppSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var app: TrackedApp
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 14) {
                    AppIconView(app: app, size: 48)
                    AppTitleView(app: app)
                        .font(.title3.weight(.medium))
                    Spacer()
                }
                .padding(.top, 8)

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Nickname", text: $app.nickname)
                            .font(.body.weight(.medium))
                        Text("Apple hides real app names from us, so alerts, stats and sync use this name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Daily limit").font(.subheadline)
                            Spacer()
                            Text(UsageMath.formatMinutes(app.limitMinutes))
                                .font(.body.monospacedDigit().weight(.semibold))
                        }
                        Slider(
                            value: Binding(
                                get: { Double(app.limitMinutes) },
                                set: { app.limitMinutes = max(5, Int($0 / 5) * 5) }
                            ),
                            in: 5...240
                        )
                        .tint(.primary)
                    }
                }

                Spacer()

                Button("Stop tracking this app", role: .destructive) {
                    confirmDelete = true
                }
                .font(.subheadline)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var apps = appState.trackedApps
                        if let i = apps.firstIndex(where: { $0.id == app.id }) {
                            apps[i] = app
                            appState.saveTrackedApps(apps)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Stop tracking \(app.nickname)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Stop tracking", role: .destructive) {
                    appState.saveTrackedApps(appState.trackedApps.filter { $0.id != app.id })
                    dismiss()
                }
            } message: {
                Text("Its history stays in your stats.")
            }
        }
    }
}
