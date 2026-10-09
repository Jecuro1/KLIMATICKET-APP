import SwiftUI
import SwiftData
import KlimaCore

/// Step 1 – brand moment: summit scene with glass chips, "Hat sich dein Ticket schon rentiert?", page dots, sign-in
/// buttons (or "Weiter" when already signed in with an account), "Ohne Konto fortfahren · Demo ansehen" and the legal
/// footnote.
///
/// Motion (docs/MOTION.md): the page waits one beat on the plain sky while the sample year's figures are worked out, then
/// enters in reading order – brand mark, scene, headline, buttons. In the scene the climber walks the route up to the
/// demo's amortisation while "Amortisiert" counts with it; when it arrives, the break-even chip – the "aha" – pops in
/// and the climber's halo starts to pulse. The layers shift with the phone's tilt (parallax). First visit only;
/// Reduce Motion: fades, no parallax, no halo.
struct OnbWelcomeStep: View {
    var model: OnboardingModel
    var animatesEntrance: Bool
    var onContinue: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    /// Figures of the sample year behind "Demo ansehen" – the scene shows exactly what the demo will show. Seeding the
    /// in-memory store takes a moment on the main thread, so it runs after the first frame and before any entrance
    /// animation starts (nothing stutters); later visits and screenshots have them at once.
    @State private var figures: OnbDemoFigures?
    /// Decided once: an account (Apple, Google, Microsoft) shows "Weiter"; a local profile ("Ohne Konto fortfahren"
    /// earlier) still gets the sign-in buttons when the user comes back to this page.
    @State private var hasAccountOnAppear: Bool?
    @State private var legalDocument: OnbLegalDocument?
    @State private var isConfirmingDemo = false

    init(model: OnboardingModel, animatesEntrance: Bool, onContinue: @escaping () -> Void) {
        self.model = model
        self.animatesEntrance = animatesEntrance
        self.onContinue = onContinue
        _figures = State(initialValue: LaunchMode.isScreenshot ? OnbDemoFigures.current(catalog: model.app.catalog)
                                                               : OnbDemoFigures.cachedFigures)
    }

    private var hasAccount: Bool {
        guard app.auth.isSignedIn, let profile = app.auth.profile else { return false }
        return profile.provider != .local
    }

