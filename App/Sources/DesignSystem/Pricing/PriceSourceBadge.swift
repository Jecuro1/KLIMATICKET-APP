import SwiftUI
import KlimaCore

/// Where a price comes from, always in plain words (docs/OEBB_LIVE.md §E5, UX §4.7): „Live-Preis · ÖBB“, „Tarif-Tabelle“,
/// „Schätzung“, „Angepasst“, „Live-Preis wird abgefragt …“, „Offline · Tarif-Tabelle“. A price the user typed is
/// „Angepasst“ and is never replaced by a live one.
struct PriceSourceBadge: View {
    enum Source: Equatable {
        /// Live from a provider ("ÖBB", "VVT", "VOR" …).
        case live(String)
        /// Official fare table (offline) or the tariff catalog's city ticket.
        case table
        /// Distance model.
        case estimate
        /// Entered or changed by the user.
        case edited
        /// A live quote is on its way.
        case loading
        /// Offline: the table price stands in until the network is back.
        case offline
    }

    enum Style { case tag, regular }

    var source: Source
    var style: Style = .regular

    var body: some View {
        HStack(spacing: 4) {
            if source == .loading {
                ProgressView().controlSize(.mini)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: style == .tag ? 9 : 11, weight: .bold))
            }
            Text(title)
                .font(.system(size: style == .tag ? 10.5 : 12.5, weight: .bold, design: .rounded))
                .tracking(style == .tag ? 0.4 : 0)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, style == .tag ? 6 : 9)
        .padding(.vertical, style == .tag ? 2.5 : 4)
        .background(tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    var title: String {
        switch (source, style) {
        case (.live, .tag): "LIVE"
        case (.live(let p), .regular): p.isEmpty ? "Live-Preis" : "Live-Preis · \(p)"
        case (.table, _): "Tarif-Tabelle"
        case (.estimate, _): "Schätzung"
        case (.edited, _): "Angepasst"
        case (.loading, .tag): "…"
        case (.loading, .regular): "Live-Preis wird abgefragt …"
        case (.offline, .tag): "OFFLINE"
        case (.offline, .regular): "Offline · Tarif-Tabelle"
        }
    }

    private var spoken: String {
        switch source {
        case .live(let p): p.isEmpty ? "Live-Preis" : "Live-Preis von \(p)"
        case .table: "Preis aus der Tarif-Tabelle"
        case .estimate: "Geschätzter Preis"
        case .edited: "Von dir angepasster Preis"
        case .loading: "Live-Preis wird abgefragt"
        case .offline: "Offline, Preis aus der Tarif-Tabelle"
        }
    }

    private var symbol: String? {
        switch source {
        case .live: "checkmark.seal.fill"
        case .table: "tablecells"
        case .estimate: "ruler"
        case .edited: "pencil"
        case .loading: nil
        case .offline: "wifi.slash"
        }
    }

    private var tint: Color {
        switch source {
        case .live: Theme.positiveText
        case .table: Theme.accentText
        case .estimate, .offline: Theme.textSecondary
        case .edited: Theme.summitText
        case .loading: Theme.textSecondary
        }
    }
}

extension PriceSourceBadge.Source {
    /// The badge for a resolved quote. `offline` marks a table price shown because the network is unavailable.
    init(quote: PriceQuote, offline: Bool = false) {
        switch quote.source {
        case .liveOebb: self = .live(quote.provider ?? "ÖBB")
        case .liveVerbund: self = .live(quote.provider ?? "VAO")
        case .table, .cityTicket: self = offline ? .offline : .table
        case .distanceModel: self = .estimate
        case .manual: self = .edited
        }
    }
}
