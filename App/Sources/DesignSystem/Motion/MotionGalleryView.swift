import SwiftUI
import TipKit
import KlimaCore

/// Design-system QA for the motion system (CI screenshot routes "motionGallery", "motionGallery2", "motionGallery3",
/// DEBUG builds only – see ScreenshotRouter). Every pattern of docs/MOTION.md in one scrollable page; in screenshot mode
/// everything shows its end state. Compiled in every configuration so the Linux type-check covers it; only the route
/// is DEBUG-only.
struct MotionGalleryView: View {
    enum Section: String, CaseIterable { case top, controls, celebrate }

    var initialSection: Section = .top

    @State private var condense = ScrollCondense()
    @State private var replay = 0
    @State private var total: Double = 946
    @State private var range = "Monat"
    @State private var isExpanded = MotionPolicy.isStatic
    @State private var isFavorite = MotionPolicy.isStatic
    @State private var celebrateCount = 0
    @State private var springsAtEnd = MotionPolicy.isStatic
    @State private var lastHaptic: Haptic?
    @State private var hapticCount = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header
                        revealSection.id(replay)
                        numbersSection
                        springsSection
                        controlsSection.id(Section.controls)
                        glassSection
                        symbolsSection
                        celebrateSection.id(Section.celebrate)
                        carouselSection
                        zoomSection
                        hapticsSection
                        tipSection
                        scrollCardsSection
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.bottom, Theme.Spacing.xxl)
                }
                .tracksScrollCondense(condense, distance: 160)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onAppear {
                    if initialSection != .top { proxy.scrollTo(initialSection, anchor: .top) }
                }
            }
            .revealScope()
            .ambientBackground()
            .navigationTitle("Bewegung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CompactTitle(condense: condense, total: total)
                }
            }
            .navigationDestination(for: String.self) { id in
                ZoomDetail(id: id)
                    .zoomDestination(id: id)
            }
        }
        .zoomTransitionScope()
        .onAppear { KBTips.configureForGallery() }
    }

    // MARK: Header (condenses on scroll)

    private var header: some View {
        VStack(spacing: 2) {
            Kicker(text: "Design System · Motion")
            CountUpText(value: total) { Format.euro($0) }
                .font(.system(size: 64, weight: .thin, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .reveal(.focus)
            Text("zählt einmal hoch, danach rollen die Ziffern")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .reveal(order: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.m)
        .heroCondense(condense, minScale: 0.8)
    }

    // MARK: Reveal

    private var revealSection: some View {
        GallerySection(title: "Reveal & Stagger", note: "Nur beim ersten Erscheinen · 45 ms Versatz") {
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(Self.demoTrips.enumerated()), id: \.offset) { index, trip in
                    TripRow(fromName: trip.from, toName: trip.to, date: Date(), mode: trip.mode, distanceKm: trip.km,
                            value: trip.value, isRoundTrip: index == 0)
                        .reveal(order: index + 1)
                }
            }
            .revealScope()   // replay: a fresh scope with every new `replay` id
            Button("Nochmal abspielen") { replay += 1 }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    // MARK: Numbers

    private var numbersSection: some View {
        GallerySection(title: "Zahlen", note: ".numericValue · Motion.number") {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.euro(total))
                    .font(Theme.Typography.numberLarge)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(total)
                Spacer()
                Text(Format.percent(total / 1400))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.positiveText)
                    .numericValue(total)
            }
            ProgressRail(progress: min(total / 1400, 1), leadingLabel: "Amortisiert", trailingLabel: Format.euro(1400))
                .motionAnimation(Motion.smooth, value: total)
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    withMotion { total = max(0, total - 23.5) }
                } label: {
                    Label("Fahrt weg", systemImage: "minus")
                }
                .buttonStyle(.glass)
                .haptic(.decrease, trigger: total, when: { old, new in new < old })
                Button {
                    withMotion { total += 23.5 }
                } label: {
                    Label("+ € 23,50", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .haptic(.increase, trigger: total, when: { old, new in new > old })
            }
            .labelStyle(.titleAndIcon)
        }
    }

    // MARK: Springs

    private var springsSection: some View {
        GallerySection(title: "Federn", note: "snappy · smooth · bouncy · gentle") {
            VStack(spacing: Theme.Spacing.s) {
                SpringTrack(name: "snappy", detail: "Tippen, Auswahl", animation: Motion.snappy, atEnd: springsAtEnd)
                SpringTrack(name: "smooth", detail: "Layout, Glas", animation: Motion.smooth, atEnd: springsAtEnd)
                SpringTrack(name: "bouncy", detail: "Bestätigung", animation: Motion.bouncy, atEnd: springsAtEnd)
                SpringTrack(name: "gentle", detail: "Hero, Charts", animation: Motion.gentle, atEnd: springsAtEnd)
            }
            Button(springsAtEnd ? "Zurück" : "Abspielen") { springsAtEnd.toggle() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    // MARK: Press

    private var controlsSection: some View {
        GallerySection(title: "Drücken", note: ".pressable · .pressableCard · .primary") {
            HStack(spacing: Theme.Spacing.s) {
                Button {} label: {
                    Label("Chip", systemImage: "tram.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.pressable)
                Button {} label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.pressable(scale: 0.9, haptic: true))
                .accessibilityLabel("Tauschen")
            }
            Button {} label: {
                HStack {
                    ModeIcon(mode: .train, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Karte drücken").font(.headline)
                        Text("98 % · Motion.press / .release").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
                }
                .padding(Theme.Spacing.s)
                .frostedCard(cornerRadius: Theme.Radius.tile)
            }
            .buttonStyle(.pressableCard)
            Button("Fahrt speichern · € 47,00") {}
                .buttonStyle(.primary)
        }
    }

    // MARK: Glass

    private var glassSection: some View {
        GallerySection(title: "Glas, das verschmilzt", note: "GlassMorphGroup · GlassSegmentedPicker") {
            GlassSegmentedPicker(selection: $range, options: ["Woche", "Monat", "Jahr"]) { Text($0) }
            GlassMorphGroup(spacing: 14) { ns in
                HStack(spacing: 14) {
                    if isExpanded {
                        ForEach(["star.fill", "clock.arrow.circlepath", "map.fill"], id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 48, height: 48)
                                .morphingGlass(in: .circle, id: symbol, namespace: ns)
                        }
                    }
                    Button {
                        withMotion(Motion.bouncy) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "xmark" : "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 56, height: 56)
                            .symbolReplaceTransition()
                    }
                    .buttonStyle(.pressable(scale: 0.9))
                    .morphingGlass(.regular.tint(Theme.accent).interactive(), in: .circle, id: "main", namespace: ns)
                    .haptic(.tap, trigger: isExpanded)
                    .accessibilityLabel(isExpanded ? "Schließen" : "Mehr Aktionen")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: Symbols

    private var symbolsSection: some View {
        GallerySection(title: "Symbole", note: ".symbolBounce · .symbolReplaceTransition") {
            HStack(spacing: Theme.Spacing.l) {
                Button {
                    withMotion(Motion.bouncy) { isFavorite.toggle() }
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(isFavorite ? Theme.gold : Theme.textSecondary)
                        .symbolReplaceTransition()
                        .symbolBounce(on: isFavorite)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                .haptic(.selection, trigger: isFavorite)
                .accessibilityLabel(isFavorite ? "Favorit entfernen" : "Als Favorit merken")
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.positive)
                    .symbolBounce(on: celebrateCount)
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.dawn)
                    .symbolEffect(.wiggle, value: celebrateCount)
                Image(systemName: "leaf.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.pine)
                    .symbolBounce(on: total)
            }
        }
    }

    // MARK: Celebrate

    private var celebrateSection: some View {
        GallerySection(title: "Feiern", note: ".celebrate · .celebrationRing · .celebrationBurst") {
            HStack(spacing: Theme.Spacing.xl) {
                Medallion(symbol: "mountain.2.fill", tier: .gold)
                    .celebrate(trigger: celebrateCount)
                    .celebrationRing(trigger: celebrateCount)
                Medallion(symbol: "flag.checkered", tier: .platinum)
                    .celebrate(trigger: celebrateCount, haptic: nil)
                    .celebrationBurst(trigger: celebrateCount)
                Spacer(minLength: 0)
                Button("Feiern") { celebrateCount += 1 }
                    .buttonStyle(.glassProminent)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    // MARK: Carousel

    private var carouselSection: some View {
        GallerySection(title: "Karussell", note: ".carouselScrolling · .carouselItem", padsContent: false) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(Self.demoTrips, id: \.from) { trip in
                        Button {} label: {
                            HStack(spacing: 8) {
                                ModeIcon(mode: trip.mode, size: 30)
                                Text("\(TripRow.short(trip.from)) → \(TripRow.short(trip.to))")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(Format.euroPrecise(trip.value))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Theme.accentText)
                            }
                            .padding(.leading, 6)
                            .padding(.trailing, 14)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.pressable)
                        .carouselItem()
                    }
                }
                .scrollTargetLayout()
            }
            .carouselScrolling(margin: Theme.Spacing.m)
        }
    }

    // MARK: Zoom

    private var zoomSection: some View {
        GallerySection(title: "Zoom-Navigation", note: ".zoomSource · .zoomDestination") {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(["Innsbruck", "Wien"], id: \.self) { id in
                    NavigationLink(value: id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.accentText)
                            Text(id).font(.headline).foregroundStyle(Theme.textPrimary)
                            Text("öffnet mit Zoom").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frostedCard(cornerRadius: Theme.Radius.tile)
                        .zoomSource(id: id, cornerRadius: Theme.Radius.tile)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
        }
    }

    // MARK: Haptics

    private var hapticsSection: some View {
        GallerySection(title: "Haptik", note: "eine Bedeutung je Haptik · folgt Einstellungen") {
            FlowChips(items: Self.haptics.map(\.name)) { index in
                lastHaptic = Self.haptics[index].haptic
                hapticCount += 1
            }
            .sensoryFeedback(trigger: hapticCount) { lastHaptic?.feedback }
        }
    }

    // MARK: Tips

    private var tipSection: some View {
        GallerySection(title: "Tipps", note: "KBTips · TipKit") {
            TipView(KBTips.TripSwipe())
                .kbTipStyle()
            TipView(KBTips.QuickLog())
                .kbTipStyle()
        }
    }

    // MARK: Scroll cards

    private var scrollCardsSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            SectionHeader(title: "Scroll-Karten")
            ForEach(0..<4, id: \.self) { index in
                GlassCard(padding: Theme.Spacing.m) {
                    HStack {
                        StatGlyph(index: index)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(["Fahrten", "Kilometer", "CO₂ gespart", "Mit dem Auto"][index]).font(.headline)
                            Text(".scrollCardTransition").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
                .scrollCardTransition()
            }
        }
    }

    // MARK: Demo data

    private struct DemoTrip {
        let from: String, to: String, mode: TransportMode, km: Double, value: Double
    }

    private static let demoTrips: [DemoTrip] = [
        DemoTrip(from: "St. Anton am Arlberg", to: "Innsbruck Hauptbahnhof", mode: .train, km: 101, value: 47),
        DemoTrip(from: "Innsbruck Hauptbahnhof", to: "Hall in Tirol", mode: .sBahn, km: 9, value: 3.6),
        DemoTrip(from: "Wien Westbahnhof", to: "Wien Stephansplatz", mode: .metro, km: 4, value: 2.4),
        DemoTrip(from: "Lech Post", to: "Warth am Arlberg Dorf", mode: .bus, km: 15, value: 5.8),
    ]

    private static let haptics: [(name: String, haptic: Haptic)] = [
        ("Erfolg", .success), ("Warnung", .warning), ("Fehler", .error), ("Auswahl", .selection), ("Tippen", .tap),
        ("Einrasten", .snap), ("Mehr", .increase), ("Weniger", .decrease), ("Meilenstein", .milestone),
        ("Start", .start), ("Stopp", .stop),
    ]
}

// MARK: - Gallery building blocks

private struct GallerySection<Content: View>: View {
    var title: String
    var note: String
    var padsContent = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typography.sectionTitle).foregroundStyle(Theme.textPrimary)
                Text(note).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, padsContent ? 0 : Theme.Spacing.m)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.vertical, Theme.Spacing.m)
        .padding(.horizontal, padsContent ? Theme.Spacing.m : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard()
        .reveal()
    }
}

/// The compact toolbar title that fades in once the hero has condensed.
private struct CompactTitle: View {
    let condense: ScrollCondense
    let total: Double

    var body: some View {
        let p = condense.value
        HStack(spacing: 6) {
            Text("Bewegung").font(.headline)
            Text(Format.euro(total))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.accentText)
                .numericValue(total)
                .opacity(Double(max(0, p - 0.5) * 2))
        }
    }
}

private struct SpringTrack: View {
    let name: String
    let detail: String
    let animation: Animation
    let atEnd: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.subheadline.weight(.semibold).monospaced())
                Text(detail).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 92, alignment: .leading)
            Capsule()
                .fill(Theme.surfaceSecondary)
                .frame(height: 6)
                .overlay(alignment: atEnd ? .trailing : .leading) {
                    Circle()
                        .fill(Theme.routeGradient)
                        .frame(width: 22, height: 22)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 2)
                }
                .motionAnimation(animation, value: atEnd)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Medallion: View {
    let symbol: String
    let tier: Achievement.Tier

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(Theme.tierGradient(tier), in: .circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

private struct StatGlyph: View {
    let index: Int

    var body: some View {
        let symbols = ["tram.fill", "point.topleft.down.to.point.bottomright.curvepath.fill", "leaf.fill", "car.fill"]
        let colors = [Theme.glacier, Theme.dusk, Theme.pine, Theme.dawn]
        Image(systemName: symbols[index % symbols.count])
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(colors[index % colors.count])
            .frame(width: 34, height: 34)
            .background(colors[index % colors.count].opacity(0.14), in: .circle)
    }
}

/// Wrapping chip row (haptics vocabulary).
private struct FlowChips: View {
    let items: [String]
    let action: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button(item) { action(index) }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(Theme.textPrimary)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .buttonStyle(.pressable)
            }
        }
    }
}

/// Minimal flow layout: rows of chips that wrap.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The pushed detail of the zoom demo.
private struct ZoomDetail: View {
    let id: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: "Detail")
                Text(id).font(.largeTitle.bold())
                Text("Diese Ansicht wächst aus der Karte heraus und schrumpft beim Zurückwischen wieder hinein.")
                    .foregroundStyle(Theme.textSecondary)
                ForEach(0..<3, id: \.self) { index in
                    GlassCard {
                        Text("Abschnitt \(index + 1)").font(.headline)
                    }
                    .reveal(order: index)
                }
            }
            .padding(Theme.Spacing.screen)
        }
        .revealScope()
        .ambientBackground()
    }
}
