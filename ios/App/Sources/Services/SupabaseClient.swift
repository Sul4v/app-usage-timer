import Foundation

/// Minimal hand-rolled client for Supabase's GoTrue (auth) and PostgREST
/// (data) HTTP APIs — a few dozen lines instead of a large SDK dependency.
struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    var email: String
    var expiresAt: Date
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Sync isn't configured in this build."
        case .server(let message): return message
        }
    }
}

final class SupabaseClient {
    let baseURL: URL
    let anonKey: String

    /// Reads SupabaseURL / SupabaseAnonKey from Info.plist. Returns nil when
    /// they're blank — the app then runs in local-only mode.
    static func fromBundle() -> SupabaseClient? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !urlString.isEmpty, !key.isEmpty, let url = URL(string: urlString)
        else { return nil }
        return SupabaseClient(baseURL: url, anonKey: key)
    }

    init(baseURL: URL, anonKey: String) {
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

    // MARK: - Auth

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: String; let email: String? }
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let user: User
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        try await authRequest(path: "auth/v1/signup", body: ["email": email, "password": password])
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await authRequest(path: "auth/v1/token?grant_type=password",
                              body: ["email": email, "password": password])
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        try await authRequest(path: "auth/v1/token?grant_type=refresh_token",
                              body: ["refresh_token": session.refreshToken])
    }

    private func authRequest(path: String, body: [String: String]) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent2(path))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response: response, data: data)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            userID: token.user.id,
            email: token.user.email ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in))
        )
    }

    // MARK: - Data

    func upsert<T: Encodable>(table: String, rows: [T], session: AuthSession, onConflict: String) async throws {
        guard !rows.isEmpty else { return }
        var components = URLComponents(
            url: baseURL.appendingPathComponent2("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: onConflict)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        setDataHeaders(&request, session: session)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(rows)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response: response, data: data)
    }

    func select<T: Decodable>(table: String, query: [URLQueryItem], session: AuthSession) async throws -> [T] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent2("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        setDataHeaders(&request, session: session)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([T].self, from: data)
    }

    private func setDataHeaders(_ request: inout URLRequest, session: AuthSession) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private static func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.server("No response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = (json["msg"] ?? json["message"] ?? json["error_description"]) as? String {
                throw SupabaseError.server(message)
            }
            throw SupabaseError.server("HTTP \(http.statusCode): \(body.prefix(200))")
        }
    }
}

private extension URL {
    /// appendingPathComponent percent-encodes "?" — split query-bearing paths.
    func appendingPathComponent2(_ path: String) -> URL {
        if let range = path.range(of: "?") {
            let base = appendingPathComponent(String(path[..<range.lowerBound]))
            return URL(string: "\(base.absoluteString)?\(path[range.upperBound...])") ?? base
        }
        return appendingPathComponent(path)
    }
}
