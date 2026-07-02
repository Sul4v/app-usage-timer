import Charts
import SwiftUI

/// Per-app drill-down: 14-day trend against the limit, plus every session
/// for a selectable day (iOS sessions are approximated from Screen Time
/// threshold events — see README).
struct AppDetailView: View {
    @EnvironmentObject private var appState: AppState
    let app: TrackedApp

    @State private var selectedDay = DayKey.today

    private var history: [DayUsage] { appState.store.history(days: 14) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                chartCard
                daySessions
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(app.nickname)
        .navigationBarTitleDisplayMode(.large)
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last 14 days")
                    .font(.subheadline.weight(.medium))
                Chart {
                    ForEach(history, id: \.day) { day in
                        let minutes = day.apps[app.id]?.minutes ?? 0
                        let ratio = app.limitMinutes > 0 ? Double(minutes) / Double(app.limitMinutes) : 0
                        BarMark(
                            x: .value("Day", String(day.day.suffix(2))),
                            y: .value("Minutes", minutes)
                        )
                        .foregroundStyle(
                            day.day == selectedDay
                                ? UsageMath.stateColor(ratio: ratio)
                                : UsageMath.stateColor(ratio: ratio).opacity(0.45)
                        )
                        .cornerRadius(4)
                    }
                    RuleMark(y: .value("Limit", app.limitMinutes))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("limit \(UsageMath.formatMinutes(app.limitMinutes))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(height: 170)

                // Day selector for the session list below.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(history.reversed(), id: \.day) { day in
                            let isSelected = day.day == selectedDay
                            Button {
                                selectedDay = day.day
                            } label: {
                                Text(dayLabel(day.day))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isSelected ? Color.primary : Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private var daySessions: some View {
        let usage = appState.store.usage(for: selectedDay).apps[app.id] ?? AppDayUsage()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sessions")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(usage.opens) opens · \(UsageMath.formatMinutes(usage.minutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if usage.sessions.isEmpty {
                Card {
                    Text("No sessions this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ForEach(Array(usage.sessions.enumerated()), id: \.offset) { _, session in
                    Card {
                        HStack {
                            Text("\(timeString(session.start)) – \(timeString(session.end))")
                                .font(.subheadline.monospacedDigit())
                            Spacer()
                            Text(UsageMath.formatSeconds(session.seconds))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func dayLabel(_ day: String) -> String {
        if day == DayKey.today { return "Today" }
        guard let date = DayKey.date(from: day) else { return day }
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f.string(from: date)
    }
}
