import SwiftUI

/// „Fahrt von hier“ / „Fahrt nach hier“ (ENRICH_SPEC §3.2 item 9): open „Neue Fahrt“ prefilled with the stop.
struct StopActionBar: View {
    var onFrom: () -> Void
    var onTo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onFrom) {
                Label("Fahrt von hier", systemImage: "arrow.up.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.ctaGradient, in: .capsule)
            }
            .buttonStyle(.pressable)
            Button(action: onTo) {
                Label("Fahrt nach hier", systemImage: "mappin")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background { LinearGradient(colors: [Theme.sheetBackground.opacity(0), Theme.sheetBackground], startPoint: .top, endPoint: .center).ignoresSafeArea() }
    }
}
