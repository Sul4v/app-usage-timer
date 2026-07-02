import Foundation
import ManagedSettings

/// An app the user chose to track, with its daily limit.
///
/// On iOS the system gives us an opaque `ApplicationToken` for a picked app —
/// we can render its real name/icon via `Label(token)` but can never read them.
/// `nickname` is the user-editable name used for stats and cross-device sync.
public struct TrackedApp: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var nickname: String
    public var limitMinutes: Int
    public var tokenData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public static let defaultLimitMinutes = 45

    public init(
        id: UUID = UUID(),
        nickname: String,
        limitMinutes: Int = TrackedApp.defaultLimitMinutes,
        tokenData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.nickname = nickname
        self.limitMinutes = limitMinutes
        self.tokenData = tokenData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var token: ApplicationToken? {
        guard let tokenData else { return nil }
        return (try? JSONDecoder().decode([ApplicationToken].self, from: tokenData))?.first
    }

    public static func encode(token: ApplicationToken) -> Data? {
        try? JSONEncoder().encode([token])
    }
}

/// One continuous stretch of usage inside a tracked app.
public struct UsageSession: Codable, Equatable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var seconds: Int { max(0, Int(end.timeIntervalSince(start))) }
}

/// A single app's usage for one day.
public struct AppDayUsage: Codable, Equatable {
    public var minutes: Int
    public var opens: Int
    public var sessions: [UsageSession]
    /// Day-relative flags so milestone notifications fire once.
    public var notifiedNearLimit: Bool
    public var notifiedOverLimit: Bool

    public init(minutes: Int = 0, opens: Int = 0, sessions: [UsageSession] = [],
                notifiedNearLimit: Bool = false, notifiedOverLimit: Bool = false) {
        self.minutes = minutes
        self.opens = opens
        self.sessions = sessions
        self.notifiedNearLimit = notifiedNearLimit
        self.notifiedOverLimit = notifiedOverLimit
    }
}

/// All tracked-app usage for one calendar day. Keyed by day string so the
/// "today" counter resets naturally at midnight.
public struct DayUsage: Codable, Equatable {
    public var day: String // yyyy-MM-dd, local time
    public var apps: [UUID: AppDayUsage]

    public init(day: String, apps: [UUID: AppDayUsage] = [:]) {
        self.day = day
        self.apps = apps
    }

    public var totalMinutes: Int { apps.values.reduce(0) { $0 + $1.minutes } }
}

public enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func from(_ date: Date) -> String { formatter.string(from: date) }
    public static func date(from key: String) -> Date? { formatter.date(from: key) }
    public static var today: String { from(Date()) }
}
