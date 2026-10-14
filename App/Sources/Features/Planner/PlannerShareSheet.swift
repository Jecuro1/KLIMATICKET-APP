import SwiftUI
import UIKit
import KlimaCore

/// The link of a connection: the search as `klimabilanz://plan?…` (`PlannerLink`). Stations go by their id, other places by
/// name, via stops in travel order, the departure as the time of the search.
enum PlannerShare {
    static func link(for journey: Journey, vias: [ViaStop]) -> PlannerLink? {
        guard let from = journey.origin, let to = journey.destination else { return nil }
        return PlannerLink(from: placeKey(from), to: placeKey(to), vias: vias.map { placeKey($0.location) },
                           at: journey.departure?.effective, isArrival: false)
    }

    /// `uic:<extId>` for a station (the id of the offline station index), else the name the planner can search again.
    static func placeKey(_ location: Location) -> String {
        if location.kind == .station, let extId = location.extId { return "uic:\(extId)" }
        return DisplayNames.name(location.name)
    }
}

/// „Teilen“ of a connection (docs/PLANNER.md §Teilen): the text as Messages and Mail show it, the link that opens the search in
/// KlimaBilanz, and a copy of the link. Nothing is sent by the app itself; the share sheet of iOS does that.
struct PlannerShareSheet: View {
    let journey: Journey
    let link: PlannerLink?

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let text = PlannerExport.shareText(journey)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(text)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.m)
                        .frostedCard(cornerRadius: Theme.Radius.card)
                    ShareLink(item: text) {
                        Label("Text teilen", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glass)
                    if let url = link?.url {
                        ShareLink(item: url) {
                            Label("Link teilen", systemImage: "link")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.glass)
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            copied = true
                        } label: {
                            Label(copied ? "Link kopiert" : "Link kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glass)
                        .haptic(.tap, trigger: copied)
                        Text("Der Link öffnet diese Verbindung in KlimaBilanz: Haltestellen, Zwischenhalte und Abfahrt. Er enthält keine persönlichen Daten.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Theme.Spacing.cardGutter)
            }
            .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.4) }
            .navigationTitle("Teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.fontWeight(.semibold) } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.sheetBackground)
    }
}
