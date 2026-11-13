import SwiftUI
import KlimaCore

// „Filter & Darstellung“ of the radar (MARK: radarmodes, docs/RADAR_MODES.md §6): two pages. „Filter“: Schnellwahl, Verkehrsmittel, Zugart, Linie
// oder Zugnummer, Betreiber, Verspätung, Region (`Modes/RadarFilterPage.swift`). „Darstellung“: labels, size, groups, arrow, city refresh, and the
// sections of the other radar2 parts (`Modes/RadarDisplayPage.swift`). Every change applies at once to the map; filters and display are kept per device.

struct RadarFilterSheet: View {
    enum Page: String, CaseIterable, Identifiable {
        case filter, display
        var id: Self { self }
        var title: String { self == .filter ? RadarModesText.filterPage : RadarModesText.displayPage }
    }

    @Binding var filter: RadarFilter
    @Binding var modes: RadarModeSelection
    /// MARK: radarmodes – „Darstellung“.
    @Binding var display: RadarDisplay
    /// Every vehicle the radar holds (lines, operators and counts of the sections come from them).
    var vehicles: [RadarVehicle]
    /// The vehicles on the map per mode now („gerade 180“).
    var counts: RadarModeCounts
    /// MARK: radar2 – the parts of the second wave add their sections at the end of „Darstellung“ (`Radar2SettingsSections`).
    var parts: Radar2Parts? = nil
    @State var page: Page = .filter
    /// The CI scene of the lower filter sections scrolls there.
    var scrollTo: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .filter:
                    RadarFilterPage(filter: $filter, modes: $modes, vehicles: vehicles, counts: counts, scrollTo: scrollTo)
                case .display:
                    RadarDisplayPage(display: $display, parts: parts)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker(RadarModesText.sheetTitle, selection: $page) {
                    ForEach(Page.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.sheetBackground)
                .haptic(.selection, trigger: page)
            }
            .background(Theme.sheetBackground)
            .navigationTitle(RadarModesText.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
