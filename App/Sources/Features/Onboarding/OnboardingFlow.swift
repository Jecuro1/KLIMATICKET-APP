import SwiftUI
import SwiftData
import UIKit
import KlimaCore

/// Onboarding: Willkommen → Ticket → Gültigkeit & Preis → Strecke → Erinnerungen → Fertig.
/// A custom paged flow on the alpine sky with a fixed progress trail, back button and primary CTA.
struct OnboardingFlow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        OnbFlowHost(app: app)
    }
}

private struct OnbFlowHost: View {
    @State private var model: OnboardingModel
    @State private var isForward = true
    @State private var isBusy = false
    @State private var welcomeHasAnimated = LaunchMode.isScreenshot
    @State private var finishCount = 0

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(app: AppState) {
        _model = State(initialValue: OnboardingModel(app: app))
    }

    private var step: OnboardingModel.Step { model.step }

    var body: some View {
        NavigationStack {
            ZStack {
                if step == .welcome {
                    // Full-bleed brand page – outside the step chrome so nothing shifts while it leaves.
                    OnbWelcomeStep(model: model, animatesEntrance: !welcomeHasAnimated) {
                        go(to: .ticket)
                    }
                    .onAppear { welcomeHasAnimated = true }
                    .transition(pageTransition)
                } else {
                    stepContainer
                        .transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { skyBackground }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { dismissKeyboard() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: step) { _, _ in app.settings.hapticsEnabled }
        .sensoryFeedback(.success, trigger: finishCount) { _, _ in app.settings.hapticsEnabled }
    }

    // MARK: Pages

    /// Setup steps with the fixed chrome (progress trail + back button on top, primary button at the bottom).
    private var stepContainer: some View {
        ZStack {
            page
                .id(step)
                .transition(pageTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            EmptyView()
        case .ticket:
            OnbTicketStep(model: model)
        case .validity:
            OnbValidityStep(model: model)
        case .habits:
            OnbHabitsStep(model: model)
        case .notifications:
            OnbRemindersStep(model: model)
        case .done:
            OnbDoneStep(model: model)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let dx: CGFloat = isForward ? 56 : -56
        return .asymmetric(insertion: .offset(x: dx).combined(with: .opacity),
                           removal: .offset(x: -dx).combined(with: .opacity))
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.55, bounce: 0.12)
    }

    // MARK: Background

    /// Welcome: deeper "Blaue Stunde" sky in dark mode, bright dawn glow in light mode. Steps: calm standard sky.
    @ViewBuilder
    private var skyBackground: some View {
        ZStack {
            if step == .welcome {
                AmbientBackground(style: colorScheme == .dark ? .onboarding : .standard, glow: 0.95)
                    .transition(.opacity)
            } else {
                AmbientBackground(style: .standard, glow: 0.5)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(isBusy)
            .accessibilityLabel("Zurück")

            OnbProgressTrail(progress: step.progress, accessibilityText: progressText)

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xxs)
        .padding(.bottom, Theme.Spacing.xs)
        .background { topFade }
    }

    private var progressText: String {
        if let n = step.number { return "Schritt \(n) von \(OnboardingModel.Step.numberedCount)" }
        return step == .done ? "Fertig" : "Willkommen"
    }

    private var footer: some View {
        Button(action: primaryAction) {
            HStack(spacing: Theme.Spacing.xs) {
                if isBusy {
                    ProgressView()
                        .tint(Theme.onAccent)
                }
                Text(primaryTitle)
                if !isBusy && step != .done {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                }
            }
            .animation(.snappy(duration: 0.25), value: primaryTitle)
        }
        .buttonStyle(.primary)
        .disabled(!model.canContinue || isBusy)
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xs)
        .background { bottomFade }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome, .ticket, .validity: "Weiter"
        case .habits: model.commuteEstimate == nil ? "Überspringen" : "Weiter"
        case .notifications: model.remindersEnabled ? "Erinnerungen aktivieren" : "Weiter"
        case .done: "Los geht’s"
        }
    }

    /// Progressive blur under the top bar so scrolled content fades out softly.
    private var topFade: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.8), location: 0.55),
                                       .init(color: .black.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private var bottomFade: some View {
        LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0),
                               .init(color: Theme.background.opacity(0.88), location: 0.6)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }

    // MARK: Actions

    private func primaryAction() {
        switch step {
        case .welcome:
            go(to: .ticket)
        case .ticket:
            go(to: .validity)
        case .validity:
            go(to: .habits)
        case .habits:
            go(to: .notifications)
        case .notifications:
            guard model.remindersEnabled else {
                go(to: .done)
                return
            }
            isBusy = true
            Task {
                await app.notifications.requestAuthorization()
                isBusy = false
                // The permission alert can stay up for a while – only advance if the user is still on this step.
                if model.step == .notifications { go(to: .done) }
            }
        case .done:
            isBusy = true
            Task {
                await model.finish(context: context)
                finishCount += 1
                isBusy = false
                app.showToast("checkmark.circle.fill", "Ticket angelegt", model.ticketName)
            }
        }
    }

    private func goBack() {
        if let previous = step.previous { go(to: previous) }
    }

    /// Changes the page. When the direction flips, the transition is updated one frame before the page changes,
    /// so the outgoing page leaves in the right direction.
    private func go(to target: OnboardingModel.Step) {
        guard target != step else { return }
        dismissKeyboard()
        let forward = target.rawValue > step.rawValue
        if forward == isForward {
            withAnimation(pageAnimation) { model.step = target }
        } else {
            isForward = forward
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                withAnimation(pageAnimation) { model.step = target }
            }
        }
    }

    private func dismissKeyboard() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// "Dein Weg zum Gipfel": route-gradient progress with a climber dot and the summit flag at the end.
private struct OnbProgressTrail: View {
    var progress: Double
    var accessibilityText: String

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(geo.size.width - 16, 1)
            let x = trackWidth * CGFloat(min(max(progress, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textTertiary.opacity(0.25))
                    .frame(width: trackWidth, height: 5)
                Capsule()
                    .fill(Theme.routeGradient)
                    .frame(width: trackWidth, height: 5)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(x, 5), height: 5)
                    }
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(Theme.accentSecondary, lineWidth: 3) }
                    .shadow(color: Theme.accentSecondary.opacity(0.45), radius: 4)
                    .offset(x: x - 6)
                FlagShape()
                    .fill(progress >= 1 ? Theme.gold : Theme.summit)
                    .frame(width: 12, height: 17)
                    .offset(x: trackWidth + 3, y: -6)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fortschritt")
        .accessibilityValue(accessibilityText)
    }
}
