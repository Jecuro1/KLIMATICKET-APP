import SwiftUI
import SwiftData
import KlimaCore

/// Step 1 – brand moment: summit scene with floating glass chips, "Hat sich dein Ticket schon rentiert?",
/// page dots, sign-in buttons (or "Weiter" when already signed in), "Ohne Konto fortfahren · Demo ansehen" and the legal footnote.
struct OnbWelcomeStep: View {
    var model: OnboardingModel
    var animatesEntrance: Bool
    var onContinue: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared: Bool
    @State private var signedInOnAppear: Bool?
    @State private var legalDocument: OnbLegalDocument?
    @State private var isConfirmingDemo = false
    /// Figures of the sample year behind "Demo ansehen" – the scene shows exactly what the demo will show.
    private let figures: OnbDemoFigures

    init(model: OnboardingModel, animatesEntrance: Bool, onContinue: @escaping () -> Void) {
        self.model = model
        self.animatesEntrance = animatesEntrance
        self.onContinue = onContinue
        self.figures = OnbDemoFigures.current(catalog: model.app.catalog)
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
            OnbWelcomeHero(figures: figures, animatesEntrance: animatesEntrance, isVisible: appeared)
                .frame(minHeight: flexibleHero ? 236 : 300,
                       idealHeight: flexibleHero ? 236 : 300,
                       maxHeight: flexibleHero ? 420 : 300)

            headline
                .padding(.top, Theme.Spacing.m)
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

            OnbPageDots(count: OnboardingModel.Step.numberedCount + 1, current: 0)
                .padding(.top, Theme.Spacing.m)
                .onbEntrance(appeared, delay: 0.24, offset: 0)

            authArea
                .padding(.top, Theme.Spacing.l)
                .padding(.horizontal, Theme.Spacing.screen)
                .onbEntrance(appeared, delay: 0.28)

            legal
                .padding(.top, Theme.Spacing.xxs)
                .padding(.horizontal, Theme.Spacing.xl)
                .onbEntrance(appeared, delay: 0.36)
        }
        .padding(.bottom, Theme.Spacing.xs)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    /// DESIGN.md §5.8 / DESIGN_FINAL_SYNTHESIS §9.1: the Rail-Editorial phrase ("den Tag, ab dem du gratis fährst")
    /// is the visible subtitle under the headline – it replaces the separate "Ticket gekauft → Gratis fahren" rail.
    static let subline = "Erfasse deine Fahrten – wir zeigen dir den Tag, ab dem du gratis fährst."

    /// "Hat sich dein Ticket" / "schon rentiert?" – second line in a gradient.
    /// One Text, so both lines share the same scale when space is tight.
    private var headline: some View {
        let lines = Self.splitTagline(Copy.tagline)
        let first = Text(lines.first).foregroundStyle(Theme.textPrimary)
        let title: Text
        if let second = lines.second {
            title = Text("\(first)\n\(Text(second).foregroundStyle(headlineGradient))")
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

    /// Light: the text-safe `verdictAmount` gradient (≥ 4.5 : 1 on the dawn sky – the route gradient's dawn end is only 2.6 : 1).
    /// Dark: the luminous headline gradient of DESIGN_FINAL_SYNTHESIS §9.1.
    private var headlineGradient: LinearGradient {
        let colors = colorScheme == .dark
            ? [Color(hex: "#8CCBFF"), Color(hex: "#B9A8FF"), Color(hex: "#FFB896")]
            : [Color(hex: "#1F66B8"), Color(hex: "#5A4FC4")]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
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
                demoButton
            }
        } else {
            VStack(spacing: Theme.Spacing.xs) {
                AuthButtonStack(showsContinueWithoutAccount: false,
                                onSignedIn: {
                                    model.didSignIn()
                                    onContinue()
                                })
                secondaryActions
            }
        }
    }

