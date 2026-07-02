import ManagedSettings

/// Handles the reminder-screen buttons.
///  - "Continue anyway" (primary): grant a grace window so the app opens, then
///    re-shields itself when grace expires (reconciled on the next threshold
///    event / app foreground).
///  - "Not now" (secondary): close, returning the user to the Home Screen.
class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            if let app = SharedStore.shared.loadTrackedApps().first(where: { $0.token == application }) {
                ShieldController.grantGrace(appID: app.id)
            }
            completionHandler(.none)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
