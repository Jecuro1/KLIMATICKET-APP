import SwiftUI
import SwiftData
import KlimaCore

/// "Live-Aktivität" – the real Lock Screen and Dynamic Island views of a ride, rendered as plain SwiftUI on stages
/// (a Live Activity itself cannot be captured in CI). CI screenshot `liveActivityPreview`, and the ⓘ of the trip
/// editor's "Fahrt jetzt starten" card. Uses the first favourite and the active ticket, else a sample.
struct RideActivityPreviewView: View {
    var isSheet: Bool = false

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    /// Built once, so the running timer keeps its start.
    @State private var sample: RidePreviewSample?
    @State private var showsNavigationTitle = false
    @State private var controller = RideActivityController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let sample {
                    RidePreviewLockStage(sample: sample)
                    RidePreviewIslandStage(sample: sample)
                }
                RidePreviewSteps(isEnabled: controller.areActivitiesEnabled || LaunchMode.isScreenshot)
            }
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { backdrop }
        .navigationTitle("Live-Aktivität")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Live-Aktivität")
                    .font(.headline)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .accessibilityHidden(!showsNavigationTitle)
            }
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Schließen")
                }
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, isPastHeader in
            withAnimation(.easeInOut(duration: 0.2)) { showsNavigationTitle = isPastHeader }
        }
        .onAppear {
            if sample == nil { sample = RidePreviewSample.make(favorites: favorites, context: context, app: app) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: "Unterwegs")
            Text("Live-Aktivität")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Deine Fahrt live am Sperrbildschirm und in der Dynamic Island – mit ihrem Wert und deinem Weg zum Gipfel.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screen)
    }

    /// In a sheet the calm sheet surface with a pale sky (DESIGN.md §2), otherwise the alpine sky.
    @ViewBuilder
    private var backdrop: some View {
        if isSheet {
            ZStack(alignment: .top) {
                Theme.sheetBackground
                AmbientBackground(style: .standard, glow: 0.6)
                    .opacity(0.55)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.6), location: 0.25),
                                               .init(color: .clear, location: 0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            AmbientBackground()
        }
    }
}

// MARK: - Sample

/// A ride as the app would start it right now, 42 minutes in.
struct RidePreviewSample {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState

    @MainActor
    static func make(favorites: [FavoriteRouteEntity], context: ModelContext, app: AppState, now: Date = Date()) -> RidePreviewSample {
        let start = now.addingTimeInterval(-(42 * 60 + 17))
        let ride: RideStart
        if let favorite = favorites.first(where: { $0.mode == .train }) ?? favorites.first {
            ride = RidePlanner.ride(favorite: favorite, context: context, app: app, startedAt: start)
        } else {
            ride = fallback(startedAt: start)
        }
        return RidePreviewSample(attributes: ride.attributes, state: ride.initialState)
    }

    /// St. Anton → Innsbruck Hbf on a € 1.400 ticket at 75 % (no data yet).
    static func fallback(startedAt: Date) -> RideStart {
        let trip = RideTrip(fromName: "St. Anton am Arlberg", toName: "Innsbruck Hauptbahnhof", mode: .train, distanceKm: 101,
                            fareEUR: 23.5, isRoundTrip: true)
        var ride = RideStart(trip: trip, startedAt: startedAt)
        ride.payoff = RidePayoff(currentValue: 1_050, ticketPrice: 1_400, rideValue: trip.totalValue)
        ride.climb = [0, 0.05, 0.11, 0.16, 0.22, 0.29, 0.34, 0.4, 0.46, 0.52, 0.57, 0.62, 0.68, 0.72, 0.75]
        ride.ticketName = "KlimaTicket Ö Klassik"
        return ride
    }
}

// MARK: - Lock Screen stage

/// The Lock Screen activity under the clock, on a wallpaper (light: Morgendämmerung, dark: Blaue Stunde).
private struct RidePreviewLockStage: View {
    let sample: RidePreviewSample

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
        VStack(spacing: 0) {
            Text(Format.weekdayDayMonth(Date()))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(verbatim: "9:41")
                .font(.system(size: 74, weight: .semibold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Color.white, Color.white.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
                .padding(.top, -6)
                .accessibilityHidden(true)
            RideLockScreenView(attributes: sample.attributes, state: sample.state, isInteractive: false)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)
                .padding(.top, 8)
            Text("Sperrbildschirm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
                .padding(.top, 10)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background { RidePreviewWallpaper() }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6) }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .padding(.horizontal, Theme.Spacing.xs + 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vorschau Sperrbildschirm")
    }
}

/// Lock Screen wallpaper: alpine sky at dawn (light) or blue hour (dark) with a ridge line.
private struct RidePreviewWallpaper: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.55, 0.45], [1, 0.55],
        [0, 1], [0.5, 1], [1, 1],
    ]

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            MeshGradient(width: 3, height: 3, points: Self.points, colors: dark ? darkColors : lightColors)
            if dark {
                StarField(seed: 11, count: 40, t: 0)
            }
            WidRidgeShape(peak: CGPoint(x: 0.76, y: 0.78), seed: 4, drop: 0.7, roughness: 1.1)
                .fill(Color.white.opacity(dark ? 0.06 : 0.16))
            WidRidgeShape(peak: CGPoint(x: 0.22, y: 0.86), seed: 9, drop: 0.6, roughness: 1)
                .fill((dark ? Theme.background : Theme.dusk).opacity(dark ? 0.6 : 0.22))
        }
        .accessibilityHidden(true)
    }

    private var lightColors: [Color] {
        [Color(hex: "#3F7FCF"), Color(hex: "#6C77D9"), Color(hex: "#9A7BD6"),
         Color(hex: "#5B9BE0"), Color(hex: "#8E86DE"), Color(hex: "#E98B86"),
         Color(hex: "#7FB4E6"), Color(hex: "#C79AC9"), Color(hex: "#F2A27A")]
    }

    private var darkColors: [Color] {
        [Color(hex: "#07112A"), Color(hex: "#111C44"), Color(hex: "#1D1A4A"),
         Color(hex: "#0B1838"), Color(hex: "#251F58"), Color(hex: "#47295C"),
         Color(hex: "#0A1430"), Color(hex: "#2A2050"), Color(hex: "#5A2E55")]
    }
}

