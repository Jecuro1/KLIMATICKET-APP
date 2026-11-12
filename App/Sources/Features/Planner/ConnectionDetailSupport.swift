import SwiftUI
import KlimaCore
#if canImport(SafariServices)
import SafariServices
#endif

// Price popover, calendar file and Safari sheet of the connection detail (split from ConnectionDetailView.swift).

// MARK: - Price info popover

/// „Woher kommt der Preis?“ – the source, when it was asked, other prices found, and the rule.
struct PriceInfoPopover: View {
    var quote: PriceQuote

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            PriceSourceBadge(source: PriceSourceBadge.Source(quote: quote))
            Text(quote.explanation).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            if let fetched = quote.fetchedAt {
                Text("abgefragt \(Format.dayMonth(fetched)), \(Format.time(fetched))").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if !quote.alternatives.isEmpty {
                Divider()
                ForEach(Array(quote.alternatives.enumerated()), id: \.offset) { _, alternative in
                    Text(alternative.text).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Divider()
            Text("Normalpreis: das reguläre Einzelticket am Reisetag. Ohne Gewähr.").font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Spacing.m)
        .frame(width: 300, alignment: .leading)
    }
}

// MARK: - Calendar and shop

/// A one-event .ics file of the connection (shared through the share sheet: „In den Kalender“).
enum PlannerCalendarFile {
    /// The .ics text comes from `PlannerExport` (KlimaCore, tested); the file is written to the temporary folder.
    static func make(journey: Journey) -> URL? {
        guard let text = PlannerExport.ics(journey, uid: "\(UUID().uuidString)@klimabilanz", stamp: Date(), alarmMinutes: 10) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: PlannerExport.icsFileName(journey), directoryHint: .notDirectory)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// The ÖBB shop opens in a Safari view controller (never in-app purchase, docs/OEBB_LIVE.md §2).
struct PlannerSafariSheet: View {
    var url: URL
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if canImport(SafariServices)
        SafariRepresentable(url: url).ignoresSafeArea()
        #else
        Color.clear.onAppear { openURL(url); dismiss() }
        #endif
    }
}

#if canImport(SafariServices)
private struct SafariRepresentable: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
