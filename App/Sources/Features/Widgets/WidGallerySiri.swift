import SwiftUI
import WidgetKit
import KlimaCore

/// "Siri & Kurzbefehle": the phrases that work out of the box (KlimaBilanzShortcuts) and what Siri answers – the real
/// snippet views of the intents (`WidBalanceSnippet`, `WidLoggedSnippet`) on a Siri-like platter. Tapping a phrase
/// shows its answer; the selection glides between the phrases.
struct WidSiriSection: View {
    let snapshot: WidgetSnapshot

    @State private var phrase: WidSiriPhrase = .balance
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "Siri & Kurzbefehle",
                          caption: "Frag einfach – ohne die App zu öffnen. Alle Aktionen findest du auch in der Kurzbefehle-App.")
            GlassCard(padding: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    VStack(spacing: 4) {
                        ForEach(WidSiriPhrase.allCases) { item in
                            phraseRow(item)
                        }
                    }
                    answer
                        .id(phrase)
                        .motionTransition(.rise)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
        }
        .haptic(.selection, trigger: phrase)
    }

    private var favoriteTitle: String { snapshot.favorites.first?.title ?? "Pendeln" }

    private func phraseRow(_ item: WidSiriPhrase) -> some View {
        let isSelected = item == phrase
        return Button {
            guard item != phrase else { return }
            withMotion(Motion.snappy) { phrase = item }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Image(systemName: item.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("„\(item.text(favorite: favoriteTitle))“")
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 0.8)
                        }
                        .matchedGeometryEffect(id: "phrase", in: selection)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(item.text(favorite: favoriteTitle))
        .accessibilityHint("Zeigt die Antwort von Siri")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Siri's answer on a platter like the system's (the snippet views are the intents' own).
    @ViewBuilder
    private var answer: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .symbolRenderingMode(.hierarchical)
                Text(dialog)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            switch phrase {
            case .balance:
                WidBalanceSnippet(snapshot: snapshot)
            case .favorite:
                WidLoggedSnippet(title: favoriteTitle, favorite: snapshot.favorites.first, snapshot: snapshot)
            case .addTrip:
                openAppAnswer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(Theme.separator, lineWidth: 0.8))
        .accessibilityElement(children: .contain)
    }

    private var dialog: String {
        switch phrase {
        case .balance: IntentCopy.balance(snapshot)
        case .favorite: IntentCopy.logged(favoriteTitle, snapshot: snapshot)
        case .addTrip: "KlimaBilanz öffnet sich beim Erfassen einer neuen Fahrt."
        }
    }

    private var openAppAnswer: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.ctaGradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Fahrt erfassen")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Von, Nach und Preis – mit deinen Lieblingsfahrten als Vorschlag.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

/// The phrases shown (each one of `KlimaBilanzShortcuts`).
enum WidSiriPhrase: String, CaseIterable, Identifiable {
    case balance, favorite, addTrip

    var id: String { rawValue }

    func text(favorite: String) -> String {
        switch self {
        case .balance: "Hat sich mein KlimaTicket in KlimaBilanz gelohnt?"
        case .favorite: "\(favorite) in KlimaBilanz erfassen"
        case .addTrip: "Fahrt in KlimaBilanz erfassen"
        }
    }

    var symbol: String {
        switch self {
        case .balance: "gauge.with.needle"
        case .favorite: "star.fill"
        case .addTrip: "plus.circle.fill"
        }
    }
}