// MARK: - Dynamic Island stage

/// Expanded, compact and minimal Dynamic Island over the app's sky.
private struct RidePreviewIslandStage: View {
    let sample: RidePreviewSample

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
        VStack(spacing: 8) {
            RideIslandExpandedMock(sample: sample)
            caption("Dynamic Island · erweitert")
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 8) {
                    RideIslandCompactMock(sample: sample)
                    caption("Kompakt")
                }
                VStack(spacing: 8) {
                    RideIslandMinimalMock(sample: sample)
                    caption("Minimal")
                }
            }
            .padding(.top, 6)
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background { WidSkyBackground(family: .systemLarge) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6) }
        .shadow(color: Color.black.opacity(0.14), radius: 16, y: 8)
        .padding(.horizontal, Theme.Spacing.xs + 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vorschau Dynamic Island")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
    }
}

/// The black island shape with a hairline so it stays defined on the dark sky.
private struct RideIslandShapeStyle: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Color.black))
            .overlay { shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0), lineWidth: 0.6) }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.22), radius: 12, y: 6)
    }
}

/// Approximates the system layout: leading / trailing beside the camera, center below it, bottom across.
private struct RideIslandExpandedMock: View {
    let sample: RidePreviewSample

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                RideIslandLeading(attributes: sample.attributes)
                    .frame(width: 64, alignment: .leading)
                VStack(spacing: 0) {
                    Color.clear.frame(height: 24)   // camera
                    RideIslandCenter(attributes: sample.attributes, state: sample.state, isStale: false)
                }
                .frame(maxWidth: .infinity)
                RideIslandTrailing(attributes: sample.attributes, state: sample.state)
                    .frame(width: 92, alignment: .trailing)
            }
            RideIslandBottom(attributes: sample.attributes, state: sample.state, isStale: false, isInteractive: false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .modifier(RideIslandShapeStyle(cornerRadius: 44))
        .environment(\.colorScheme, .dark)
    }
}

private struct RideIslandCompactMock: View {
    let sample: RidePreviewSample

    var body: some View {
        HStack(spacing: 0) {
            RideIslandCompactLeading(attributes: sample.attributes, state: sample.state)
            Color.clear.frame(width: 84)   // camera
            RideIslandCompactTrailing(state: sample.state)
        }
        .padding(.horizontal, 12)
        .frame(height: 37)
        .modifier(RideIslandShapeStyle(cornerRadius: 18.5))
        .environment(\.colorScheme, .dark)
    }
}

private struct RideIslandMinimalMock: View {
    let sample: RidePreviewSample

    var body: some View {
        RideIslandMinimal(attributes: sample.attributes, state: sample.state)
            .frame(width: 37, height: 37)
            .modifier(RideIslandShapeStyle(cornerRadius: 18.5))
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - How it works

private struct RidePreviewSteps: View {
    var isEnabled: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("So funktioniert's")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Theme.Spacing.xxs)
            GlassCard(padding: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 14) {
                    step(symbol: "play.fill", tint: Theme.dusk, title: "Losfahren",
                         text: "Im Fahrt-Editor „Fahrt jetzt starten“ tippen – oder den Kurzbefehl „Fahrt starten“ mit einer Lieblingsfahrt nutzen, auch über die Aktionstaste.")
                    step(symbol: "mountain.2.fill", tint: Theme.dawn, title: "Unterwegs",
                         text: "Sperrbildschirm und Dynamic Island zeigen den Wert der Fahrt und wie weit sie dich zum Gipfel bringt.")
                    step(symbol: "checkmark", tint: Theme.pine, title: "Ankommen",
                         text: "„Fahrt speichern“ tippen – fertig. Nach 8 Stunden endet die Live-Aktivität von selbst, dann fragt KlimaBilanz nach.")
                    if !isEnabled {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Label("Live-Aktivitäten in den Einstellungen erlauben", systemImage: "gearshape.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
    }

    private func step(symbol: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            TripEdIconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CI screenshots

extension View {
    /// CI screenshot `addTripLive`: the trip editor opens scrolled to its end, where "Fahrt jetzt starten" sits.
    func rideScreenshotScrollAnchor() -> some View {
        defaultScrollAnchor(LaunchMode.screenshotScreen == "addTripLive" ? .bottom : nil)
    }
}

extension RideActivityController {
    /// CI screenshot `dashboardLive`: a ride 42 minutes in for the Übersicht capsule (CI has no real Live Activity).
    func showScreenshotRide(context: ModelContext, app: AppState) {
        guard LaunchMode.isScreenshot else { return }
        let start = Date().addingTimeInterval(-(42 * 60 + 17))
        let ride = Repository(context: context, app: app).liveFavorites().first(where: { $0.mode == .train })
            .map { RidePlanner.ride(favorite: $0, context: context, app: app, startedAt: start) }
            ?? RidePreviewSample.fallback(startedAt: start)
        var record = ride.record
        record.activityID = "screenshot"
        showPreview(rides: [record])
    }
}
