import ActivityKit
import SwiftUI
import WidgetKit

/// The visible "capsule". By design it shows **color, not digits**: color is a
/// coarse, ambient signal, so the once-a-minute push cadence and brief offline
/// gaps are imperceptible (a slightly-stale green still reads green). The exact
/// minutes live where we can be accurate — the reminder screen before opening
/// an app, and the Today/Stats screens.
struct CapsuleLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CapsuleActivityAttributes.self) { context in
            LockScreenCapsuleView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.appNickname)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(statusWord(context))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color(context))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CapsuleProgressBar(ratio: context.state.ratio, color: color(context))
                        .frame(height: 8)
                        .padding(.top, 6)
                }
            } compactLeading: {
                Circle().fill(color(context)).frame(width: 12, height: 12)
            } compactTrailing: {
                // Thin colored bar: fill + color at a glance, no digits.
                CapsuleProgressBar(ratio: context.state.ratio, color: color(context))
                    .frame(width: 34, height: 6)
            } minimal: {
                Circle().fill(color(context)).frame(width: 12, height: 12)
            }
        }
    }

    /// Gray out once no update has arrived for a while — the session likely
    /// ended and the app/next push will refresh it.
    private func color(_ context: ActivityViewContext<CapsuleActivityAttributes>) -> Color {
        context.isStale ? .gray : UsageMath.stateColor(ratio: context.state.ratio)
    }

    private func statusWord(_ context: ActivityViewContext<CapsuleActivityAttributes>) -> String {
        if context.isStale { return "Paused" }
        return Self.statusWord(ratio: context.state.ratio)
    }

    static func statusWord(ratio: Double) -> String {
        switch ratio {
        case ..<0.5: return "On track"
        case ..<0.8: return "Doing well"
        case ..<1.0: return "Getting close"
        default: return "Over limit"
        }
    }
}

struct LockScreenCapsuleView: View {
    let state: CapsuleActivityAttributes.ContentState
    var stale = false

    private var color: Color {
        stale ? .gray : UsageMath.stateColor(ratio: state.ratio)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.appNickname)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                CapsuleProgressBar(ratio: state.ratio, color: color)
                    .frame(height: 6)
            }
            Spacer()
            Text(stale ? "Paused" : CapsuleLiveActivityWidget.statusWord(ratio: state.ratio))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(16)
    }
}

struct CapsuleProgressBar: View {
    let ratio: Double
    var color: Color = .green

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(ratio, 0.02), 1))
            }
        }
    }
}
