import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers
import KlimaCore

/// Shareable image of the pass with the verdict ("Mein Ticket ist zu 75 % amortisiert").
/// Rendered lazily (only when the share sheet actually exports it) with `ImageRenderer`.
struct TktSharePass: Transferable {
    var face: TktCardFace
    var verdict: String
    var detail: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { pass in
            try await pass.renderPNG()
        }
        .suggestedFileName("KlimaBilanz-Ticket.png")
    }

    @MainActor
    func renderPNG() throws -> Data {
        let renderer = ImageRenderer(content: TktShareImage(face: face, verdict: verdict, detail: detail))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 420, height: nil)
        guard let data = renderer.uiImage?.pngData() else { throw TktShareError.renderFailed }
        return data
    }
}

enum TktShareError: Error {
    case renderFailed
}

/// Twilight poster: question kicker, verdict, the pass, brand line. Always dark so it looks the same everywhere.
private struct TktShareImage: View {
    var face: TktCardFace
    var verdict: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Kicker(text: Copy.tagline, color: Color.white.opacity(0.7))
                Text(verdict)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            TicketCard(title: face.title, subtitle: face.kicker, holder: face.holder,
                       validFrom: face.validFrom, validUntil: face.validUntil, ticketNumber: face.number,
                       theme: face.theme, roll: 0.35, pitch: 0.12,
                       amortizedFraction: face.amortizedFraction, valueText: face.valueText)
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "mountain.2.fill")
                Text("KlimaBilanz · Begleitkarte, kein Fahrschein")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 420)
        .background {
            ZStack {
                LinearGradient(colors: TicketTheme.night.colors, startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.dawn.opacity(0.45), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 360)
                RadialGradient(colors: [Theme.dusk.opacity(0.35), Color.clear], center: .topLeading, startRadius: 0, endRadius: 320)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
