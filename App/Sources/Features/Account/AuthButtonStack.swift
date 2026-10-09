import SwiftUI
import AuthenticationServices

/// "Mit Apple / Google / Microsoft anmelden" buttons following each provider's branding,
/// shared by onboarding and settings. Calls `onSignedIn` after a successful sign-in.
struct AuthButtonStack: View {
    var showsContinueWithoutAccount = false
    var onSignedIn: () -> Void = {}
    var onContinueWithoutAccount: () -> Void = {}

    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private let height: CGFloat = 54

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                app.auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task {
                    await app.auth.handleAppleCompletion(result)
                    if app.auth.isSignedIn { onSignedIn() }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: height)
            .clipShape(Capsule())
            .accessibilityLabel("Mit Apple anmelden")

            providerButton(.google, title: "Mit Google anmelden") { GoogleLogo(size: 20) }
            providerButton(.microsoft, title: "Mit Microsoft anmelden") { MicrosoftLogo(size: 18) }

            if showsContinueWithoutAccount {
                Button("Ohne Konto fortfahren") {
                    app.auth.continueWithoutAccount()
                    onContinueWithoutAccount()
                }
                .font(.body.weight(.semibold))
                .padding(.top, 6)
            }

            if let error = app.auth.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: app.auth.lastError)
    }

    private func providerButton<Logo: View>(_ provider: AuthProvider, title: String, @ViewBuilder logo: () -> Logo) -> some View {
        let isBusy = app.auth.phase == .signingIn(provider)
        return Button {
            Task {
                await app.auth.signIn(with: provider, using: webAuthenticationSession)
                if app.auth.isSignedIn { onSignedIn() }
            }
        } label: {
            HStack(spacing: 12) {
                if isBusy {
                    ProgressView().tint(colorScheme == .dark ? .black : .white)
                } else {
                    logo()
                }
                Text(title)
                    .font(.system(size: 19, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(colorScheme == .dark ? Color(white: 0.89) : Color(white: 0.12))
            .background(
                Capsule().fill(colorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.08) : Color.white)
            )
            .overlay(
                Capsule().strokeBorder(colorScheme == .dark ? Color(white: 0.56) : Color(white: 0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(title)
    }
}
