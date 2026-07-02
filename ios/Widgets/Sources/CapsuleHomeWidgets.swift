import Charts
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct CapsuleEntry: TimelineEntry {
    let date: Date
    let apps: [TrackedApp]
    let today: DayUsage
    let week: [DayUsage]

    var totalMinutes: Int { today.totalMinutes }
    var combinedLimit: Int { apps.reduce(0) { $0 + $1.limitMinutes } }
    var overallRatio: Double {
        combinedLimit > 0 ? Double(totalMinutes) / Double(combinedLimit) : 0
    }

    /// Tracked apps ordered by today's usage, heaviest first.
    var ranked: [(app: TrackedApp, usage: AppDayUsage)] {
        apps.map { ($0, today.apps[$0.id] ?? AppDayUsage()) }
            .sorted { $0.1.minutes > $1.1.minutes }
    }

    static func load() -> CapsuleEntry {
        let store = SharedStore.shared
        return CapsuleEntry(
            date: Date(),
            apps: store.loadTrackedApps(),
            today: store.todayUsage(),
            week: store.history(days: 7)
        )
    }

    static var placeholder: CapsuleEntry {
        let apps = [
            TrackedApp(nickname: "Instagram", limitMinutes: 45),
            TrackedApp(nickname: "TikTok", limitMinutes: 30),
            TrackedApp(nickname: "YouTube", limitMinutes: 60),
        ]
        var today = DayUsage(day: DayKey.today)
        today.apps[apps[0].id] = AppDayUsage(minutes: 32, opens: 6)
        today.apps[apps[1].id] = AppDayUsage(minutes: 12, opens: 3)
        today.apps[apps[2].id] = AppDayUsage(minutes: 18, opens: 2)
        let cal = Calendar.current
        let week = (0..<7).reversed().map { offset -> DayUsage in
            let date = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            var day = DayUsage(day: DayKey.from(date))
            day.apps[apps[0].id] = AppDayUsage(minutes: [70, 95, 40, 120, 65, 150, 62][offset % 7])
            return day
        }
        return CapsuleEntry(date: Date(), apps: apps, today: today, week: week)
    }
}

struct CapsuleProvider: TimelineProvider {
    func placeholder(in context: Context) -> CapsuleEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CapsuleEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CapsuleEntry>) -> Void) {
        // Data only changes when the app / monitor extension reloads us, but a
        // 15-minute cadence keeps "today" fresh across midnight regardless.
        completion(Timeline(entries: [.load()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

// MARK: - Widget

struct CapsuleTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CapsuleToday", provider: CapsuleProvider()) { entry in
            CapsuleWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Capsule — Today")
        .description("Your tracked screen time at a glance: total, per-app progress, and the week.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular,
        ])
    }
}

struct CapsuleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CapsuleEntry

    var body: some View {
        if entry.apps.isEmpty {
            emptyState
        } else {
            switch family {
            case .systemSmall: SmallRingView(entry: entry)
            case .systemMedium: MediumAppsView(entry: entry)
            case .systemLarge: LargeOverviewView(entry: entry)
            case .accessoryCircular: AccessoryRingView(entry: entry)
            case .accessoryRectangular: AccessoryBarView(entry: entry)
            default: SmallRingView(entry: entry)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Capsule().fill(UsageMath.green).frame(width: 34, height: 14)
            Text("Pick apps to track in Capsule")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Shared pieces

/// State-colored ring, the widget counterpart of the capsule.
struct RingView: View {
    let ratio: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(ratio, 0.02), 1))
                .stroke(
                    UsageMath.stateColor(ratio: ratio),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

struct WidgetAppRow: View {
    let app: TrackedApp
    let usage: AppDayUsage

    private var ratio: Double {
        app.limitMinutes > 0 ? Double(usage.minutes) / Double(app.limitMinutes) : 0
    }

    var body: some View {
        // Note: real app icons/names cannot appear here — iOS renders a
        // "prohibited" placeholder for Screen Time tokens in widgets
        // (verified on device). Nickname + monogram is the honest option.
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                Text(String(app.nickname.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.nickname)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(UsageMath.formatMinutes(usage.minutes))
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(UsageMath.stateColor(ratio: ratio))
                    + Text(" / \(UsageMath.formatMinutes(app.limitMinutes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(UsageMath.stateColor(ratio: ratio))
                            .frame(width: geo.size.width * min(max(ratio, 0.02), 1))
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

// MARK: - Small: today ring

struct SmallRingView: View {
    let entry: CapsuleEntry

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RingView(ratio: entry.overallRatio)
                VStack(spacing: 0) {
                    Text(UsageMath.formatMinutes(entry.totalMinutes))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                    Text("today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            Text("of \(UsageMath.formatMinutes(entry.combinedLimit)) across \(entry.apps.count) apps")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Medium: top apps

struct MediumAppsView: View {
    let entry: CapsuleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(UsageMath.formatMinutes(entry.totalMinutes))
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(UsageMath.stateColor(ratio: entry.overallRatio))
                    .frame(width: 8, height: 8)
            }
            VStack(spacing: 8) {
                ForEach(entry.ranked.prefix(3), id: \.app.id) { item in
                    WidgetAppRow(app: item.app, usage: item.usage)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Large: week chart + apps

struct LargeOverviewView: View {
    let entry: CapsuleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(UsageMath.formatMinutes(entry.totalMinutes))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(entry.week, id: \.day) { day in
                    let ratio = entry.combinedLimit > 0
                        ? Double(day.totalMinutes) / Double(entry.combinedLimit) : 0
                    BarMark(
                        x: .value("Day", shortLabel(day.day)),
                        y: .value("Minutes", day.totalMinutes)
                    )
                    .foregroundStyle(UsageMath.stateColor(ratio: ratio))
                    .cornerRadius(3)
                }
                if entry.combinedLimit > 0 {
                    RuleMark(y: .value("Limit", entry.combinedLimit))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2) }
            }
            .frame(height: 88)

            VStack(spacing: 8) {
                ForEach(entry.ranked.prefix(3), id: \.app.id) { item in
                    WidgetAppRow(app: item.app, usage: item.usage)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func shortLabel(_ day: String) -> String {
        guard let date = DayKey.date(from: day) else { return day }
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }
}

// MARK: - Lock screen accessories

struct AccessoryRingView: View {
    let entry: CapsuleEntry

    var body: some View {
        Gauge(value: min(entry.overallRatio, 1)) {
            Text("Capsule")
        } currentValueLabel: {
            Text(UsageMath.formatMinutes(entry.totalMinutes))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct AccessoryBarView: View {
    let entry: CapsuleEntry

    var body: some View {
        let top = entry.ranked.first
        VStack(alignment: .leading, spacing: 3) {
            Text("Capsule · \(UsageMath.formatMinutes(entry.totalMinutes)) today")
                .font(.caption.weight(.semibold))
            if let top {
                Text("\(top.app.nickname) \(UsageMath.formatMinutes(top.usage.minutes)) of \(UsageMath.formatMinutes(top.app.limitMinutes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.tertiary)
                        let ratio = top.app.limitMinutes > 0
                            ? Double(top.usage.minutes) / Double(top.app.limitMinutes) : 0
                        Capsule().frame(width: geo.size.width * min(max(ratio, 0.03), 1))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}