    /// "Ohne Konto fortfahren · Demo ansehen" – one quiet tertiary row; stacked when the text is too large for one line.
    private var secondaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) {
                continueWithoutAccountButton
                Capsule()
                    .fill(Theme.textTertiary.opacity(0.6))
                    .frame(width: 1, height: 16)
                    .accessibilityHidden(true)
                demoButton
            }
            VStack(spacing: 0) {
                continueWithoutAccountButton
                demoButton
            }
        }
    }

    private var continueWithoutAccountButton: some View {
        Button {
            app.auth.continueWithoutAccount()
            onContinue()
        } label: {
            Text("Ohne Konto fortfahren")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(OnbPressableStyle())
    }

    private var demoButton: some View {
        Button {
            isConfirmingDemo = true
        } label: {
            Label {
                Text("Demo ansehen")
            } icon: {
                Image(systemName: "play.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(OnbPressableStyle())
        .accessibilityHint("Lädt ein Beispieljahr zum Ausprobieren")
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

// MARK: - Demo figures

/// Amortisation, break-even forecast and CO₂ of the `DemoData` sample year, computed with the same `Analytics` as the
/// dashboard – so the welcome scene reads exactly what "Demo ansehen" opens (e.g. 75 % · 21. Dez. · 661 kg).
/// Seeded once per launch into a private in-memory store; never touches the user's data.
struct OnbDemoFigures {
    var amortized: Double
    var breakEven: Date?
    var co2Kg: Double

    @MainActor private static var cached: OnbDemoFigures?

    @MainActor
    static func current(catalog: TariffCatalog) -> OnbDemoFigures {
        if let cached { return cached }
        let figures = compute(catalog: catalog)
        cached = figures
        return figures
    }

    @MainActor
    private static func compute(catalog: TariffCatalog) -> OnbDemoFigures {
        let fallback = OnbDemoFigures(amortized: 0.75,
                                      breakEven: Calendar.vienna.date(byAdding: .day, value: 73, to: Date()),
                                      co2Kg: 661)
        let schema = Schema(DataSchema.models)
        let configuration = ModelConfiguration("OnbDemoFigures", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else { return fallback }
        let context = ModelContext(container)
        DemoData.seed(into: context)
        guard let ticket = (try? context.fetch(FetchDescriptor<TicketEntity>()))?.first,
              let trips = try? context.fetch(FetchDescriptor<TripEntity>()), !trips.isEmpty else { return fallback }
        let summary = Analytics.make(ticket: ticket, trips: trips, catalog: catalog).summary
        return OnbDemoFigures(amortized: summary.amortizedFraction,
                              breakEven: summary.isPaidOff ? summary.paidOffDate : summary.forecastBreakEvenDate,
                              co2Kg: summary.co2SavedKg)
    }

    var percentText: String { Format.percent(amortized) }
    var breakEvenText: String { breakEven.map(Format.dayMonth) ?? "–" }
    var co2Text: String { Format.kg(co2Kg) }
}

// MARK: - Page dots

/// Pager dots under the subtitle (welcome + the numbered setup steps); the current page is a wide capsule.
private struct OnbPageDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Theme.textPrimary.opacity(0.85)) : AnyShapeStyle(Theme.textTertiary.opacity(0.55)))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(current + 1) von \(count)")
    }
}

// MARK: - Hero scene

/// Brand mark above an alpine scene: ridges with the route climbing to the summit flag and three floating glass chips.
/// The climber sits at the demo's amortisation along the route (arc length), with milestone dots at 25 % and 50 %.
/// Scene geometry is in unit coordinates of the area below the brand, so the composition holds from iPhone SE to Pro Max.
private struct OnbWelcomeHero: View {
    var figures: OnbDemoFigures
    var animatesEntrance: Bool
    var isVisible: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var reveal: CGFloat

    init(figures: OnbDemoFigures, animatesEntrance: Bool, isVisible: Bool) {
        self.figures = figures
        self.animatesEntrance = animatesEntrance
        self.isVisible = isVisible
        _reveal = State(initialValue: animatesEntrance ? 0 : 1)
    }

    private static let summit = CGPoint(x: 0.70, y: 0.13)
    /// The whole way from the valley (ticket bought) to the summit flag (break-even).
    private static let path: [CGPoint] = [
        CGPoint(x: -0.02, y: 0.99), CGPoint(x: 0.06, y: 0.93), CGPoint(x: 0.13, y: 0.96), CGPoint(x: 0.21, y: 0.84),
        CGPoint(x: 0.28, y: 0.87), CGPoint(x: 0.36, y: 0.74), CGPoint(x: 0.43, y: 0.77), CGPoint(x: 0.50, y: 0.61),
        CGPoint(x: 0.56, y: 0.53), CGPoint(x: 0.635, y: 0.44), summit,
    ]
    private static let milestones: [CGFloat] = [0.25, 0.5]

    private var isAnimated: Bool { !reduceMotion && !LaunchMode.isScreenshot }
    private var progress: CGFloat { CGFloat(min(max(figures.amortized, 0.04), 1)) }

    var body: some View {
        VStack(spacing: 0) {
            brand
            GeometryReader { geo in
                scene(geo.size)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Beispiel: Ticket zu \(figures.percentText) amortisiert, Break-even am \(figures.breakEvenText), \(Int(figures.co2Kg.rounded())) Kilogramm CO₂ gespart")
        }
        .onAppear {
            guard reveal < 1 else { return }
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.easeOut(duration: 1.2).delay(0.1)) { reveal = 1 }
            }
        }
    }

    private func scene(_ size: CGSize) -> some View {
        let split = Self.split(Self.path, at: progress, in: size)
        return ZStack(alignment: .topLeading) {
            glow(size)
            ridges
            routeLayer(walked: split.walked, ahead: split.ahead)
            ForEach(Self.milestones.filter { $0 < progress - 0.08 }, id: \.self) { fraction in
                let point = Self.split(Self.path, at: fraction, in: size).point
                milestoneDot
                    .onbEntrance(isVisible, delay: 0.35 + Double(fraction), offset: 0, scale: 0.4)
                    .position(x: size.width * point.x, y: size.height * point.y)
            }
            summitMarker
                .onbEntrance(isVisible, delay: 0.4, offset: 6, scale: 0.6)
                .position(x: size.width * Self.summit.x + 8, y: size.height * Self.summit.y - 12)
            if progress < 1 {
                climberMarker
                    .onbEntrance(isVisible, delay: 0.85, offset: 0, scale: 0.4)
                    .position(x: size.width * split.point.x, y: size.height * split.point.y)
            }
            chips(size)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Splits a polyline (unit coordinates) at `fraction` of its on-screen length.
    static func split(_ points: [CGPoint], at fraction: CGFloat, in size: CGSize) -> (walked: [CGPoint], ahead: [CGPoint], point: CGPoint) {
        guard points.count > 1 else { return (points, points, points.first ?? .zero) }
        let lengths = zip(points, points.dropFirst()).map { a, b in
            hypot((b.x - a.x) * size.width, (b.y - a.y) * size.height)
        }
        var remaining = min(max(fraction, 0), 1) * lengths.reduce(0, +)
        for (index, length) in lengths.enumerated() {
            if remaining <= length || index == lengths.count - 1 {
                let t = length > 0 ? min(remaining / length, 1) : 0
                let a = points[index], b = points[index + 1]
                let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                return (Array(points[...index]) + [point], [point] + Array(points[(index + 1)...]), point)
            }
            remaining -= length
        }
        return (points, [], points[points.count - 1])
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

    private func routeLayer(walked: [CGPoint], ahead: [CGPoint]) -> some View {
        ZStack {
            OnbPolygon(points: walked, closed: false)
                .trim(from: 0, to: reveal)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .blur(radius: 9)
                .opacity(0.55)
            OnbPolygon(points: walked, closed: false)
                .trim(from: 0, to: reveal)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            OnbPolygon(points: ahead, closed: false)
                .trim(from: 0, to: reveal)
                .stroke(Theme.textSecondary.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
        }
    }

    /// Milestone hut on the walked route (25 % / 50 %).
    private var milestoneDot: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 7, height: 7)
            .shadow(color: Theme.dusk.opacity(0.45), radius: 3)
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

    /// Chip order and tiles as in mock 05 / DESIGN_FINAL_SYNTHESIS §9.1: Break-even (flag), Amortisiert (percent), CO₂ (leaf).
    private func chips(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            OnbStatChip(symbol: "flag.fill", tile: [Color(hex: "#FF9E7A"), Color(hex: "#D9573A")],
                        label: "Break-even", value: figures.breakEvenText)
                .modifier(OnbFloating(amplitude: 4, duration: 2.6, isActive: isAnimated))
                .onbEntrance(isVisible, delay: 0.3, offset: 10, scale: 0.85)
                .offset(x: size.width * 0.11, y: 4)
            OnbStatChip(symbol: "percent", tile: [Color(hex: "#6CB6FF"), Color(hex: "#5B5FD6")],
                        label: "Amortisiert", value: figures.percentText)
                .modifier(OnbFloating(amplitude: 4, duration: 3.1, isActive: isAnimated))
                .onbEntrance(isVisible, delay: 0.4, offset: 10, scale: 0.85)
                .offset(x: 14, y: size.height * 0.40)
            OnbStatChip(symbol: "leaf.fill", tile: [Color(hex: "#5FD3A2"), Color(hex: "#1E7F62")],
                        label: "CO₂ gespart", value: figures.co2Text)
                .modifier(OnbFloating(amplitude: 4, duration: 3.5, isActive: isAnimated))
                .onbEntrance(isVisible, delay: 0.5, offset: 10, scale: 0.85)
                .frame(width: max(size.width - 14, 0), alignment: .trailing)
                .offset(y: size.height * 0.63)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Brand

    private var brand: some View {
        VStack(spacing: 6) {
            OnbBrandMark(size: 60)
            Text("KlimaBilanz")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .onbEntrance(isVisible, delay: 0, offset: 8, scale: 0.92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("KlimaBilanz")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Floating glass chip with a gradient icon tile ("Break-even · 21. Dez.").
private struct OnbStatChip: View {
    var symbol: String
    var tile: [Color]
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: tile, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .rect(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
                }
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