    var body: some View {
        Group {
            if let figures {
                ViewThatFits(in: .vertical) {
                    content(figures: figures, flexibleHero: true)
                    ScrollView {
                        content(figures: figures, flexibleHero: false)
                    }
                    .scrollIndicators(.hidden)
                }
                // The entrance starts when the content does (not when the empty sky appeared).
                .revealScope()
            } else {
                Color.clear
            }
        }
        .task {
            guard figures == nil else { return }
            try? await Task.sleep(for: .milliseconds(60))   // let the sky's first frame reach the screen
            figures = OnbDemoFigures.current(catalog: model.app.catalog)
        }
        .onAppear {
            if hasAccountOnAppear == nil { hasAccountOnAppear = hasAccount }
        }
        .preference(key: OnbCoveredKey.self, value: legalDocument != nil)
        .sheet(item: $legalDocument) { document in
            OnbLegalSheet(document: document)
        }
        .confirmationDialog("Demo ansehen?", isPresented: $isConfirmingDemo, titleVisibility: .visible) {
            Button("Beispieljahr laden") { loadDemo() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("KlimaBilanz wird mit einem realistischen Beispieljahr gefüllt. Unter Einstellungen › Daten entfernst du es jederzeit wieder.")
        }
    }

    // MARK: Layout

    private func content(figures: OnbDemoFigures, flexibleHero: Bool) -> some View {
        VStack(spacing: 0) {
            OnbWelcomeHero(figures: figures, animatesEntrance: animatesEntrance, isCovered: legalDocument != nil)
                .frame(minHeight: flexibleHero ? 236 : 300,
                       idealHeight: flexibleHero ? 236 : 300,
                       maxHeight: flexibleHero ? 420 : 300)

            headline
                .padding(.top, Theme.Spacing.m)
                .padding(.horizontal, Theme.Spacing.screen)
                .onbReveal(.focus, order: 2)

            Text(Self.subline)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xs)
                .padding(.horizontal, Theme.Spacing.screen)
                .onbReveal(order: 3)

            OnbPageDots(count: OnboardingModel.Step.numberedCount + 1, current: 0, animates: animatesEntrance)
                .padding(.top, Theme.Spacing.m)
                .onbReveal(.fade, order: 4)

            authArea
                .padding(.top, Theme.Spacing.l)
                .padding(.horizontal, Theme.Spacing.screen)
                .onbReveal(order: 5)

            legal
                .padding(.top, Theme.Spacing.xxs)
                .padding(.horizontal, Theme.Spacing.xl)
                .onbReveal(.fade, order: 6)
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
        if hasAccountOnAppear ?? hasAccount {
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
            // Back on this page after "Ohne Konto fortfahren": the local profile stays (no second one).
            if !app.auth.isSignedIn { app.auth.continueWithoutAccount() }
            onContinue()
        } label: {
            Text("Ohne Konto fortfahren")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
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
        .buttonStyle(.pressable)
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

    /// The figures if they were worked out earlier in this launch (going back to the welcome page).
    @MainActor static var cachedFigures: OnbDemoFigures? { cached }

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

/// Pager dots under the subtitle (welcome + the numbered setup steps); the current page is a wide capsule that
/// stretches out of its dot on the first visit.
private struct OnbPageDots: View {
    var count: Int
    var current: Int
    var animates: Bool

    @State private var isStretched: Bool

    init(count: Int, current: Int, animates: Bool) {
        self.count = count
        self.current = current
        self.animates = animates
        _isStretched = State(initialValue: !animates)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let isCurrent = index == current
                Capsule()
                    .fill(isCurrent ? AnyShapeStyle(Theme.textPrimary.opacity(0.85)) : AnyShapeStyle(Theme.textTertiary.opacity(0.55)))
                    .frame(width: isCurrent && isStretched ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(current + 1) von \(count)")
        .task {
            guard !isStretched else { return }
            try? await Task.sleep(for: .milliseconds(420))
            withMotion(Motion.bouncy) { isStretched = true }
        }
    }
}

// MARK: - Hero scene

/// Brand mark above an alpine scene: ridges with the route climbing to the summit flag and three glass chips.
/// The climber sits at the demo's amortisation along the route (arc length), with milestone dots at 25 % and 50 %.
/// Scene geometry is in unit coordinates of the area below the brand, so the composition holds from iPhone SE to Pro Max.
private struct OnbWelcomeHero: View {
    var figures: OnbDemoFigures
    var animatesEntrance: Bool
    /// The legal sheet is up: the parallax stops (the halo pauses through `ambientSkyPaused`).
    var isCovered: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    /// 0 … 1 – the climb: the walked route draws from the valley, the climber rides its tip, "Amortisiert" counts with it.
    @State private var climb: CGFloat
    /// The climber has arrived: the break-even chip pops in and the halo starts.
    @State private var hasArrived: Bool
    @State private var tilt = MotionTilt()
    @State private var isOnScreen = false
    @State private var isTilting = false

    init(figures: OnbDemoFigures, animatesEntrance: Bool, isCovered: Bool) {
        self.figures = figures
        self.animatesEntrance = animatesEntrance
        self.isCovered = isCovered
        _climb = State(initialValue: animatesEntrance ? 0 : 1)
        _hasArrived = State(initialValue: !animatesEntrance)
    }

    private static let summit = CGPoint(x: 0.70, y: 0.13)
    /// The whole way from the valley (ticket bought) to the summit flag (break-even).
    private static let path: [CGPoint] = [
        CGPoint(x: -0.02, y: 0.99), CGPoint(x: 0.06, y: 0.93), CGPoint(x: 0.13, y: 0.96), CGPoint(x: 0.21, y: 0.84),
        CGPoint(x: 0.28, y: 0.87), CGPoint(x: 0.36, y: 0.74), CGPoint(x: 0.43, y: 0.77), CGPoint(x: 0.50, y: 0.61),
        CGPoint(x: 0.56, y: 0.53), CGPoint(x: 0.635, y: 0.44), summit,
    ]
    private static let milestones: [CGFloat] = [0.25, 0.5]

    private var progress: CGFloat { CGFloat(min(max(figures.amortized, 0.04), 1)) }

    /// Parallax runs while the scene is on screen, the app active, nothing covers it, Reduce Motion is off.
    private var wantsTilt: Bool {
        isOnScreen && scenePhase == .active && !isCovered && !reduceMotion && !MotionPolicy.isStatic
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            brand
                .onbReveal(.pop, order: 0)
            GeometryReader { geo in
                scene(geo.size)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Beispiel: Ticket zu \(figures.percentText) amortisiert, Break-even am \(figures.breakEvenText), \(Int(figures.co2Kg.rounded())) Kilogramm CO₂ gespart")
        }
        .onAppear {
            isOnScreen = true
            startClimb()
        }
        .onDisappear { isOnScreen = false }
        .onChange(of: wantsTilt, initial: true) { _, wants in
            guard wants != isTilting else { return }
            isTilting = wants
            if wants { tilt.start() } else { tilt.stop() }
        }
    }

    /// The climb on the countIn curve (fast start, long soft landing), then the "aha": the break-even chip.
    private func startClimb() {
        guard climb < 1 else { return }
        if reduceMotion {
            withAnimation(Motion.crossfade) {
                climb = 1
                hasArrived = true
            }
            return
        }
        withAnimation(Motion.countIn.delay(0.25)) {
            climb = 1
        } completion: {
            withMotion(Motion.bouncy) { hasArrived = true }
        }
    }

    private func parallax(_ depth: CGFloat) -> OnbParallax {
        OnbParallax(tilt: tilt, depth: depth, isActive: isTilting)
    }

    private func scene(_ size: CGSize) -> some View {
        let split = Self.split(Self.path, at: progress, in: size)
        return ZStack(alignment: .topLeading) {
            glow(size)
                .modifier(parallax(2))
                .onbReveal(.fade, order: 0)
            ridges
                .onbReveal(.fade, order: 1)
            ZStack(alignment: .topLeading) {
                routeLayer(walked: split.walked, ahead: split.ahead)
                ForEach(Self.milestones.filter { $0 < progress - 0.08 }, id: \.self) { fraction in
                    let point = Self.split(Self.path, at: fraction, in: size).point
                    milestoneDot
                        .modifier(OnbPassReveal(climb: climb, at: fraction / progress))
                        .position(x: size.width * point.x, y: size.height * point.y)
                }
                summitMarker
                    .onbReveal(.pop, order: 3)
                    .position(x: size.width * Self.summit.x + 8, y: size.height * Self.summit.y - 12)
                if progress < 1 {
                    climberMarker
                        .modifier(OnbAlongPath(points: split.walked, size: size, fraction: climb))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .modifier(parallax(6))
            chips(size)
                .modifier(parallax(11))
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
    }

    /// Three ridges at three depths: the far ones barely move with the tilt, the frosted front ridge (with the route on
    /// it) the most – the scene gains depth without any redraw.
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
                .modifier(parallax(1.5))
            RidgeShape(peakX: 0.30, peakY: 0.36, seed: 19, roughness: 0.6)
                .fill(Theme.dusk.opacity(dark ? 0.20 : 0.14))
                .modifier(parallax(3.5))
            ZStack {
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
            .modifier(parallax(6))
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                   .init(color: .black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// The dashed way ahead is there from the start (the goal); the walked part draws up to the climber.
    private func routeLayer(walked: [CGPoint], ahead: [CGPoint]) -> some View {
        ZStack {
            OnbPolygon(points: walked, closed: false)
                .trim(from: 0, to: climb)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .blur(radius: 9)
                .opacity(0.55)
            OnbPolygon(points: walked, closed: false)
                .trim(from: 0, to: climb)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            OnbPolygon(points: ahead, closed: false)
                .stroke(Theme.textSecondary.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
                .onbReveal(.fade, order: 2)
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

    /// "Du bist hier": a quiet ring on the way up; once arrived, the motion system's halo pulses while it can be seen.
    private var climberMarker: some View {
        ZStack {
            Circle()
                .fill(Theme.dusk.opacity(0.24))
                .frame(width: 30, height: 30)
            Circle()
                .fill(Color.white)
                .frame(width: 15, height: 15)
                .overlay { Circle().stroke(Theme.dusk, lineWidth: 4) }
                .shadow(color: Theme.dusk.opacity(0.5), radius: 6)
                .background {
                    if hasArrived {
                        Color.clear
                            .frame(width: 24, height: 24)
                            .pulsingHalo(Theme.dusk, scale: 1.9)
                    }
                }
        }
        .frame(width: 40, height: 40)
    }

    /// Chip order and tiles as in mock 05 / DESIGN_FINAL_SYNTHESIS §9.1: Break-even (flag), Amortisiert (percent), CO₂ (leaf).
    /// "Amortisiert" counts with the climb; "Break-even" – where the climb leads – pops in when the climber arrives.
    private func chips(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if hasArrived {
                OnbStatChip(symbol: "flag.fill", tile: [Color(hex: "#FF9E7A"), Color(hex: "#D9573A")], label: "Break-even") {
                    Text(figures.breakEvenText)
                }
                .motionTransition(.asymmetric(insertion: .scale(scale: 0.7, anchor: .bottomLeading).combined(with: .opacity),
                                              removal: .opacity))
                .offset(x: size.width * 0.11, y: 4)
            }
            OnbStatChip(symbol: "percent", tile: [Color(hex: "#6CB6FF"), Color(hex: "#5B5FD6")], label: "Amortisiert") {
                // The final figure reserves the width; the counting figure sits on top of it.
                Text(figures.percentText)
                    .hidden()
                    .overlay(alignment: .leading) {
                        OnbClimbPercent(climb: climb, total: figures.amortized)
                    }
            }
            .onbReveal(order: 2)
            .offset(x: 14, y: size.height * 0.40)
            OnbStatChip(symbol: "leaf.fill", tile: [Color(hex: "#5FD3A2"), Color(hex: "#1E7F62")], label: "CO₂ gespart") {
                Text(figures.co2Text)
            }
            .onbReveal(order: 5)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("KlimaBilanz")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Positions the climber on the walked route at `fraction` of its length – animatable, so it rides the route's tip
/// frame by frame while the trim draws it.
private struct OnbAlongPath: ViewModifier, Animatable {
    var points: [CGPoint]
    var size: CGSize
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        let point = OnbWelcomeHero.split(points, at: fraction, in: size).point
        content.position(x: size.width * point.x, y: size.height * point.y)
    }
}

/// A milestone dot grows in the moment the climb passes it (`at` = its share of the walked route).
private struct OnbPassReveal: ViewModifier, Animatable {
    var climb: CGFloat
    var at: CGFloat

    var animatableData: CGFloat {
        get { climb }
        set { climb = newValue }
    }

    func body(content: Content) -> some View {
        let t = min(max((climb - at) / 0.06, 0), 1)
        content
            .scaleEffect(0.3 + 0.7 * t)
            .opacity(Double(t))
    }
}

/// "75 %" counting with the climb (the number itself interpolates, so it reads like a counter).
private struct OnbClimbPercent: View, Animatable {
    var climb: CGFloat
    var total: Double

    var animatableData: CGFloat {
        get { climb }
        set { climb = newValue }
    }

    var body: some View {
        Text(Format.percent(total * Double(climb)))
    }
}

/// Glass chip with a gradient icon tile ("Break-even · 21. Dez.").
private struct OnbStatChip<Value: View>: View {
    var symbol: String
    var tile: [Color]
    var label: String
    @ViewBuilder var value: () -> Value

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
                value()
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
