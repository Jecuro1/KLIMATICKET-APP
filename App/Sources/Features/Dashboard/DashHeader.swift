import SwiftUI
import KlimaCore

/// Own large header – the navigation bar is hidden on the Übersicht (spec §9.2, mock 01):
/// tappable eyebrow "KLIMATICKET Ö KLASSIK · NOCH 142 TAGE" (→ Ticket tab) over "Übersicht", the account avatar trailing.
struct DashHeader: View {
    var eyebrow: String
    /// Shorter eyebrow used when the full one does not fit next to the avatar ("Klassik · noch 142 Tage").
    var compactEyebrow: String? = nil
    var onEyebrow: (() -> Void)? = nil
    var avatarInitials: String?
    var isSignedIn: Bool
    var hasUpdate: Bool = false
    var onAvatar: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                eyebrowView
                Text(AppTab.overview.title)
                    .font(Theme.Typography.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DashAvatarButton(initials: avatarInitials, isSignedIn: isSignedIn, hasUpdate: hasUpdate, action: onAvatar)
        }
    }

    @ViewBuilder
    private var eyebrowView: some View {
        if let onEyebrow {
            Button(action: onEyebrow) {
                HStack(spacing: 5) {
                    eyebrowText
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                // Generous hit area without changing the layout (the eyebrow line itself is only ~15 pt tall).
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(DashPressableStyle())
            .padding(.vertical, -10)
            .accessibilityLabel(eyebrow)
            .accessibilityHint("Öffnet dein Ticket")
        } else {
            eyebrowText
        }
    }

    private var eyebrowText: some View {
        ViewThatFits(in: .horizontal) {
            Kicker(text: eyebrow)
            if let compactEyebrow {
                Kicker(text: compactEyebrow)
            }
            Kicker(text: compactEyebrow ?? eyebrow)
                .lineLimit(1)
        }
    }
}

/// 44 pt glass circle with the account initials on the brand gradient (same recipe as the Einstellungen avatar),
/// a dawn dot when an update is available. Opens Einstellungen.
struct DashAvatarButton: View {
    var initials: String?
    var isSignedIn: Bool
    var hasUpdate: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.glacier, Theme.dusk, Theme.alpenglow],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .environment(\.colorScheme, .light)
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0)],
                                         center: .topLeading, startRadius: 0, endRadius: 38))
                if let initials {
                    Text(initials)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(4)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 38, height: 38)
            .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1) }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay(alignment: .topTrailing) {
            if hasUpdate {
                Circle()
                    .fill(Theme.dawn)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(Theme.background, lineWidth: 2) }
                    .offset(x: 2, y: -2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Einstellungen")
        .accessibilityValue(hasUpdate ? "Neue Version verfügbar" : "")
        .accessibilityHint(isSignedIn ? "Angemeldet – Konto, Bewertung und Daten" : "Konto, Bewertung und Daten")
    }

    /// "Lena Hofer" → "LH" (first letters of the first two name parts).
    static func initials(from name: String) -> String? {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? nil : letters.uppercased(with: Format.locale)
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
        .tint(Theme.accentText)
    }
}

/// Soft frosted fade under the status bar once the header has scrolled away (there is no navigation bar on this screen).
struct DashTopScrim: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 14)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
