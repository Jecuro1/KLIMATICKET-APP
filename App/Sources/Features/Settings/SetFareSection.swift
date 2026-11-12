import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Preisberechnung

/// Defaults used to value new trips: discount card, class and how the normal fare is estimated.
struct SetFareSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Group {
                Picker(selection: $settings.defaultDiscount) {
                    ForEach(FareDiscount.allCases) { discount in
                        Text(SetFareSection.title(for: discount)).tag(discount)
                    }
                } label: {
                    SetRowLabel(title: "Ermäßigung", symbol: "percent", tint: Theme.dusk)
                        .setSymbolEffect(.bounce, trigger: settings.defaultDiscount)
                }
                .haptic(.selection, trigger: settings.defaultDiscount)
                Picker(selection: $settings.defaultTravelClass) {
                    ForEach(TravelClass.allCases) { travelClass in
                        Text(travelClass.displayName).tag(travelClass)
                    }
                } label: {
                    SetRowLabel(title: "Klasse", symbol: "sofa.fill", tint: Theme.modeColor(.train))
                        .setSymbolEffect(.bounce, trigger: settings.defaultTravelClass)
                }
                .haptic(.selection, trigger: settings.defaultTravelClass)
                NavigationLink {
                    SetInfoPage(title: "Preisschätzung", kicker: "So rechnet KlimaBilanz", symbol: "eurosign.circle.fill",
                                tint: Theme.glacier, text: Copy.fareExplanation,
                                notesTitle: "Tarifstand · Version \(app.catalog.version)", notes: app.catalog.notes)
                } label: {
                    SetRowLabel(title: "Wie wird der Preis geschätzt?", symbol: "eurosign.circle.fill", tint: Theme.glacier)
                }
                SetTarifstandRows()   // MARK: tarifstand – dates of the price data, „Jetzt prüfen“
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Preisberechnung")
        } footer: {
            SetFooter(text: "Bestimmt den Normalpreis, mit dem jede neue Fahrt bewertet wird. Beim Erfassen kannst du jeden Preis antippen und anpassen. Neue Preise lädt die App von selbst – ohne App-Update.")
        }
    }

    static func title(for discount: FareDiscount) -> String {
        switch discount {
        case .none: "Keine"
        case .vorteilscard: "Vorteilscard"
        }
    }
}
