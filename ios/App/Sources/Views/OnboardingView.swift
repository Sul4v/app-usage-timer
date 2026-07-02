import FamilyControls
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    private enum Step: Int, CaseIterable {
        case welcome, screenTime, pickApps, limits, notifications
    }

    @State private var step: Step = .welcome
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var draftApps: [TrackedApp] = []
    @State private var screenTimeDenied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Color.primary : Color.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)

            switch step {
            case .welcome: welcome
            case .screenTime: screenTime
            case .pickApps: pickApps
            case .limits: limits
            case .notifications: notifications
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { _, newSelection in
            draftApps = appState.screenTime.apply(selection: newSelection, to: draftApps)
        }
        .onAppear { draftApps = appState.trackedApps }
    }

    // MARK: - Steps

    private var welcome: some View {
        OnboardingPage(
            symbol: nil,
            title: "A gentle timer for the apps that eat your day",
            body: "Pick the apps you want to be conscious of. Whenever you use one, a small capsule keeps count — green while you're fine, red when you've had enough.",
            buttonTitle: "Set it up"
        ) {
            step = .screenTime
        } accessory: {
            HStack(spacing: 10) {
                ForEach([0.3, 0.75, 1.1], id: \.self) { ratio in
                    HStack(spacing: 8) {
                        Circle().fill(UsageMath.stateColor(ratio: ratio)).frame(width: 8, height: 8)
                        Text(UsageMath.formatMinutes(Int(ratio * 40)))
                            .font(.footnote.monospacedDigit().weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var screenTime: some View {
        OnboardingPage(
            symbol: "hourglass",
            title: "Allow Screen Time access",
            body: "Capsule uses Apple's Screen Time to measure how long you spend in the apps you choose. The data stays under Apple's privacy rules — we never see which apps you picked, only the time counts you let us keep.",
            buttonTitle: "Allow access",
            secondaryTitle: screenTimeDenied ? "Continue without it (demo mode)" : nil
        ) {
            Task {
                let granted = await appState.screenTime.requestAuthorization()
                if granted { step = .pickApps } else { screenTimeDenied = true }
            }
        } secondaryAction: {
            step = .pickApps
        } accessory: {
            if screenTimeDenied {
                Text("Screen Time access wasn't granted (it isn't available on the simulator). You can still explore Capsule with named apps and sample data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var pickApps: some View {
        VStack(spacing: 16) {
            ScreenTitle(title: "Which apps?", subtitle: "Pick the apps you want to keep an eye on.")
                .padding(.top, 32)

            if appState.screenTime.isAuthorized {
                Button {
                    showPicker = true
                } label: {
                    Label(draftApps.isEmpty ? "Choose apps" : "Change selection", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
            } else {
                demoAppGrid
            }

            if !draftApps.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(draftApps) { app in
                            Card {
                                HStack(spacing: 12) {
                                    AppIconView(app: app, size: 36)
                                    AppTitleView(app: app).font(.body.weight(.medium))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            Spacer()

            Button("Continue") { step = .limits }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(draftApps.isEmpty)
                .opacity(draftApps.isEmpty ? 0.4 : 1)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private static let demoChoices = ["Instagram", "TikTok", "YouTube", "X", "Reddit", "Snapchat"]

    private var demoAppGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
            ForEach(Self.demoChoices, id: \.self) { name in
                let isOn = draftApps.contains { $0.nickname == name }
                Button {
                    if isOn {
                        draftApps.removeAll { $0.nickname == name }
                    } else {
                        draftApps.append(TrackedApp(nickname: name))
                    }
                } label: {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isOn ? Color(.systemBackground) : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(isOn ? Color.primary : Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var limits: some View {
        VStack(spacing: 16) {
            ScreenTitle(
                title: "Daily limits",
                subtitle: "How much is enough? \(TrackedApp.defaultLimitMinutes) minutes is a sensible default — adjust anytime."
            )
            .padding(.top, 32)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($draftApps) { $app in
                        LimitEditorCard(app: $app)
                    }
                }
            }
            Spacer()

            Button("Continue") { step = .notifications }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, 24)
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private var notifications: some View {
        OnboardingPage(
            symbol: "bell",
            title: "One quiet heads-up",
            body: "Capsule nudges you once when you're close to a limit and once when you cross it. No streaks, no guilt trips.",
            buttonTitle: "Enable notifications",
            secondaryTitle: "Not now"
        ) {
            Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                finish()
            }
        } secondaryAction: {
            finish()
        } accessory: { EmptyView() }
    }

    private func finish() {
        appState.saveTrackedApps(draftApps)
        appState.completeOnboarding()
    }
}

struct LimitEditorCard: View {
    @Binding var app: TrackedApp

    var body: some View {
        Card {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    AppIconView(app: app, size: 36)
                    AppTitleView(app: app).font(.body.weight(.medium))
                    Spacer()
                    Text(UsageMath.formatMinutes(app.limitMinutes))
                        .font(.body.monospacedDigit().weight(.semibold))
                }
                Slider(
                    value: Binding(
                        get: { Double(app.limitMinutes) },
                        set: { app.limitMinutes = max(5, Int($0 / 5) * 5) }
                    ),
                    in: 5...240
                )
                .tint(.primary)
                if app.tokenData != nil {
                    TextField("Nickname (used in alerts & stats)", text: $app.nickname)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct OnboardingPage<Accessory: View>: View {
    let symbol: String?
    let title: String
    let body_: String
    let buttonTitle: String
    var secondaryTitle: String?
    let action: () -> Void
    var secondaryAction: (() -> Void)?
    @ViewBuilder var accessory: Accessory

    init(
        symbol: String?,
        title: String,
        body: String,
        buttonTitle: String,
        secondaryTitle: String? = nil,
        action: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.symbol = symbol
        self.title = title
        self.body_ = body
        self.buttonTitle = buttonTitle
        self.secondaryTitle = secondaryTitle
        self.action = action
        self.secondaryAction = secondaryAction
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
            Text(body_)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            accessory
            Spacer()
            Button(buttonTitle, action: action)
                .buttonStyle(PrimaryButtonStyle())
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 24)
    }
}
