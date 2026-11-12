import SwiftUI
import KlimaCore

// MARK: tarifstand – CI screenshots (`-KBScreenshot <name> -KBDemo YES`, RootView › ScreenshotRouter): the price notice on the
// Ticket tab in its three states, its details sheet and the Tarifstand row in Einstellungen. Demo fixture: the clock, the
// catalogue's age and the last check are injected (`\.tariffNoticeInput`), so every state shows on any day; no network.
//
//   tarifNoticeUpcoming  2 December 2026: timetable change on 13.12., data from October
//   tarifNoticeNewYear   5 January 2027: no KlimaTicket price entry for 2027
//   tarifNoticeStale     12 November 2026 with a fare index from September 2025 (more than 13 months)
//   tarifSettingsRow     Preisberechnung with the Tarifstand row, the three dates and a finished check (Aktuell)
//   tarifSheet           the details sheet of the upcoming-change notice
//   tarifNoticeAX5       the banner at the largest text size · tarifSettingsRowAX5 the two rows (Kein Netz) at the largest size
struct TarifstandScreenshotHost: View {
    static let screens: Set<String> = [
        "tarifNoticeUpcoming", "tarifNoticeNewYear", "tarifNoticeStale", "tarifSettingsRow", "tarifSheet",
        "tarifNoticeAX5", "tarifSettingsRowAX5",
        // MARK: review-tarifstand – no banner (the Ticket tab as before), the details when nothing is due, a finished check that
        // brings a pack for a later day
        "tarifNoticeCurrent", "tarifSheetCurrent", "tarifSheetUpdated",
    ]

    let screen: String

    @Environment(AppState.self) private var app

    var body: some View {
        content
            .dynamicTypeSize(screen.hasSuffix("AX5") ? .accessibility5 : .large)
    }

    // MARK: Fixtures

    private static func vienna(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        Calendar.vienna.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? Date()
    }

    /// The app's own catalogue and relation table, the clock of the fixture, a last check on the morning of 12 November.
    private func input(_ now: Date, catalog: TariffCatalog? = nil) -> TariffNoticeInput {
        TariffNoticeInput(catalog: catalog ?? app.catalog, now: now, lastCheck: Self.vienna(2026, 11, 12, 9, 41),
                          fareValidFrom: app.relations.validFrom)
    }

    private var upcoming: TariffNoticeInput { input(Self.vienna(2026, 12, 2)) }
    private var newYear: TariffNoticeInput { input(Self.vienna(2027, 1, 5)) }

    /// Fare index of September 2025 only: 13 months later (October 2026) the data counts as stale.
    private var stale: TariffNoticeInput {
        var catalog = app.catalog
        catalog.fareIndex = [.init(validFrom: "2025-09-01", factor: 1.02)]
        return input(Self.vienna(2026, 11, 12), catalog: catalog)
    }

    // MARK: Screens

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "tarifNoticeUpcoming":
            ticketTab(upcoming)
        case "tarifNoticeAX5":
            // The whole Ticket tab does not fit at this size (its own layout), so the banner is shown on its own.
            ScrollView {
                TariffNoticeBanner()
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.xxl)
            }
            .ambientBackground()
            .environment(\.tariffNoticeInput, upcoming)
        case "tarifNoticeNewYear":
            ticketTab(newYear)
        case "tarifNoticeStale":
            ticketTab(stale)
        case "tarifSettingsRow":
            settingsSection(input(Self.vienna(2026, 11, 12, 10, 0)), check: .finished(.current))
        case "tarifSettingsRowAX5":
            settingsSection(upcoming, check: .finished(.offline), onlyTarifstand: true)
        case "tarifSheet":
            Color.clear
                .ambientBackground()
                .sheet(isPresented: .constant(true)) {
                    TariffNoticeSheet(input: upcoming, check: TarifCheck(phase: .finished(.current)))
                }
        // MARK: review-tarifstand
        case "tarifNoticeCurrent":
            ticketTab(input(Self.vienna(2026, 11, 12, 10, 0)))
        case "tarifSheetCurrent":
            Color.clear
                .ambientBackground()
                .sheet(isPresented: .constant(true)) {
                    TariffNoticeSheet(input: input(Self.vienna(2026, 11, 12, 10, 0)), check: TarifCheck())
                }
        case "tarifSheetUpdated":
            Color.clear
                .ambientBackground()
                .sheet(isPresented: .constant(true)) {
                    TariffNoticeSheet(input: upcoming, check: TarifCheck(phase: .finished(.updated(startsOn: "2026-12-13"))))
                }
        default:
            MainTabView().onAppear { app.selectedTab = .ticket }
        }
    }

    private func ticketTab(_ input: TariffNoticeInput) -> some View {
        MainTabView()
            .onAppear { app.selectedTab = .ticket }
            .environment(\.tariffNoticeInput, input)
    }

    /// The Preisberechnung section as in Einstellungen (same list style and backdrop).
    private func settingsSection(_ input: TariffNoticeInput, check: TarifCheck.Phase, onlyTarifstand: Bool = false) -> some View {
        NavigationStack {
            List {
                if onlyTarifstand {
                    // At the largest size the two new rows would sit below the fold: show just them under the section header.
                    Section {
                        SetTarifstandRows()
                            .listRowBackground(Theme.surface)
                    } header: {
                        SetSectionHeader(title: "Preisberechnung")
                    }
                } else {
                    SetFareSection()
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.l)
            .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop() }
            .tint(Theme.accent)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.tariffNoticeInput, input)
        .environment(\.tarifCheckPreset, check)
    }
}
