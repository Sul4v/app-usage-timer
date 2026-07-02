import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isSignUp = true
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Capsule()
                    .fill(UsageMath.green)
                    .frame(width: 56, height: 24)
                Text("Capsule")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text("Know where your time goes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                if appState.account.isConfigured {
                    Picker("", selection: $isSignUp) {
                        Text("Create account").tag(true)
                        Text("Sign in").tag(false)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 1) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground))
                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(UsageMath.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(isSignUp ? "Create account" : "Sign in") {
                        submit()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isBusy || email.isEmpty || password.count < 6)
                    .opacity(email.isEmpty || password.count < 6 ? 0.4 : 1)
                } else {
                    Text("This build isn't connected to a sync server, so your data stays on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if appState.account.isConfigured {
                    Button("Continue without an account") {
                        appState.account.continueWithoutAccount()
                        appState.didAuthenticate()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Button("Get started") {
                        appState.account.continueWithoutAccount()
                        appState.didAuthenticate()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, Theme.screenPadding)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func submit() {
        errorMessage = nil
        isBusy = true
        Task {
            do {
                if isSignUp {
                    try await appState.account.signUp(email: email, password: password)
                } else {
                    try await appState.account.signIn(email: email, password: password)
                }
                appState.didAuthenticate()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}
