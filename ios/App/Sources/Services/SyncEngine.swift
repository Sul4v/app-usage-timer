import Foundation

/// Pushes tracked apps + recent usage to Supabase and pulls limit/nickname
/// changes made on other devices (last-write-wins by updated_at).
///
/// Note: iOS app tokens are opaque and device-bound, so what syncs is the
/// nickname, the limit, and the usage numbers — not the token itself. A new
/// device re-picks the apps once; edits then flow both ways.
@MainActor
final class SyncEngine: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private let account: AccountManager
    private let store: SharedStore

    init(account: AccountManager, store: SharedStore) {
        self.account = account
        self.store = store
    }

    struct TrackedAppRow: Codable {
        var id: String
        var user_id: String
        var platform: String
        var nickname: String
        var limit_minutes: Int
        var created_at: Date
        var updated_at: Date
    }

    struct SessionDTO: Codable {
        var start: Date
        var end: Date
    }

    struct DailyUsageRow: Codable {
        var user_id: String
        var app_id: String
        var day: String
        var minutes: Int
        var opens: Int
        var sessions: [SessionDTO]
    }

    func syncNow() async {
        guard let client = account.client,
              let session = await account.validSession(),
              !isSyncing
        else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await pullApps(client: client, session: session)
            try await pushApps(client: client, session: session)
            try await pushUsage(client: client, session: session)
            store.lastSyncAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func pushApps(client: SupabaseClient, session: AuthSession) async throws {
        let rows = store.loadTrackedApps().map {
            TrackedAppRow(id: $0.id.uuidString.lowercased(), user_id: session.userID,
                          platform: "ios", nickname: $0.nickname, limit_minutes: $0.limitMinutes,
                          created_at: $0.createdAt, updated_at: $0.updatedAt)
        }
        try await client.upsert(table: "tracked_apps", rows: rows, session: session, onConflict: "id")
    }

    private func pullApps(client: SupabaseClient, session: AuthSession) async throws {
        let remote: [TrackedAppRow] = try await client.select(
            table: "tracked_apps",
            query: [URLQueryItem(name: "user_id", value: "eq.\(session.userID)"),
                    URLQueryItem(name: "platform", value: "eq.ios")],
            session: session
        )
        var apps = store.loadTrackedApps()
        for row in remote {
            guard let id = UUID(uuidString: row.id),
                  let i = apps.firstIndex(where: { $0.id == id }),
                  row.updated_at > apps[i].updatedAt
            else { continue }
            apps[i].nickname = row.nickname
            apps[i].limitMinutes = row.limit_minutes
            apps[i].updatedAt = row.updated_at
        }
        store.saveTrackedApps(apps)
    }

    private func pushUsage(client: SupabaseClient, session: AuthSession) async throws {
        var rows: [DailyUsageRow] = []
        for day in store.history(days: 7) where !day.apps.isEmpty {
            for (appID, usage) in day.apps where usage.minutes > 0 {
                rows.append(DailyUsageRow(
                    user_id: session.userID,
                    app_id: appID.uuidString.lowercased(),
                    day: day.day,
                    minutes: usage.minutes,
                    opens: usage.opens,
                    sessions: usage.sessions.map { SessionDTO(start: $0.start, end: $0.end) }
                ))
            }
        }
        try await client.upsert(table: "daily_usage", rows: rows, session: session,
                                onConflict: "user_id,app_id,day")
    }
}
