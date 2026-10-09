import SwiftUI
import SwiftData
import UIKit
import KlimaCore

/// Onboarding: Willkommen → Ticket → Gültigkeit & Preis → Strecke → Erinnerungen → Fertig.
/// A custom paged flow on the alpine sky with a fixed progress trail, back button and primary CTA.
///
/// Motion (docs/MOTION.md): pages slide in the direction of travel on `Motion.smooth`; each page's entrance plays on its
/// first visit only (`onbReveal`); the climber on the trail walks to the next waypoint and the flag waves at the end;
/// the CTA's arrow nudges forward the moment a step can be continued. One light tap per page change.
struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    /// CI screenshots of the later steps (`onboardingTicket` … `onboardingDone`): the flow opens on that step.
    var screenshotStep: OnboardingModel.Step? = nil

    var body: some View {
        OnbFlowHost(app: app, screenshotStep: screenshotStep)
    }

    /// The step a CI screenshot route opens (`-KBScreenshot onboardingHabits`), nil for any other screen.
    static func screenshotStep(for screen: String) -> OnboardingModel.Step? {
        switch screen {
        case "onboardingTicket": .ticket
        case "onboardingValidity": .validity
        case "onboardingHabits": .habits
        case "onboardingReminders": .notifications
        case "onboardingDone": .done
        default: nil
        }
    }
}

private struct OnbFlowHost: View {
    @State private var model: OnboardingModel
    @State private var isForward = true
    @State private var isBusy = false
    /// Pages shown so far, and whether the page on screen is new (its entrance plays) or one the user went back to.
    @State private var visitedSteps: Set<OnboardingModel.Step> = []
    @State private var isFirstVisit = true
    /// A step's own sheet is up (legal text, station search): sky and continuous effects underneath pause.
    @State private var isCoveredBySheet = false
    /// Counts the moments a step becomes ready to continue – the CTA's arrow nudges forward each time.
    @State private var readyNudge = 0

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ambientSkyPaused) private var isCoveredByAppSheet

    init(app: AppState, screenshotStep: OnboardingModel.Step? = nil) {
        let model = OnboardingModel(app: app)
        if let screenshotStep {
            model.step = screenshotStep
            // "Deine Strecke" with the demo commute, so the preview (and the done page's favourite) are on screen.
            model.homeStation = app.stations.station(named: "St. Anton am Arlberg")
            model.commuteDestination = app.stations.station(named: "Innsbruck Hbf")
            model.holderName = "Lena Hofer"
        }
        _model = State(initialValue: model)
        _visitedSteps = State(initialValue: [model.step])
    }

    private var step: OnboardingModel.Step { model.step }

    var body: some View {
        NavigationStack {
            ZStack {
                if step == .welcome {
                    // Full-bleed brand page – outside the step chrome so nothing shifts while it leaves.
                    OnbWelcomeStep(model: model, animatesEntrance: isFirstVisit && !MotionPolicy.isStatic) {
                        go(to: .ticket)
                    }
                    .transition(pageTransition)
                } else {
                    stepContainer
                        .transition(pageTransition)
                }
            }
            .environment(\.onbFirstVisit, isFirstVisit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { skyBackground }
            .environment(\.ambientSkyPaused, isCoveredByAppSheet || isCoveredBySheet)
            .onPreferenceChange(OnbCoveredKey.self) { covered in
                isCoveredBySheet = covered
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { dismissKeyboard() }
                        .fontWeight(.semibold)
                }
            }
        }
        // One light tap per page; finishing is confirmed by the "Ticket angelegt" toast and its own haptic.
        .haptic(.tap, trigger: step)
        .onChange(of: model.canContinue) { wasReady, isReady in
            if !wasReady && isReady { readyNudge += 1 }
        }
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

    /// nil in screenshots (end state at once), a cross-fade under Reduce Motion.
    private var pageAnimation: Animation? {
        MotionPolicy.animation(Motion.smooth)
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
                .motionAnimation(Motion.smooth, value: step)

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
                        .motionTransition(.pop)
                }
                Text(primaryTitle)
                    .contentTransition(.interpolate)
                if !isBusy && step != .done {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                        .symbolEffect(.wiggle.forward, value: readyNudge)
                        .symbolEffectsRemoved(reduceMotion || MotionPolicy.isStatic)
                        .motionTransition(.pop)
                }
            }
            .motionAnimation(Motion.snappy, value: primaryTitle)
            .motionAnimation(Motion.snappy, value: isBusy)
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
        isFirstVisit = !visitedSteps.contains(target)
        visitedSteps.insert(target)
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

/// "Dein Weg zum Gipfel": route-gradient progress with a climber dot, a waypoint per setup step and the summit flag at
/// the end. The climber walks to the next waypoint (render transforms: the fill is a scaled capsule, the dot an offset),
/// passed waypoints light up, and the flag turns gold and waves once when the setup is done.
private struct OnbProgressTrail: View {
    var progress: Double
    var accessibilityText: String

    /// Waypoints of the numbered steps (Ticket, Gültigkeit, Strecke, Erinnerungen).
    private static let waypoints: [Double] = (1...OnboardingModel.Step.numberedCount).map {
        Double($0) / Double(OnboardingModel.Step.allCases.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(geo.size.width - 16, 1)
            let fraction = CGFloat(min(max(progress, 0), 1))
            let x = trackWidth * fraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textTertiary.opacity(0.25))
                    .frame(width: trackWidth, height: 5)
                Capsule()
                    .fill(Theme.routeGradient)
                    .frame(width: trackWidth, height: 5)
                    .mask(alignment: .leading) {
                        Capsule()
                            .frame(width: trackWidth, height: 5)
                            .scaleEffect(x: max(fraction, 5 / trackWidth), anchor: .leading)
                    }
                ForEach(Self.waypoints, id: \.self) { point in
                    let isPassed = progress >= point - 0.001
                    Circle()
                        .fill(isPassed ? Color.white : Theme.textTertiary.opacity(0.45))
                        .frame(width: 5, height: 5)
                        .scaleEffect(isPassed ? 1 : 0.8)
                        .offset(x: trackWidth * CGFloat(point) - 2.5)
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(Theme.accentSecondary, lineWidth: 3) }
                    .shadow(color: Theme.accentSecondary.opacity(0.45), radius: 4)
                    // At the summit the gold flag takes over – the climber steps aside instead of covering its foot.
                    .scaleEffect(progress >= 1 ? 0.4 : 1)
                    .opacity(progress >= 1 ? 0 : 1)
                    .offset(x: x - 6)
                FlagShape()
                    .fill(progress >= 1 ? Theme.gold : Theme.summit)
                    .frame(width: 12, height: 17)
                    .celebrate(trigger: progress >= 1, haptic: nil)
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
