import SwiftUI
import KlimaCore

// MARK: funktionen – the CI scenes of Einstellungen › Funktionen (RootView's ScreenshotRouter, `// MARK: funktionen`) and the entry
// row in Einstellungen. Every scene runs on the demo data, in memory, without network and without a system alert.

enum FeatureDemo {
    /// The scene's hub settings and the wrapped switches it shows (the screenshot run's own settings are never written).
    @MainActor
    static func install(_ screen: String) {
        var settings = FeatureSettings()
        var wrapped: [FeatureID: Bool] = [.haptics: true, .weeklySummary: true]
        switch screen {
        case "featuresOffline", "featuresPlanner":
            settings.offlineMode = true
        case "featuresDependency":
            wrapped[.liveTimetable] = false
            settings.set(.perksCard, false)
        case "featuresLink":
            settings.set(.radar, false)
        default:
            // A lived-in hub: the Vorteile-Karte switched off (one note), the rest as it comes.
            settings.set(.perksCard, false)
        }
        FeatureCenter.shared.installDemo(settings, wrapped: wrapped)
    }

    /// Counters made by a real `RequestThrottle` on a pinned clock: a search 25 minutes ago, prices, half a minute of radar and
    /// a departure board in the last minute – 41 to the ÖBB-Auskunft, 3 of them in the last minute.
    static func counters(now: Date) async -> FeatureDemoCounters {
        let clock = FeatureDemoClock(now.addingTimeInterval(-25 * 60))
        let throttle = RequestThrottle(clock: clock.read, sleeper: clock.sleeper)
        let hafas = RequestThrottle.budget(for: .oebbHafas)
        let shop = RequestThrottle.budget(for: .oebbShop)
        let vao = RequestThrottle.budget(for: .vaoTariff)
        func send(_ provider: LiveProvider, _ count: Int, _ budget: (minInterval: TimeInterval, perMinute: Int)) async {
            for _ in 0..<count {
                try? await throttle.acquire(provider, minInterval: budget.minInterval, perMinute: budget.perMinute, maxWait: 120)
            }
        }
        await send(.oebbHafas, 6, hafas)          // a connection search
        clock.set(now.addingTimeInterval(-12 * 60))
        await send(.oebbShop, 4, shop)            // two prices
        await send(.vaoTariff, 2, vao)
        clock.set(now.addingTimeInterval(-9 * 60))
        await send(.oebbHafas, 32, hafas)         // the radar, open for a while
        clock.set(now.addingTimeInterval(-50))
        await send(.oebbHafas, 3, hafas)          // a departure board
        clock.set(now)
        return FeatureDemoCounters(counters: await throttle.allCounters())
    }
}

/// The pinned clock of the demo counters: sleeping moves it on.
private final class FeatureDemoClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Date

    init(_ start: Date) { now = start }

    func set(_ date: Date) {
        lock.lock(); now = date; lock.unlock()
    }

    var read: @Sendable () -> Date {
        { [self] in
            self.lock.lock(); defer { self.lock.unlock() }
            return self.now
        }
    }

    var sleeper: @Sendable (TimeInterval) async throws -> Void {
        { [self] seconds in self.advance(seconds) }
    }

    private func advance(_ seconds: TimeInterval) {
        lock.lock(); now = now.addingTimeInterval(seconds); lock.unlock()
    }
}

/// Routes the CI scenes.
struct FeaturesScreenshotHost: View {
    static let screens: Set<String> = [
        "featuresHub", "featuresOffline", "featuresPrivacy", "featuresPrivacyBottom", "featuresDependency", "featuresAX5",
        "featuresAX5Rows", "featuresPlanner", "featuresLink", "featuresSettingsRow", "featuresRows", "featuresInfo",
    ]

    let screen: String
    @Environment(AppState.self) private var app
    @State private var isReady = false
    @State private var demoCounters: FeatureDemoCounters?

    var body: some View {
        // The clear layer is always there, so `onAppear` fires before the scene exists (an empty `if` never appears).
        ZStack {
            Color.clear
            content
        }
        .dynamicTypeSize(screen.hasPrefix("featuresAX5") ? .accessibility5 : .large)
        .onAppear {
            FeatureDemo.install(screen)
            isReady = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if isReady {
            switch screen {
            case "featuresPrivacy", "featuresPrivacyBottom":
                NavigationStack {
                    if let demoCounters {
                        FeaturePrivacyScene(counters: demoCounters, scrollsToEnd: screen == "featuresPrivacyBottom")
                    }
                }
                .task { demoCounters = await FeatureDemo.counters(now: Date()) }
            case "featuresDependency":
                NavigationStack { FeaturesHubView(screenshotAnchor: .radar) }
            case "featuresInfo":
                NavigationStack { FeaturesHubView(screenshotAnchor: .radar, screenshotFlows: .radar) }
            case "featuresRows", "featuresAX5Rows":
                NavigationStack { FeaturesHubView(screenshotAnchor: .trainSearch) }
            case "featuresPlanner":
                MainTabView().onAppear { app.selectedTab = .planner }
            case "featuresLink":
                MainTabView()
                    .task {
                        app.selectedTab = .planner
                        try? await Task.sleep(for: .milliseconds(700))
                        app.planner.radarRequested = true   // what klimabilanz://radar and the radar control do
                        // Keep the toast up for the capture (it fades after 2,6 s).
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(900))
                            if app.toast == nil {
                                app.showToast("eye.slash.fill", "Zug-Radar ist ausgeblendet", "Hier kannst du es wieder einschalten")
                            }
                        }
                    }
            case "featuresSettingsRow":
                NavigationStack {
                    List {
                        SetFeaturesSection()
                        SetFareSection()
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(Theme.Spacing.l)
                    .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
                    .scrollContentBackground(.hidden)
                    .background { SetBackdrop() }
                    .navigationTitle("Einstellungen")
                    .navigationBarTitleDisplayMode(.inline)
                }
            default:
                NavigationStack { FeaturesHubView() }
            }
        }
    }
}

/// The privacy page with the demo counters, optionally scrolled to its end.
private struct FeaturePrivacyScene: View {
    var counters: FeatureDemoCounters
    var scrollsToEnd: Bool

    var body: some View {
        FeaturePrivacyView(demo: counters, screenshotScrollsToEnd: scrollsToEnd)
    }
}

/// Einstellungen › Funktionen: the entry row with the state in its subtitle.
struct SetFeaturesSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let center = FeatureCenter.shared
        let context = center.context(app: app)
        let onCount = FeatureGate.onCount(settings: center.settings, context: context)
        let hidden = FeatureGate.hiddenNotes(settings: center.settings, context: context).count
        Section {
            NavigationLink {
                FeaturesHubView()
            } label: {
                SetRowLabel(title: "Funktionen", subtitle: subtitle(onCount: onCount, hidden: hidden, offline: center.offlineMode),
                            symbol: center.offlineMode ? "wifi.slash" : "switch.2", tint: center.offlineMode ? Theme.dawn : Theme.dusk)
                    .setSymbolOnEnable(center.offlineMode)
            }
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Jede Funktion ein- und ausschalten, Offline-Modus, und was die App wohin sendet.")
        }
    }

    private func subtitle(onCount: Int, hidden: Int, offline: Bool) -> String {
        var text = "\(onCount) von \(FeatureID.allCases.count) an"
        if offline { text += " · Offline-Modus an" } else if hidden > 0 { text += " · \(hidden) ausgeblendet" }
        return text
    }
}
