import SwiftUI
import KlimaCore

/// Own large header (not the nav-bar title): eyebrow "FREITAG, 9. OKTOBER" over "Übersicht".
struct DashHeader: View {
    var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: DashStyle.longDate(date))
            Text(AppTab.overview.title)
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Glass capsule "🎫 KlimaTicket Ö Klassik · noch 143 Tage" – switches to the Ticket tab.
struct DashTicketPill: View {
    var ticketName: String
    var status: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    icon
                    name
                    Circle()
                        .fill(Theme.textTertiary)
                        .frame(width: 3, height: 3)
                    statusText
                }
                HStack(spacing: Theme.Spacing.xs) {
                    icon
                    VStack(alignment: .leading, spacing: 1) {
                        name
                        statusText
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("\(ticketName), \(status)")
        .accessibilityHint("Zeigt dein Ticket")
    }

    private var icon: some View {
        Image(systemName: "ticket.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
    }

    private var name: some View {
        Text(ticketName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
    }

    private var statusText: some View {
        Text(status)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}

/// Optional glass capsule "Neue Version 1.1.0 verfügbar" (DESIGN.md §5.7) – opens the update sheet.
struct DashUpdateCapsule: View {
    var version: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Neue Version \(version) verfügbar", systemImage: "arrow.down.circle.fill")
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(Theme.accent)
    }
}
