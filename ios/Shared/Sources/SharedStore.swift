import Foundation

/// Persistence shared between the app, the DeviceActivity monitor extension,
/// and the widget extension, via the App Group container.
///
/// Tracked apps + settings live in the shared UserDefaults suite; usage history
/// is one JSON file per day so the monitor extension's frequent writes stay
/// small and midnight rollover is free.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.com.sodhera.capsule"
    public static let shared = SharedStore()

    private let defaults: UserDefaults
    private let usageDir: URL
    private let queue = DispatchQueue(label: "com.sodhera.capsule.store")

    private enum Key {
        static let trackedApps = "trackedApps"
        static let shieldWhenOverLimit = "shieldWhenOverLimit"
        static let familySelection = "familyActivitySelection"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastSyncAt = "lastSyncAt"
        static let lastCapsuleDiag = "lastCapsuleDiag"
        static let lastThresholdAt = "lastThresholdAt"
    }

    private init() {
        defaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        usageDir = container.appendingPathComponent("usage", isDirectory: true)
        try? FileManager.default.createDirectory(at: usageDir, withIntermediateDirectories: true)
    }

    // MARK: - Tracked apps

    public func loadTrackedApps() -> [TrackedApp] {
        guard let data = defaults.data(forKey: Key.trackedApps) else { return [] }
        return (try? JSONDecoder().decode([TrackedApp].self, from: data)) ?? []
    }

    public func saveTrackedApps(_ apps: [TrackedApp]) {
        if let data = try? JSONEncoder().encode(apps) {
            defaults.set(data, forKey: Key.trackedApps)
        }
    }

    public func trackedApp(id: UUID) -> TrackedApp? {
        loadTrackedApps().first { $0.id == id }
    }

    // MARK: - Settings

    public var shieldWhenOverLimit: Bool {
        get { defaults.bool(forKey: Key.shieldWhenOverLimit) }
        set { defaults.set(newValue, forKey: Key.shieldWhenOverLimit) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    public var lastSyncAt: Date? {
        get { defaults.object(forKey: Key.lastSyncAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSyncAt) }
    }

    /// Diagnostics for the capsule pipeline, written by the monitor extension
    /// and shown in Settings so the live behaviour is observable on-device.

    /// When the extension last received *any* usage-threshold event — proves
    /// the Screen Time monitoring itself is alive.
    public var lastThresholdAt: Date? {
        get { defaults.object(forKey: Key.lastThresholdAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastThresholdAt) }
    }

    public struct CapsuleDiag: Codable, Equatable {
        public var at: Date
        public var targetMinutes: Int
        public var result: String
        public var detail: String
        public init(at: Date, targetMinutes: Int, result: String, detail: String) {
            self.at = at; self.targetMinutes = targetMinutes
            self.result = result; self.detail = detail
        }
    }

    /// Outcome of the extension's most recent capsule-update attempt.
    public var lastCapsuleDiag: CapsuleDiag? {
        get {
            guard let data = defaults.data(forKey: Key.lastCapsuleDiag) else { return nil }
            return try? JSONDecoder().decode(CapsuleDiag.self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.lastCapsuleDiag)
            }
        }
    }

    /// Raw `FamilyActivitySelection` (Codable) so monitoring can be
    /// re-registered without re-prompting the user.
    public var familySelectionData: Data? {
        get { defaults.data(forKey: Key.familySelection) }
        set { defaults.set(newValue, forKey: Key.familySelection) }
    }

    // MARK: - Usage

    private func fileURL(for day: String) -> URL {
        usageDir.appendingPathComponent("\(day).json")
    }

    public func usage(for day: String) -> DayUsage {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL(for: day)),
                  let usage = try? JSONDecoder().decode(DayUsage.self, from: data)
            else { return DayUsage(day: day) }
            return usage
        }
    }

    public func save(_ usage: DayUsage) {
        queue.sync {
            if let data = try? JSONEncoder().encode(usage) {
                try? data.write(to: fileURL(for: usage.day), options: .atomic)
            }
        }
    }

    public func todayUsage() -> DayUsage { usage(for: DayKey.today) }

    /// Called by the monitor extension when a cumulative-usage threshold fires.
    /// Threshold events only tell us "app X has now been used N minutes today",
    /// so sessions are approximated: a gap of more than 3 minutes between
    /// events starts a new session. Returns the updated day usage.
    @discardableResult
    public func recordThreshold(appID: UUID, cumulativeMinutes: Int, at date: Date = Date()) -> DayUsage {
        var day = usage(for: DayKey.from(date))
        var app = day.apps[appID] ?? AppDayUsage()
        app.minutes = max(app.minutes, cumulativeMinutes)

        let sessionGap: TimeInterval = 3 * 60
        if var last = app.sessions.last, date.timeIntervalSince(last.end) <= sessionGap {
            last.end = date
            app.sessions[app.sessions.count - 1] = last
        } else {
            // First minute of a new session: it started roughly a minute ago.
            app.sessions.append(UsageSession(start: date.addingTimeInterval(-60), end: date))
            app.opens += 1
        }
        day.apps[appID] = app
        save(day)
        return day
    }

    public func markNotified(appID: UUID, overLimit: Bool, day dayKey: String = DayKey.today) {
        var day = usage(for: dayKey)
        var app = day.apps[appID] ?? AppDayUsage()
        if overLimit { app.notifiedOverLimit = true } else { app.notifiedNearLimit = true }
        day.apps[appID] = app
        save(day)
    }

    /// Most recent `days` of usage, oldest first, including empty days.
    public func history(days: Int, endingAt end: Date = Date()) -> [DayUsage] {
        let cal = Calendar.current
        return (0..<days).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return usage(for: DayKey.from(date))
        }
    }

    public func allUsageDays() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: usageDir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}
