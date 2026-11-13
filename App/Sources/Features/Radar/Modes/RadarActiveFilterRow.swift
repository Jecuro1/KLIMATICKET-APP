import SwiftUI
import KlimaCore

// MARK: radarmodes – an active filter is always visible on the map (it is kept per device): „Filter: RJX, RJ · nur verspätet“ and „Filter aus“.

struct RadarActiveFilterRow: View {
    var filter: RadarFilter
    var onOpen: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Theme.accentText)
                    Text(RadarModesText.activeFilter(filter))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet Filter & Darstellung")
            Button(RadarModesText.filterOff, action: onClear)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 32)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.horizontal, Theme.Spacing.cardGutter)
    }
}
