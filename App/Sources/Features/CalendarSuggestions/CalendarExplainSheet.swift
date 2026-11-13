import SwiftUI
import KlimaCore

// MARK: calendarsuggestions – the explanation before the system question (docs/CALENDAR_SUGGESTIONS.md §2, consent): what is read, what
// never happens, where it can be wrong. iOS asks for calendar access only after „Verstanden, weiter“ – never at launch, never in
// the onboarding.

struct CalendarExplainSheet: View {
    var onContinue: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    hero.reveal(.focus, order: 0)
                    block(symbol: "calendar.badge.checkmark", tint: Theme.glacier, title: "Was KlimaBilanz tut",
                          lines: ["Es schaut in die nächsten 14 Tage der Kalender, die du auswählst.",
                                  "Steht bei einem Termin ein Bahnhof oder eine Stadt mit Hauptbahnhof, liegt in der Übersicht ein Vorschlag: Ankunft 20 Minuten vor Beginn, mit einem Tipp in den Fahrplan.",
                                  "Am Tag danach fragt es, ob du gefahren bist – erfasst wird nur, was du bestätigst."])
                        .reveal(order: 1)
                    block(symbol: "lock.fill", tint: Theme.pine, title: "Was gelesen und was gespeichert wird",
                          lines: ["Wir lesen nur Titel, Ort und Zeit deiner Termine, nur auf diesem iPhone, nur während die App offen ist.",
                                  "Gespeichert werden keine Titel und keine Orte. Für „Kein Zug“ merkt sich die App nur einen Prüfwert des Termins, höchstens 60 Tage.",
                                  "Nichts davon geht an einen Server, in eine KI, in eine Statistik oder in die Cloud-Synchronisierung."])
                        .reveal(order: 2)
                    block(symbol: "tram.fill", tint: Theme.dusk, title: "Wann die ÖBB gefragt werden",
                          lines: ["Erst wenn du bei einem Vorschlag „Verbindung suchen“ tippst – und nur, wenn du Live-Daten erlaubt hast. Dann gehen zwei Bahnhöfe und eine Uhrzeit an die ÖBB-Fahrplanauskunft, nie der Termin."])
                        .reveal(order: 3)
                    block(symbol: "exclamationmark.triangle.fill", tint: Theme.dawn, title: "Wo es sich irren kann",
                          lines: ["Lieber kein Vorschlag als ein falscher: Nur eindeutige Bahnhofsnamen zählen. Eine Adresse allein, „Zoom“ oder „Büro“ bringen nichts.",
                                  "Steht nur eine Stadt im Termin, nimmt die App ihren Hauptbahnhof und schreibt „ungefähr“ dazu."])
                        .reveal(order: 4)
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .revealScope()
            VStack(spacing: Theme.Spacing.xs) {
                Button(action: onContinue) {
                    Label("Verstanden, weiter", systemImage: "calendar")
                }
                .buttonStyle(.primary)
                Text("Danach fragt iOS, ob KlimaBilanz deine Kalender lesen darf.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Nicht jetzt", action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xs)
            .background(.bar)
        }
        .background { Theme.sheetBackground.ignoresSafeArea() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            CalendarHeroGlyph()
                .padding(.bottom, Theme.Spacing.xxs)
            Kicker(text: "Nur auf diesem iPhone", color: Theme.positiveText)
            Text("Kalender-Vorschläge")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Dein Termin in Salzburg, dein Zug dorthin: Die App schlägt die Fahrt vor, du entscheidest.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func block(symbol: String, tint: Color, title: String, lines: [String]) -> some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    SetIconTile(symbol: symbol, tint: tint, size: 28)
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(tint).frame(width: 5, height: 5).offset(y: -2).accessibilityHidden(true)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A calendar sheet with a train leaving it – the feature's emblem on the explanation and the settings page.
struct CalendarHeroGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "calendar")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.ctaGradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 6)
            Image(systemName: "tram.fill")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 0.44, height: size * 0.44)
                .background(Theme.dawn, in: .circle)
                .overlay(Circle().strokeBorder(Theme.snow, lineWidth: 2.5))
                .offset(x: size * 0.14, y: size * 0.12)
        }
        .padding(.trailing, size * 0.14)
        .padding(.bottom, size * 0.12)
        .accessibilityHidden(true)
    }
}
