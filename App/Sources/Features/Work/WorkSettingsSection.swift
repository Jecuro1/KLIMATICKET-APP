import SwiftUI
import KlimaCore

/// Einstellungen › "Arbeit & Auto": entry rows for "Arbeit & Steuer" and "Auto-Vergleich".
struct WorkSettingsSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let settings = WorkSettings.shared
        Section {
            Group {
                NavigationLink {
                    WorkTaxView()
                } label: {
                    SetRowLabel(title: "Arbeit & Steuer", subtitle: "Jobticket, Dienstreisen, Pendler- und Betriebsausgaben",
                                symbol: "briefcase.fill", tint: Theme.glacier)
                }
                NavigationLink {
                    WorkCarSettingsView()
                } label: {
                    SetRowLabel(title: "Auto-Vergleich",
                                subtitle: "\(settings.carMode.displayName) · \(WorkFormat.perKm(settings.carProfile(catalog: app.catalog).costPerKm))\(settings.carGivenUp ? " · ohne Auto" : "")",
                                symbol: "car.fill", tint: Theme.dawn)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Arbeit & Auto")
        } footer: {
            SetFooter(text: "Für Arbeitnehmerveranlagung und Betriebsausgaben – keine Steuerberatung.")
        }
    }
}
