import SwiftUI
import UIKit
import KlimaCore

/// Über KlimaBilanz: FAQ, data sources, privacy, disclaimer, feedback.
/// The centred brand footer (`SetBrandFooterSection`) closes the list after the sign-out section.
struct SetAboutSection: View {
    var body: some View {
        Section {
            Group {
                NavigationLink {
                    SetFAQPage()
                } label: {
                    SetRowLabel(title: "Häufige Fragen", symbol: "questionmark.bubble.fill", tint: Theme.glacier)
                }
                NavigationLink {
                    SetSourcesPage()
                } label: {
                    SetRowLabel(title: "Datenquellen", symbol: "books.vertical.fill", tint: Theme.modeColor(.sBahn))
                }
                NavigationLink {
                    SetInfoPage(title: "Datenschutz", kicker: "Deine Daten gehören dir", symbol: "hand.raised.fill",
                                tint: Theme.pine, text: Copy.privacy)
                } label: {
                    SetRowLabel(title: "Datenschutz", symbol: "hand.raised.fill", tint: Theme.pine)
                }
                NavigationLink {
                    SetInfoPage(title: "Hinweis", kicker: "Unabhängiges Projekt", symbol: "info.circle.fill",
                                tint: Theme.dusk, text: Copy.disclaimer)
                } label: {
                    SetRowLabel(title: "Hinweis", symbol: "info.circle.fill", tint: Theme.dusk)
                }
                if let url = SetAboutSection.feedbackURL {
                    Link(destination: url) {
                        SetRowLabel(title: "Feedback senden", subtitle: "Ideen, Fehler oder Lob – immer her damit",
                                    symbol: "envelope.fill", tint: Theme.dawn)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Über KlimaBilanz")
        }
    }

    /// Recipient for feedback mails (empty = the user picks one in Mail). See report › shared_requests.
    static let feedbackRecipient = ""

    /// mailto: link with subject and device info prefilled.
    static var feedbackURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackRecipient
        let device = "KlimaBilanz \(AppConfig.appVersion) (\(AppConfig.buildNumber)) · iOS \(UIDevice.current.systemVersion)"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Feedback zu KlimaBilanz"),
            URLQueryItem(name: "body", value: "\n\n\n—\n\(device)"),
        ]
        return components.url
    }
}

/// Borderless last section of the settings list with the brand footer.
struct SetBrandFooterSection: View {
    var body: some View {
        Section {
            SetBrandFooter()
                .id(SetScrollAnchor.end)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

/// Centred app icon, name, version and tagline at the end of the settings list.
private struct SetBrandFooter: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            SetAppIconView(size: 64)
                .padding(.bottom, Theme.Spacing.xxs)
            Text("KlimaBilanz")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Version \(AppConfig.appVersion) (Build \(AppConfig.buildNumber))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            // textSecondary: the tertiary grey stays below 4.5 : 1 for footnote text on the pale sky.
            Text(Copy.tagline)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - FAQ

private struct SetFAQPage: View {
    @State private var expanded: Set<Int> = [0]

    var body: some View {
        List {
            Section {
                Group {
                    ForEach(Array(Copy.faq.enumerated()), id: \.offset) { index, item in
                        DisclosureGroup(isExpanded: binding(for: index)) {
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 2)
                        } label: {
                            Text(item.question)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            } footer: {
                SetFooter(text: "Deine Frage ist nicht dabei? Schreib uns über „Feedback senden“.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4, fadeEnd: 0.4) }
        .navigationTitle("Häufige Fragen")
        .navigationBarTitleDisplayMode(.large)
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(index) },
            set: { isOpen in
                if isOpen { expanded.insert(index) } else { expanded.remove(index) }
            }
        )
    }
}

// MARK: - Data sources

private struct SetSourcesPage: View {
    @Environment(AppState.self) private var app

    var body: some View {
        List {
            Section {
                Group {
                    ForEach(Array(Copy.dataSources.enumerated()), id: \.offset) { _, source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(source.detail)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(Theme.surface)
            } footer: {
                SetFooter(text: "Tarif-Version \(app.catalog.version). Alle Preise und Schätzungen ohne Gewähr – maßgeblich sind die offiziellen Tarife.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4, fadeEnd: 0.4) }
        .navigationTitle("Datenquellen")
        .navigationBarTitleDisplayMode(.large)
    }
}
