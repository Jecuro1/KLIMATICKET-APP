import SwiftUI
import AuthenticationServices
import KlimaCloud

/// "Mit Apple / Google / Microsoft anmelden" buttons following each provider's branding,
/// shared by onboarding and settings. Calls `onSignedIn` after a successful sign-in.
/// Motion (docs/MOTION.md): the buttons dip under the finger, a provider that the server enables later rises in, the
/// logo turns into a spinner while that sign-in runs, and a failure rises in below with one error haptic.
struct AuthButtonStack: View {
    var showsContinueWithoutAccount = false
    var onSignedIn: () -> Void = {}
    var onContinueWithoutAccount: () -> Void = {}

    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private let height: CGFloat = 54

    /// Native Sign in with Apple: signed builds only, and – with a cloud – only when the server accepts it.
    private var showsNativeApple: Bool {
        AppConfig.supportsNativeAppleSignIn && (!app.auth.isCloudAvailable || app.auth.isProviderEnabled(.apple, native: true))
    }

    /// Apple through the Worker's web flow (sideloaded builds cannot carry the Sign in with Apple entitlement).
    private var showsWebApple: Bool {
        !showsNativeApple && app.auth.isCloudAvailable && app.auth.isProviderEnabled(.apple)
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsNativeApple {
                SignInWithAppleButton(.signIn) { request in
                    app.auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    let before = app.auth.profile
                    Task {
                        await app.auth.handleAppleCompletion(result)
                        finishSignIn(since: before)
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: height)
                .clipShape(Capsule())
                .accessibilityLabel("Mit Apple anmelden")
            } else if showsWebApple {
                // Sideloaded builds can't carry the Sign in with Apple entitlement → secure web sign-in through the
                // Cloudflare Worker (ASWebAuthenticationSession, PKCE).
                appleWebButton
            }

            if app.auth.isProviderEnabled(.google) {
                providerButton(.google, title: "Mit Google anmelden") { GoogleLogo(size: 20) }
                    .motionTransition(.rise)
            }
            if app.auth.isProviderEnabled(.microsoft) {
                providerButton(.microsoft, title: "Mit Microsoft anmelden") { MicrosoftLogo(size: 18) }
                    .motionTransition(.rise)
            }

            if app.auth.serverHasNoProviders {
                Text("Die Anmeldung ist auf dem Server noch nicht eingerichtet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .motionTransition(.opacity)
            }

            if showsContinueWithoutAccount {
                Button("Ohne Konto fortfahren") {
                    app.auth.continueWithoutAccount()
                    onContinueWithoutAccount()
                }
                .font(.body.weight(.semibold))
                .buttonStyle(.pressable)
                .padding(.top, 6)
            }

            if let error = app.auth.lastError {
                Label {
                    Text(error)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.negative)
                        .symbolEffect(.wiggle, value: error)
                        .symbolEffectsRemoved(MotionPolicy.isStatic)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .motionTransition(.rise)
            }
        }
        .motionAnimation(Motion.smooth, value: app.auth.lastError)
        .motionAnimation(Motion.smooth, value: app.auth.serverConfig)
        .motionAnimation(Motion.snappy, value: app.auth.phase)
        .haptic(.error, trigger: app.auth.lastError, when: { _, new in new != nil })
        .task { await app.auth.refreshServerConfig() }
    }

    /// Calls `onSignedIn` only when the attempt really signed in. `isSignedIn` alone is no proof: with a local profile
    /// ("Ohne Konto fortfahren") a cancelled or failed attempt ends in `.signedIn` again – Settings would then announce
    /// "Angemeldet" and fold the panel away over the error text, although no account was connected.
    private func finishSignIn(since before: UserProfile?) {
        guard app.auth.isSignedIn, app.auth.lastError == nil, let profile = app.auth.profile, profile != before else { return }
        onSignedIn()
    }

    private var appleWebButton: some View {
        let isBusy = app.auth.phase == .signingIn(.apple)
        return Button {
            guard !isBusy else { return }
            let before = app.auth.profile
            Task {
                await app.auth.signIn(with: .apple, using: webAuthenticationSession)
                finishSignIn(since: before)
            }
        } label: {
            HStack(spacing: 8) {
                logoSlot(isBusy: isBusy, spinnerTint: colorScheme == .dark ? .black : .white) {
                    Image(systemName: "applelogo").font(.system(size: 19, weight: .semibold))
                }
                Text("Mit Apple anmelden").font(.system(size: 19, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .background(Capsule().fill(colorScheme == .dark ? Color.white : Color.black))
            .contentShape(.capsule)
        }
        // Dips under the finger (not dimmed while busy – the spinner says it is working; taps are ignored then).
        .buttonStyle(.pressable(scale: 0.97))
        .accessibilityLabel("Mit Apple anmelden")
        .accessibilityValue(isBusy ? "Anmeldung läuft" : "")
    }

    /// The provider logo, or – while that provider's sign-in runs – a spinner in its place (scaled cross-fade).
    private func logoSlot<Logo: View>(isBusy: Bool, spinnerTint: Color, @ViewBuilder logo: () -> Logo) -> some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .tint(spinnerTint)
                    .motionTransition(.pop)
            } else {
                logo()
                    .motionTransition(.pop)
            }
        }
        .frame(minWidth: 22)
    }

    private func providerButton<Logo: View>(_ provider: AuthProvider, title: String, @ViewBuilder logo: () -> Logo) -> some View {
        let isBusy = app.auth.phase == .signingIn(provider)
        return Button {
            guard !isBusy else { return }
            let before = app.auth.profile
            Task {
                await app.auth.signIn(with: provider, using: webAuthenticationSession)
                finishSignIn(since: before)
            }
        } label: {
            HStack(spacing: 12) {
                // The spinner sits on the button's own surface (white in light mode, near-black in dark mode).
                logoSlot(isBusy: isBusy, spinnerTint: colorScheme == .dark ? Color(white: 0.89) : Color(white: 0.12), logo: logo)
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
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable(scale: 0.97))
        .accessibilityLabel(title)
        .accessibilityValue(isBusy ? "Anmeldung läuft" : "")
    }
}
