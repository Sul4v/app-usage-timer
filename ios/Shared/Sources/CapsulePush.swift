import Foundation

/// Talks to the two Supabase Edge Functions behind the live capsule:
/// `capsule-register` (app stores its Live Activity push token) and
/// `capsule-push` (monitor extension asks the server to push a fresh capsule
/// value to this device). Both are called with the public anon key.
public enum CapsulePush {
    private static let base = URL(string: "https://ubglgtworopygeenbnvb.supabase.co/functions/v1")!
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InViZ2xndHdvcm9weWdlZW5ibnZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5ODEyOTksImV4cCI6MjA5ODU1NzI5OX0.q4vUpxgxzLBaV1iZsjZgAXiQKaJETLYd7Z5lFmRLVto"

    public struct Outcome {
        public var ok: Bool
        public var detail: String
    }

    @discardableResult
    public static func registerToken(_ token: String, deviceID: String) async -> Bool {
        await post("capsule-register", ["device_id": deviceID, "token": token]).ok
    }

    /// Ask the server to push an updated capsule to this device. Called from
    /// the monitor extension on each usage-threshold event.
    public static func reportUsage(deviceID: String, appNickname: String,
                                   usedMinutes: Int, limitMinutes: Int) async -> Outcome {
        await post("capsule-push", [
            "device_id": deviceID,
            "app_nickname": appNickname,
            "used_minutes": usedMinutes,
            "limit_minutes": limitMinutes,
        ])
    }

    private static func post(_ path: String, _ body: [String: Any]) async -> Outcome {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return Outcome(ok: false, detail: "network error")
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        return Outcome(ok: (200..<300).contains(code), detail: "HTTP \(code) \(text.prefix(100))")
    }
}
