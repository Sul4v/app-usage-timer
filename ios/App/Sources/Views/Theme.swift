import FamilyControls
import ManagedSettings
import SwiftUI

/// Calm and restrained: system backgrounds, generous whitespace, neutral
/// text. The only saturated color anywhere is the usage-state green→red.
enum Theme {
    static let cardCorner: CGFloat = 20
    static let screenPadding: CGFloat = 24
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }
}

/// In-app usage bar, same color language as the floating capsule.
struct UsageBar: View {
    let ratio: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06))
                Capsule()
                    .fill(UsageMath.stateColor(ratio: ratio))
                    .frame(width: geo.size.width * min(max(ratio, 0.015), 1))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: ratio)
    }
}

/// Real app name when we have a Screen Time token. The system renders the
/// text — our code can show it but never read it — so notifications and
/// sync still use the editable nickname.
struct AppTitleView: View {
    let app: TrackedApp

    var body: some View {
        if let token = app.token {
            Label(token).labelStyle(.titleOnly)
        } else {
            Text(app.nickname)
        }
    }
}

/// Real app icon when we have a Screen Time token (system-rendered, opaque
/// to us), otherwise a neutral monogram circle.
struct AppIconView: View {
    let app: TrackedApp
    var size: CGFloat = 40

    var body: some View {
        if let token = app.token {
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(size / 24)
                .frame(width: size, height: size)
        } else {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                Text(String(app.nickname.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(.systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.primary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
