import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var rangeDays = 7

    private var history: [DayUsage] { appState.store.history(days: rangeDays) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Range", selection: $rangeDays) {
                        Text("Week").tag(7)
                        Text("Month").tag(30)
                    }
                    .pickerStyle(.segmented)

                    summaryRow
                    chartCard
                    adherenceCard
                    appList
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats")
        }
    }

    // MARK: - Pieces

    private var totalLimitPerDay: Int {
        appState.trackedApps.reduce(0) { $0 + $1.limitMinutes }
    }

    private var summaryRow: some View {
        let days = history
        let total = days.reduce(0) { $0 + $1.totalMinutes }
        let activeDays = max(1, days.filter { $0.totalMinutes > 0 }.count)
        let opens = days.reduce(0) { sum, day in sum + day.apps.values.reduce(0) { $0 + $1.opens } }
        return HStack(spacing: 10) {
            StatPill(value: UsageMath.formatMinutes(total), caption: "total")
            StatPill(value: UsageMath.formatMinutes(total / activeDays), caption: "avg / day")
            StatPill(value: "\(opens)", caption: "opens")
        }
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Minutes per day")
                    .font(.subheadline.weight(.medium))
                Chart {
                    ForEach(history, id: \.day) { day in
                        let ratio = totalLimitPerDay > 0
                            ? Double(day.totalMinutes) / Double(totalLimitPerDay) : 0
                        BarMark(
                            x: .value("Day", shortLabel(day.day)),
                            y: .value("Minutes", day.totalMinutes)
                        )
                        .foregroundStyle(UsageMath.stateColor(ratio: ratio))
                        .cornerRadius(4)
                    }
                    if totalLimitPerDay > 0 {
                        RuleMark(y: .value("Limit", totalLimitPerDay))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("combined limit")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self),
                               rangeDays <= 7 || value.index % 5 == 0 {
                                Text(label).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var adherenceCard: some View {
        let days = history.filter { !$0.apps.isEmpty }
        let underLimitDays = days.filter { day in
            appState.trackedApps.allSatisfy { app in
                (day.apps[app.id]?.minutes ?? 0) <= app.limitMinutes
            }
        }.count
        let pct = days.isEmpty ? 100 : Int(Double(underLimitDays) / Double(days.count) * 100)
        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sticking to your limits")
                        .font(.subheadline.weight(.medium))
                    Text("\(underLimitDays) of \(max(days.count, 1)) days fully under limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(pct)%")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(UsageMath.stateColor(ratio: 1.0 - Double(pct) / 100.0 * 0.9))
            }
        }
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By app")
                .font(.subheadline.weight(.medium))
                .padding(.leading, 4)
            ForEach(appState.trackedApps) { app in
                NavigationLink {
                    AppDetailView(app: app)
                } label: {
                    AppStatRow(app: app, history: history)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shortLabel(_ day: String) -> String {
        guard let date = DayKey.date(from: day) else { return day }
        let f = DateFormatter()
        f.dateFormat = rangeDays <= 7 ? "EEE" : "d"
        return f.string(from: date)
    }
}

struct StatPill: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AppStatRow: View {
    let app: TrackedApp
    let history: [DayUsage]

    var body: some View {
        let minutes = history.reduce(0) { $0 + ($1.apps[app.id]?.minutes ?? 0) }
        let activeDays = history.filter { ($0.apps[app.id]?.minutes ?? 0) > 0 }.count
        let avg = activeDays > 0 ? minutes / activeDays : 0
        Card {
            HStack(spacing: 12) {
                AppIconView(app: app, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    AppTitleView(app: app).font(.body.weight(.medium))
                    Text("avg \(UsageMath.formatMinutes(avg)) on active days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(UsageMath.formatMinutes(minutes))
                    .font(.body.monospacedDigit().weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
