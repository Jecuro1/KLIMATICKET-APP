import SwiftUI
import SwiftData
import KlimaCore

/// Step 1 – brand moment: summit scene with floating glass chips, "Hat sich dein Ticket schon rentiert?",
/// sign-in buttons (or "Weiter" when already signed in), "Demo ansehen" and the legal footnote.
struct OnbWelcomeStep: View {
    var model: OnboardingModel
    var animatesEntrance: Bool
    var onContinue: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var appeared: Bool
    @State private var signedInOnAppear: Bool?
    @State private var legalDocument: OnbLegalDocument?
    @State private var isConfirmingDemo = false

    init(model: OnboardingModel, animatesEntrance: Bool, onContinue: @escaping () -> Void) {
        self.model = model
        self.animatesEntrance = animatesEntrance
        self.onContinue = onContinue
        _appeared = State(initialValue: !animatesEntrance)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(flexibleHero: true)
            ScrollView {
                content(flexibleHero: false)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            if signedInOnAppear == nil { signedInOnAppear = app.auth.isSignedIn }
            if !appeared { appeared = true }
        }
        .sheet(item: $legalDocument) { document in
            OnbLegalSheet(document: document)
        }
        .confirmationDialog("Demo ansehen?", isPresented: $isConfirmingDemo, titleVisibility: .visible) {
            Button("Beispieljahr laden") { loadDemo() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("KlimaBilanz wird mit einem realistischen Beispieljahr gefüllt. Du kannst die Daten später in den Einstellungen löschen.")
        }
    }

    // MARK: Layout

    private func content(flexibleHero: Bool) -> some View {
        VStack(spacing: 0) {
            OnbWelcomeHero(animatesEntrance: animatesEntrance, isVisible: appeared) {
                isConfirmingDemo = true
            }
            .frame(minHeight: flexibleHero ? 220 : 290,
                   idealHeight: flexibleHero ? 220 : 290,
                   maxHeight: flexibleHero ? 400 : 290)

            OnbJourneyRail(isVisible: appeared)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xxs)
                .onbEntrance(appeared, delay: 0.2, offset: 8)

            headline
                .padding(.top, Theme.Spacing.l)
                .padding(.horizontal, Theme.Spacing.screen)
                .onbEntrance(appeared, delay: 0.1)

            Text(Self.subline)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xs)
                .padding(.horizontal, Theme.Spacing.screen)
                .onbEntrance(appeared, delay: 0.18)

            authArea
                .padding(.top, Theme.Spacing.l)
                .padding(.horizontal, Theme.Spacing.screen)
                .onbEntrance(appeared, delay: 0.28)

            legal
                .padding(.top, Theme.Spacing.s)
                .padding(.horizontal, Theme.Spacing.xl)
                .onbEntrance(appeared, delay: 0.36)
        }
        .padding(.bottom, Theme.Spacing.xs)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    /// DESIGN.md §5.8 / DESIGN_FINAL_SYNTHESIS §9.1: the Rail-Editorial phrase ("den Tag, ab dem du gratis fährst")
    /// is the visible subtitle under the headline (shorter than `Copy.subline`, so the layout still fits without scrolling).
    static let subline = "Erfasse deine Fahrten – wir zeigen dir den Tag, ab dem du gratis fährst."

    /// "Hat sich dein Ticket" / "schon rentiert?" – second line in the route gradient.
    /// One Text, so both lines share the same scale when space is tight.
    private var headline: some View {
        let lines = Self.splitTagline(Copy.tagline)
        let first = Text(lines.first).foregroundStyle(Theme.textPrimary)
        let title: Text
        if let second = lines.second {
            title = Text("\(first)\n\(Text(second).foregroundStyle(Theme.routeGradient))")
        } else {
            title = first
        }
        return title
            .font(Theme.Typography.heroTitle)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(.center)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityLabel(Copy.tagline)
            .accessibilityAddTraits(.isHeader)
    }

    static func splitTagline(_ tagline: String) -> (first: String, second: String?) {
        guard let range = tagline.range(of: " schon ") else { return (tagline, nil) }
        return (String(tagline[..<range.lowerBound]), String(tagline[tagline.index(after: range.lowerBound)...]))
    }

