import SwiftUI
import KlimaCore

// Entry points used by other screens (hooks): Einstellungen › Daten rows and the Statistik share menu item.

/// Einstellungen › Daten: "Fahrten importieren (CSV)" – opens the import flow.
struct RepImportSettingsRow: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            SetRowLabel(title: "Fahrten importieren (CSV)", subtitle: "Aus Excel, Numbers oder anderen Apps",
                        symbol: "square.and.arrow.down.on.square.fill", tint: Theme.modeColor(.sBahn))
        }
        .sheet(isPresented: $isPresented) {
            RepImportFlow()
        }
    }
}

/// Einstellungen › Daten: "Jahresbericht (PDF)" – opens the report preview.
struct RepReportSettingsRow: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            SetRowLabel(title: "Jahresbericht (PDF)", subtitle: "Dein KlimaTicket-Jahr zum Teilen und Drucken",
                        symbol: "doc.richtext.fill", tint: Theme.dawn)
        }
        .sheet(isPresented: $isPresented) {
            RepReportSheet()
        }
    }
}

/// Statistik share menu item ("Jahresbericht als PDF").
struct RepReportMenuButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Jahresbericht als PDF", systemImage: "doc.richtext")
        }
    }
}
