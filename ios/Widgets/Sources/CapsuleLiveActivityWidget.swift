import ActivityKit
import SwiftUI
import WidgetKit

/// The visible "capsule": compact Dynamic Island states while another app is
/// open, an expanded island on long-press, and a Lock Screen banner.
struct CapsuleLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CapsuleActivityAttributes.self) { context in
            LockScreenCapsuleView(state: context.state)
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
                    Text("\(UsageMath.formatMinutes(context.state.usedMinutes)) / \(UsageMath.formatMinutes(context.state.limitMinutes))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(UsageMath.stateColor(ratio: context.state.ratio))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        CapsuleProgressBar(ratio: context.state.ratio)
                            .frame(height: 8)
                        Text(statusLine(context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Circle()
                    .fill(capsuleColor(context))
                    .frame(width: 12, height: 12)
            } compactTrailing: {
                Text(UsageMath.formatMinutes(context.state.usedMinutes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(capsuleColor(context))
            } minimal: {
                Circle()
                    .fill(capsuleColor(context))
                    .frame(width: 12, height: 12)
            }
        }
    }

    /// Gray out once no usage has been reported for a few minutes — the
    /// session likely ended and the app will clear the capsule when opened.
    private func capsuleColor(_ context: ActivityViewContext<CapsuleActivityAttributes>) -> Color {
        context.isStale ? .gray : UsageMath.stateColor(ratio: context.state.ratio)
    }

    private func statusLine(_ state: CapsuleActivityAttributes.ContentState) -> String {
        let over = state.usedMinutes - state.limitMinutes
        if over >= 0 { return "\(UsageMath.formatMinutes(over)) over your daily limit" }
        return "\(UsageMath.formatMinutes(-over)) left today"
    }
}

struct LockScreenCapsuleView: View {
    let state: CapsuleActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(UsageMath.stateColor(ratio: state.ratio))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.appNickname)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                CapsuleProgressBar(ratio: state.ratio)
                    .frame(height: 6)
            }
            Spacer()
            Text("\(UsageMath.formatMinutes(state.usedMinutes)) / \(UsageMath.formatMinutes(state.limitMinutes))")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(UsageMath.stateColor(ratio: state.ratio))
        }
        .padding(16)
    }
}

struct CapsuleProgressBar: View {
    let ratio: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(UsageMath.stateColor(ratio: ratio))
                    .frame(width: geo.size.width * min(max(ratio, 0.02), 1))
            }
        }
    }
}