    @ViewBuilder
    private var authArea: some View {
        if signedInOnAppear ?? app.auth.isSignedIn {
            VStack(spacing: Theme.Spacing.s) {
                Button(action: onContinue) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Weiter")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.primary)
                if let profile = app.auth.profile, profile.provider != .local {
                    Label("Angemeldet als \(profile.displayName)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else {
            AuthButtonStack(showsContinueWithoutAccount: true,
                            onSignedIn: {
                                model.didSignIn()
                                onContinue()
                            },
                            onContinueWithoutAccount: onContinue)
        }
    }

    private var legal: some View {
        Text("Mit der Anmeldung akzeptierst du die [Nutzungsbedingungen](klimabilanz-legal://terms) und die [Datenschutzerklärung](klimabilanz-legal://privacy).")
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .tint(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                legalDocument = url.host() == "privacy" ? .privacy : .terms
                return .handled
            })
    }

    private func loadDemo() {
        model.loadDemo(context: context)
        app.showToast("sparkles", "Demo geladen", "Ein Beispieljahr zum Ausprobieren")
    }
}

// MARK: - Hero scene

/// Brand mark above an alpine scene: ridges with the route climbing to the summit flag (demo: 73 %)
/// and three floating glass chips. Scene geometry is in unit coordinates of the area below the brand,
/// so the composition holds from iPhone SE to Pro Max.
private struct OnbWelcomeHero: View {
    var animatesEntrance: Bool
    var isVisible: Bool
    var onDemo: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var reveal: CGFloat

    init(animatesEntrance: Bool, isVisible: Bool, onDemo: @escaping () -> Void) {
        self.animatesEntrance = animatesEntrance
        self.isVisible = isVisible
        self.onDemo = onDemo
        _reveal = State(initialValue: animatesEntrance ? 0 : 1)
    }

    private static let summit = CGPoint(x: 0.70, y: 0.13)
    private static let climber = CGPoint(x: 0.56, y: 0.53)
    private static let route: [CGPoint] = [
        CGPoint(x: -0.02, y: 0.99), CGPoint(x: 0.06, y: 0.93), CGPoint(x: 0.13, y: 0.96), CGPoint(x: 0.21, y: 0.84),
        CGPoint(x: 0.28, y: 0.87), CGPoint(x: 0.36, y: 0.74), CGPoint(x: 0.43, y: 0.77), CGPoint(x: 0.50, y: 0.61),
        CGPoint(x: 0.56, y: 0.53),
    ]
    private static let ahead: [CGPoint] = [CGPoint(x: 0.56, y: 0.53), CGPoint(x: 0.635, y: 0.44), CGPoint(x: 0.70, y: 0.13)]

    private var isAnimated: Bool { !reduceMotion && !LaunchMode.isScreenshot }

    private var breakEvenText: String {
        Format.dayMonth(Calendar.vienna.date(byAdding: .day, value: 66, to: Date()) ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            brand
            GeometryReader { geo in
                scene(geo.size)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Beispiel: Ticket zu 73 Prozent amortisiert, Break-even am \(breakEvenText), 612 Kilogramm CO₂ gespart")
        }
        .overlay(alignment: .topTrailing) { demoButton }
        .onAppear {
            guard reveal < 1 else { return }
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.easeOut(duration: 1.0).delay(0.1)) { reveal = 1 }
            }
        }
    }

    private func scene(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            glow(size)
            ridges
            routeLayer
            summitMarker
                .onbEntrance(isVisible, delay: 0.4, offset: 6, scale: 0.6)
                .position(x: size.width * Self.summit.x + 8, y: size.height * Self.summit.y - 12)
            climberMarker
                .onbEntrance(isVisible, delay: 0.5, offset: 0, scale: 0.4)
                .position(x: size.width * Self.climber.x, y: size.height * Self.climber.y)
            chips(size)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Layers

    private func glow(_ size: CGSize) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.dawn.opacity(colorScheme == .dark ? 0.34 : 0.42), Theme.dawn.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size.width * 0.34))
            .frame(width: size.width * 0.68, height: size.width * 0.68)
            .position(x: size.width * Self.summit.x, y: size.height * Self.summit.y + 24)
            .blur(radius: 14)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.9), value: isVisible)
    }

    private var ridges: some View {
        let dark = colorScheme == .dark
        let front = RidgeShape(peakX: Self.summit.x, peakY: Self.summit.y, seed: 7, roughness: 0.42)
        let frontFill: [Gradient.Stop] = dark
            ? [.init(color: Color.white.opacity(0.20), location: 0), .init(color: Color.white.opacity(0.04), location: 0.6),
               .init(color: Color.white.opacity(0), location: 1)]
            : [.init(color: Color.white.opacity(0.88), location: 0), .init(color: Color.white.opacity(0.26), location: 0.6),
               .init(color: Color.white.opacity(0), location: 1)]
        return ZStack {
            RidgeShape(peakX: 0.90, peakY: 0.22, seed: 3, roughness: 0.7)
                .fill(Theme.glacier.opacity(dark ? 0.13 : 0.16))
            RidgeShape(peakX: 0.30, peakY: 0.36, seed: 19, roughness: 0.6)
                .fill(Theme.dusk.opacity(dark ? 0.20 : 0.14))
            if !reduceTransparency {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .clipShape(front)
            }
            front.fill(LinearGradient(stops: frontFill, startPoint: .top, endPoint: .bottom))
            front.stroke(LinearGradient(colors: dark ? [Color.white.opacity(0.18), Theme.dawn.opacity(0.85)]
                                                     : [Color.white.opacity(0.7), Color.white],
                                        startPoint: .leading, endPoint: .trailing),
                         lineWidth: 1.3)
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                   .init(color: .black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var routeLayer: some View {
        ZStack {
            OnbPolygon(points: Self.route, closed: false)
                .trim(from: 0, to: reveal)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .blur(radius: 9)
                .opacity(0.55)
            OnbPolygon(points: Self.route, closed: false)
                .trim(from: 0, to: reveal)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            OnbPolygon(points: Self.ahead, closed: false)
                .trim(from: 0, to: reveal)
                .stroke(Theme.textSecondary.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
        }
    }

    /// Flag on the summit; the dot's centre sits at local (6, 30) of the 28 × 36 frame.
    private var summitMarker: some View {
        ZStack(alignment: .topLeading) {
            FlagShape()
                .fill(LinearGradient(colors: [Theme.dawn, Theme.alpenglow], startPoint: .top, endPoint: .bottom))
                .frame(width: 22, height: 30)
                .offset(x: 4.75)
            Circle()
                .fill(Theme.summit)
                .frame(width: 12, height: 12)
                .overlay { Circle().stroke(Color.white, lineWidth: 2) }
                .offset(y: 24)
        }
        .frame(width: 28, height: 36, alignment: .topLeading)
    }

    private var climberMarker: some View {
        ZStack {
            if isAnimated {
                Circle()
                    .fill(Theme.dusk.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .phaseAnimator([false, true]) { halo, expanded in
                        halo
                            .scaleEffect(expanded ? 1.45 : 0.7)
                            .opacity(expanded ? 0 : 0.9)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 2.4) : .linear(duration: 0.05)
                    }
            } else {
                Circle()
                    .fill(Theme.dusk.opacity(0.28))
                    .frame(width: 34, height: 34)
            }
            Circle()
                .fill(Color.white)
                .frame(width: 15, height: 15)
                .overlay { Circle().stroke(Theme.dusk, lineWidth: 4) }
                .shadow(color: Theme.dusk.opacity(0.5), radius: 6)
        }
        .frame(width: 40, height: 40)
    }

    private func chips(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            OnbStatChip(symbol: "flag.fill", tint: Theme.dawn, label: "Break-even", value: breakEvenText)
                .modifier(OnbFloating(amplitude: 4, duration: 2.6, isActive: isAnimated))
                .onbEntrance(isVisible, delay: 0.3, offset: 10, scale: 0.85)
                .offset(x: size.width * 0.11, y: 4)
            OnbStatChip(symbol: "leaf.fill", tint: Theme.pine, label: "CO₂ gespart", value: Format.kg(612))
                .modifier(OnbFloating(amplitude: 4, duration: 3.1, isActive: isAnimated))
                .onbEntrance(isVisible, delay: 0.4, offset: 10, scale: 0.85)
                .offset(x: 14, y: size.height * 0.42)
            OnbStatChip(symbol: "train.side.front.car", tint: Theme.glacier, label: "Amortisiert", value: Format.percent(0.73))
                .modifier(OnbFloating(amplitude: 4, duration: 3.5, isActive: isAnimated))
                .onbEntrance(isVisible, delay: 0.5, offset: 10, scale: 0.85)
                .frame(width: max(size.width - 14, 0), alignment: .trailing)
                .offset(y: size.height * 0.63)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Overlays

    private var brand: some View {
        VStack(spacing: 6) {
            OnbBrandMark(size: 56)
            Text("KlimaBilanz")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onbEntrance(isVisible, delay: 0, offset: 8, scale: 0.92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("KlimaBilanz")
        .accessibilityAddTraits(.isHeader)
    }

    private var demoButton: some View {
        Button(action: onDemo) {
            Label("Demo ansehen", systemImage: "play.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.top, 6)
        .padding(.trailing, Theme.Spacing.cardGutter)
        .onbEntrance(isVisible, delay: 0.45, offset: 0)
        .accessibilityHint("Lädt ein Beispieljahr zum Ausprobieren")
    }
}

/// Floating glass chip with a coloured icon tile ("Break-even · 14. Dez.").
private struct OnbStatChip: View {
    var symbol: String
    var tint: Color
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .fixedSize()
        }
        .padding(.leading, 7)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Journey rail ("TICKET GEKAUFT → GRATIS FAHREN", from Rail Editorial)

private struct OnbJourneyRail: View {
    var isVisible: Bool
    var progress: CGFloat = 0.73

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                let lineWidth = max(geo.size.width - 8, 1)
                let x = (isVisible ? progress : 0) * lineWidth
                ZStack(alignment: .leading) {
                    OnbHorizontalLine()
                        .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                        .frame(width: lineWidth, height: 2)
                    Capsule()
                        .fill(Theme.routeGradient)
                        .frame(width: lineWidth, height: 4)
                        .mask(alignment: .leading) {
                            Capsule().frame(width: max(x, 4), height: 4)
                        }
                    Circle()
                        .strokeBorder(Theme.glacier, lineWidth: 2.5)
                        .frame(width: 12, height: 12)
                    trainBadge
                        .offset(x: x - 17)
                    FlagShape()
                        .fill(Theme.summit)
                        .frame(width: 13, height: 18)
                        .offset(x: lineWidth - 1, y: -8)
                }
                .frame(height: geo.size.height)
            }
            .frame(height: 24)

            HStack {
                Kicker(text: "Ticket gekauft")
                Spacer(minLength: Theme.Spacing.xs)
                Kicker(text: "Gratis fahren", color: Theme.summitText)
            }
        }
        .animation(.easeInOut(duration: 1.0).delay(0.15), value: isVisible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vom Ticketkauf bis zum Tag, ab dem du gratis fährst")
    }

    private var trainBadge: some View {
        Image(systemName: "train.side.front.car")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 34, height: 20)
            .background(Theme.dusk.mix(with: .black, by: 0.12), in: .capsule)
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1) }
            .shadow(color: Theme.dusk.opacity(0.5), radius: 6, y: 2)
    }
}

// MARK: - Legal

private enum OnbLegalDocument: String, Identifiable {
    case terms, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Nutzungsbedingungen"
        case .privacy: "Datenschutz"
        }
    }

    var text: String {
        switch self {
        case .terms: Copy.disclaimer
        case .privacy: Copy.privacy
        }
    }
}

private struct OnbLegalSheet: View {
    var document: OnbLegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.l)
            }
            .background(Theme.sheetBackground)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
