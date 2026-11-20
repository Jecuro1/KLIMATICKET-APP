import SwiftUI
import KlimaCore

// MARK: ai – Einstellungen: „KI auf dem Gerät“ (state, switch, what runs on the device; docs/LOCAL_AI.md)
struct SetAssistantSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Section {
            NavigationLink {
                AssistantSettingsView()
            } label: {
                SetRowLabel(title: "KI auf dem Gerät", subtitle: AssistantStatusCopy(app.assistant.availability).title,
                            symbol: "sparkles", tint: Theme.dusk)
            }
            .listRowBackground(Theme.surface)
            if SiriQuestionsRelease.isLive {   // MARK: siri – „Fragen an KlimaBilanz“: Siri und Kurzbefehle (docs/SIRI_QUESTIONS.md §6)
                NavigationLink { SiriQuestionsView() } label: {
                    SetRowLabel(title: "Fragen an KlimaBilanz", subtitle: "Siri und Kurzbefehle: Fahrten, Wert, CO₂ und dein Ticket",
                                symbol: "waveform", tint: Theme.glacier)
                }
                .listRowBackground(Theme.surface)
            }
        } header: {
            SetSectionHeader(title: SiriQuestionsRelease.isLive ? "KI & Siri" : "KI")   // MARK: siri
        }
    }
}
