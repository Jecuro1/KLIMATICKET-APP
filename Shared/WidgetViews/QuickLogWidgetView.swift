import SwiftUI
import WidgetKit
import KlimaCore

/// "Schnellerfassung": interactive favourite buttons (systemSmall: 2, systemMedium: up to 4).
/// One tap runs `LogFavoriteTripIntent` – the trip is queued for the app and the snapshot updates optimistically.
struct QuickLogWidgetView: View {
    var snapshot: WidgetSnapshot?
    var family: WidgetFamily
    var margins: EdgeInsets = WidLayout.defaultMargins
    /// False in the in-app gallery: buttons are shown but do not log anything.
    var isInteractive: Bool = true

    var body: some View {
        if let snapshot {
            if family == .systemSmall {
                WidQuickLogSmall(snapshot: snapshot, margins: margins, isInteractive: isInteractive)
            } else {
                WidQuickLogMedium(snapshot: snapshot, margins: margins, isInteractive: isInteractive)
            }
        } else {
            WidEmptyView(family: family, margins: margins)
        }
    }
}

// MARK: - Small

private struct WidQuickLogSmall: View {
    let snapshot: WidgetSnapshot
    let margins: EdgeInsets
    let isInteractive: Bool

    /// No ridge here: two buttons and the progress footer fill the whole tile, so any ridge line would run
    /// through the bar and the "75 %" – the summit glow of the sky carries the brand instead.
    var body: some View {
        let favorites = Array(snapshot.favorites.prefix(2))
        VStack(alignment: .leading, spacing: 5) {
            WidEyebrow(text: "Schnell erfassen", symbol: "bolt.fill", tint: Theme.gold)
            if favorites.isEmpty {
                WidNoFavoritesHint(compact: true)
            } else {
                ForEach(favorites) { favorite in
                    WidFavoriteButton(favorite: favorite, isInteractive: isInteractive)
                }
            }
            Spacer(minLength: 0)
            WidProgressFooter(snapshot: snapshot)
        }
        .padding(margins)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium

private struct WidQuickLogMedium: View {
    let snapshot: WidgetSnapshot
    let margins: EdgeInsets
    let isInteractive: Bool

    private var rows: [[WidgetSnapshot.Favorite]] {
        let favorites = Array(snapshot.favorites.prefix(4))
        return stride(from: 0, to: favorites.count, by: 2).map { start in
            Array(favorites[start..<min(start + 2, favorites.count)])
        }
    }

    var body: some View {
        let grid = self.rows
        let showsFooter = grid.count < 2
        ZStack(alignment: .topLeading) {
            // Two rows: a low horizon below the buttons (its rim would show through the capsules).
            // One row + footer: the ridge rises between them and dissolves into mist before it reaches the bar.
            WidSummitArt(model: .decorative, top: showsFooter ? 0.6 : 0.76, bottom: 1, scale: 0.9, showsRoute: false,
                         ridgeOpacity: 0.5, showsFlag: false,
                         mistFrom: showsFooter ? 0.66 : 0.86, mistTo: showsFooter ? 0.8 : 1, mistOpacity: showsFooter ? 0 : 0.35)
            VStack(alignment: .leading, spacing: 8) {
                header
                if grid.isEmpty {
                    WidNoFavoritesHint(compact: false)
                } else {
                    ForEach(grid.indices, id: \.self) { index in
                        row(grid[index])
                    }
                }
                Spacer(minLength: 0)
                if showsFooter {
                    WidProgressFooter(snapshot: snapshot)
                }
            }
            .padding(margins)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            WidEyebrow(text: "Schnell erfassen", symbol: "bolt.fill", tint: Theme.gold)
            Spacer(minLength: 4)
            WidMiniRing(fraction: snapshot.amortizedFraction)
            if !WidInsight.isPaidOff(snapshot) {
                Text("noch \(WidFormat.euroWhole(snapshot.remaining))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.widSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func row(_ favorites: [WidgetSnapshot.Favorite]) -> some View {
        HStack(spacing: 8) {
            ForEach(favorites) { favorite in
                WidFavoriteButton(favorite: favorite, isInteractive: isInteractive)
            }
            if favorites.count == 1 {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }
}

// MARK: - Hint

/// No favourites yet: points to the app (the widget URL opens "Fahrt erfassen").
private struct WidNoFavoritesHint: View {
    let compact: Bool

    private var message: String {
        compact ? "Speichere Strecken in der App." : "Speichere oft gefahrene Strecken in der App – dann erfasst du sie hier mit einem Tipp."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 2) {
                Text("Noch keine Favoriten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(compact ? 3 : 2)
                    .minimumScaleFactor(0.85)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
