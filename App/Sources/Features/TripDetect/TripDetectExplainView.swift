import SwiftUI
import KlimaCore

// MARK: tripdetect – the explanation screen of "Hintergrund-Erkennung (Beta)" (docs/TRIP_DETECTION.md §6). It says what happens,
// exactly what is stored and for how long, what never happens and where it fails. The feature is switched on only from here,
// and the location permission is asked only after "Verstanden, einschalten".

struct TripDetectExplainView: View {
    /// "Verstanden, einschalten" – the caller switches the feature on (and asks for the permission).
    var onEnable: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    hero.reveal(.focus, order: 0)
                    block(symbol: "sparkles", tint: Theme.glacier, title: "Was KlimaBilanz tut",
                          lines: ["Es merkt grob, wo du dich aufhältst – an welchen Bahnhöfen du wartest und wann du dich weit wegbewegst.",
                                  "Passt das zusammen (Start und Ziel nahe einer Haltestelle, mindestens 5 km, Zugtempo, Aufenthalt an beiden Enden), liegt in der Übersicht ein Fahrten-Vorschlag.",
                                  "Der Vorschlag trägt ein Etikett: Vielleicht, Wahrscheinlich oder Sicher."])
                        .reveal(order: 1)
                    block(symbol: "internaldrive.fill", tint: Theme.pine, title: "Was gespeichert wird – und wie lange",
                          lines: ["Grobe Standortpunkte (Mobilfunk-Ebene, Hunderte Meter genau), Aufenthalte und das Betreten und Verlassen deiner häufigsten Bahnhöfe.",
                                  "Nur auf diesem iPhone, höchstens 36 Stunden. Danach löscht KlimaBilanz sie von selbst.",
                                  "Sofort weg: wenn du einen Vorschlag übernimmst oder verwirfst (die Punkte dieser Fahrt), wenn du die Erkennung ausschaltest und mit „Alle Standortdaten löschen“.",
                                  "Nicht im Export, nicht im Backup, nicht in der Cloud-Synchronisierung."])
                        .reveal(order: 2)
                    block(symbol: "hand.raised.fill", tint: Theme.dusk, title: "Was nie passiert",
                          lines: ["Es wird nie eine Fahrt ohne dein Okay erfasst. Jeder Vorschlag fragt dich: Übernehmen, Bearbeiten oder Verwerfen.",
                                  "Dein Standort verlässt das iPhone nicht. Nur wenn du Live-Daten erlaubt hast, fragt KlimaBilanz je Vorschlag einmal den Fahrplan, ob zwischen den beiden Bahnhöfen zu dieser Zeit ein Zug fuhr – mit zwei Haltestellennamen und der Uhrzeit, ohne Koordinaten.",
                                  "Kein Tracking, keine Werbung."])
                        .reveal(order: 3)
                    block(symbol: "exclamationmark.triangle.fill", tint: Theme.dawn, title: "Wo es sich irren kann",
                          lines: ["Eine Autofahrt zwischen zwei Orten mit Bahnhof sieht aus Sicht der Daten oft aus wie eine Zugfahrt. Deshalb fragt die App immer – und schlägt solche Fahrten nur als „Vielleicht“ vor.",
                                  "Nicht jede Fahrt wird erkannt: iOS meldet Aufenthalte und Ortswechsel nach eigenem Ermessen. Für eine sichere Erfassung gibt es „Fahrt aufzeichnen“.",
                                  "Die Erkennung braucht den Standortzugriff „Immer“ und etwas Akku. Im Erkennungs-Protokoll siehst du, warum etwas vorgeschlagen wurde oder nicht."])
                        .reveal(order: 4)
                    Text("Beta: genaue Trefferquote und Akkuverbrauch lassen sich nur im Alltag auf dem iPhone beurteilen. Das Erkennungs-Protokoll in den Einstellungen hilft dabei.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.xxs)
                        .reveal(order: 5)
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .revealScope()
            VStack(spacing: Theme.Spacing.xs) {
                Button(action: onEnable) {
                    Label("Verstanden, einschalten", systemImage: "location.fill")
                }
                .buttonStyle(.primary)
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
            Kicker(text: "Beta", color: Theme.summitText)
            Text("Fahrten automatisch erkennen")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Du fährst, KlimaBilanz schlägt die Fahrt vor, du bestätigst – und die Ersparnis wächst ohne Eintippen.")
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
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(tint).frame(width: 5, height: 5).offset(y: -2)
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
