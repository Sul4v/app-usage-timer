import Foundation

/// Deterministic demo data so the app is fully explorable on the simulator,
/// where the Screen Time API (and therefore real tracking) is unavailable.
enum SampleData {
    static func seedIfNeeded(store: SharedStore) {
        guard store.loadTrackedApps().isEmpty, !store.hasCompletedOnboarding else { return }
        guard !UserDefaults.standard.bool(forKey: "sampleDataSeeded") else { return }
        UserDefaults.standard.set(true, forKey: "sampleDataSeeded")
        seed(store: store)
    }

    static func seed(store: SharedStore) {
        let apps = [
            TrackedApp(nickname: "Instagram", limitMinutes: 45),
            TrackedApp(nickname: "TikTok", limitMinutes: 30),
            TrackedApp(nickname: "YouTube", limitMinutes: 60),
        ]
        store.saveTrackedApps(apps)

        var generator = SeededGenerator(seed: 42)
        let cal = Calendar.current
        for offset in 0..<14 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = DayKey.from(date)
            var day = DayUsage(day: key)
            for (i, app) in apps.enumerated() {
                // Weekends heavier; today partially elapsed.
                let weekday = cal.component(.weekday, from: date)
                let weekendBoost = (weekday == 1 || weekday == 7) ? 1.5 : 1.0
                var minutes = Int(Double(app.limitMinutes) * Double.random(in: 0.3...1.4, using: &generator) * weekendBoost)
                if offset == 0 { minutes = min(minutes, [32, 41, 18][i]) }
                let opens = max(1, minutes / Int.random(in: 4...9, using: &generator))
                var sessions: [UsageSession] = []
                var cursor = cal.date(bySettingHour: 8, minute: 15, second: 0, of: date) ?? date
                var remaining = minutes
                for _ in 0..<opens {
                    let length = max(1, remaining / max(1, opens - sessions.count) + Int.random(in: -3...3, using: &generator))
                    let clamped = min(max(1, length), remaining)
                    let start = cursor.addingTimeInterval(Double(Int.random(in: 20...110, using: &generator)) * 60)
                    let end = start.addingTimeInterval(Double(clamped) * 60)
                    sessions.append(UsageSession(start: start, end: end))
                    cursor = end
                    remaining -= clamped
                    if remaining <= 0 { break }
                }
                day.apps[app.id] = AppDayUsage(minutes: minutes, opens: sessions.count, sessions: sessions)
            }
            store.save(day)
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
