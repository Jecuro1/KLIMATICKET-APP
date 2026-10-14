import SwiftUI
import KlimaCore

/// Einstellungen › „KI auf dem Gerät“ (docs/LOCAL_AI.md §2). Shows the real state of the on-device model, the switch, what
/// runs on the device and what each feature does without the model. Nothing on this page sends data anywhere.
struct AssistantSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var settings = app.settings
        let assistant = app.assistant
        List {
            Section {
                AssistantStatusCard(availability: assistant.availability)
                    .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "Status")
            }

            Section {
                Toggle(isOn: $settings.localAIEnabled) {
                    SetRowLabel(title: "KI nutzen",
                                subtitle: assistant.isSwitchedOn ? "An: Texte entstehen mit dem Modell" : "Aus: alle Texte kommen aus den Regeln",
                                symbol: "sparkles", tint: Theme.dusk)
                        .setSymbolOnEnable(settings.localAIEnabled)
                }
                .haptic(.selection, trigger: settings.localAIEnabled)
                .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "Schalter")
            } footer: {
                SetFooter(text: "Aus heißt: Das Modell wird nie gefragt. Alle Funktionen arbeiten dann mit den Regeln weiter.")
            }

            Section {
                AssistantFeatureRow(symbol: "text.magnifyingglass", title: "Suche in Worten",
                                    detail: "„nächste Woche Freitag nach Innsbruck“ füllt den Planer aus. Du prüfst und suchst dann.",
                                    fallback: "Ohne KI erkennen die Regeln Ort, Tag, Uhrzeit und Rückfahrt.")
                AssistantFeatureRow(symbol: "chart.line.uptrend.xyaxis", title: "Warum lohnt sich mein Ticket?",
                                    detail: "Erklärt die Bilanz auf der Übersicht mit deinen eigenen Zahlen.",
                                    fallback: "Ohne KI steht der Regeltext mit denselben Zahlen da.")
                AssistantFeatureRow(symbol: "calendar.badge.clock", title: "Wochenrückblick",
                                    detail: "Ein kurzer Satz für die Sonntags-Mitteilung.",
                                    fallback: "Ohne KI steht der Rückblick aus den Regeln in der Mitteilung.")
                AssistantFeatureRow(symbol: "clock.arrow.circlepath", title: "Strecken zur üblichen Zeit",
                                    detail: "Schlägt eine Strecke vor, die du um diese Uhrzeit oft fährst.",
                                    fallback: "Die Auswahl kommt immer aus den Regeln, die KI formuliert nur.")
            } header: {
                SetSectionHeader(title: "Was die KI tut")
            } footer: {
                SetFooter(text: "Die KI erfindet keine Zeiten, Preise oder Zahlen. Jede Zahl in einem Text wird gegen deine Daten geprüft. Passt etwas nicht, zeigt KlimaBilanz den Regeltext.")
            }

            Section {
                Text("Nichts verlässt dein Gerät. Das Modell läuft lokal. KlimaBilanz schickt keine Fahrtdaten an einen Server und speichert keine Texte der KI. Im Hintergrund läuft keine KI-Anfrage.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "Datenschutz")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .navigationTitle("KI auf dem Gerät")
        .navigationBarTitleDisplayMode(.inline)
        .task { assistant.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the iOS Settings app: Apple Intelligence may have been switched on in the meantime.
            if phase == .active { assistant.refresh() }
        }
    }
}

/// What the status means and what the user can do about it. The copy is shown as it is (no state is hidden).
struct AssistantStatusCard: View {
    var availability: AssistantAvailability

    var body: some View {
        let copy = AssistantStatusCopy(availability)
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: copy.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(copy.tint)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(copy.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

struct AssistantStatusCopy {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    init(_ availability: AssistantAvailability) {
        switch availability {
        case .available:
            symbol = "checkmark.seal.fill"
            tint = Theme.positive
            title = "Bereit auf deinem Gerät"
            detail = "Die KI formuliert Texte lokal. Nichts verlässt dein Gerät."
        case .notEnabled:
            symbol = "exclamationmark.circle.fill"
            tint = Theme.remaining
            title = "Apple Intelligence ist aus"
            detail = "Schalte sie unter Einstellungen › Apple Intelligence & Siri ein. Bis dahin arbeiten alle Funktionen mit Regeln."
        case .unsupportedDevice:
            symbol = "iphone.slash"
            tint = Theme.textSecondary
            title = "Dieses Gerät kann das Modell nicht ausführen"
            detail = "Das Modell braucht ein iPhone mit Apple Intelligence und iOS 26. Alle Funktionen arbeiten mit Regeln."
        case .languageUnsupported:
            symbol = "character.bubble"
            tint = Theme.remaining
            title = "Deutsch wird vom Modell nicht unterstützt"
            detail = "Die Texte kommen aus den Regeln, mit denselben Zahlen."
        case .modelNotReady:
            symbol = "arrow.down.circle"
            tint = Theme.accent
            title = "Das Modell wird noch vorbereitet"
            detail = "Das dauert manchmal eine Weile. Bis dahin arbeiten die Regeln."
        case .switchedOff:
            symbol = "pause.circle.fill"
            tint = Theme.textSecondary
            title = "In KlimaBilanz ausgeschaltet"
            detail = "Die KI wird nicht gefragt. Die Regeln arbeiten weiter."
        }
    }
}

private struct AssistantFeatureRow: View {
    var symbol: String
    var title: String
    var detail: String
    var fallback: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(fallback)
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .listRowBackground(Theme.surface)
        .accessibilityElement(children: .combine)
    }
}
