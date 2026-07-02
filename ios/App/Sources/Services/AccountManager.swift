import Foundation
import Security

@MainActor
final class AccountManager: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published var localMode: Bool {
        didSet { UserDefaults.standard.set(localMode, forKey: "localMode") }
    }

    let client = SupabaseClient.fromBundle()
    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { session != nil }

    init() {
        localMode = UserDefaults.standard.bool(forKey: "localMode")
        session = Keychain.load()
    }

    func signUp(email: String, password: String) async throws {
        guard let client else { throw SupabaseError.notConfigured }
        let session = try await client.signUp(email: email, password: password)
        store(session)
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw SupabaseError.notConfigured }
        let session = try await client.signIn(email: email, password: password)
        store(session)
    }

    func continueWithoutAccount() {
        localMode = true
    }

    func signOut() {
        session = nil
        localMode = false
        Keychain.delete()
    }

    /// Valid session, refreshed if it's about to expire.
    func validSession() async -> AuthSession? {
        guard let client, let current = session else { return nil }
        guard current.expiresAt < Date().addingTimeInterval(60) else { return current }
        guard let refreshed = try? await client.refresh(current) else { return nil }
        store(refreshed)
        return refreshed
    }

    private func store(_ session: AuthSession) {
        self.session = session
        localMode = false
        Keychain.save(session)
    }
}

/// Just enough Keychain to hold one auth session.
private enum Keychain {
    private static let account = "com.sodhera.capsule.session"

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
