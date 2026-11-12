import SwiftUI
import KlimaCore

/// The screen as a sheet with its own navigation bar (onboarding, the empty Ticket tab, Statistik, the deep link).
struct WhatIfSheet: View {
    var launch: WhatIfLaunch = .automatic

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WhatIfView(launch: launch)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}

/// Any label that opens „Was wäre wenn?“ as a sheet.
struct WhatIfSheetLink<Content: View>: View {
    @ViewBuilder var label: Content
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label
        }
        .sheet(isPresented: $isPresented) {
            WhatIfSheet()
        }
        .accessibilityHint("Öffnet die Rechenhilfe „Was wäre wenn?“")
    }
}

/// The row in the Ticket-Ratgeber: pushes the screen.
struct WhatIfEntryRow: View {
    var body: some View {
        NavigationLink {
            WhatIfView()
        } label: {
            GlassCard(padding: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    TktIconTile(symbol: "slider.horizontal.3", color: Theme.glacier, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Was wäre wenn?")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Mehr oder weniger fahren, andere Strecken – welches Ticket lohnt sich?")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.pressableCard)
    }
}

/// A quiet text link for a card footer ("Was wäre, wenn du mehr oder weniger fährst?") that opens the sheet.
struct WhatIfInlineLink: View {
    var title: String

    var body: some View {
        WhatIfSheetLink {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.accentText)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
