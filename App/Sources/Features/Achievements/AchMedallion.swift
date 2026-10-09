import SwiftUI
import UIKit
import KlimaCore

// MARK: - Tier & formatting helpers (module-local – no extensions on shared types to avoid clashes)

/// Display helpers for achievement tiers.
enum AchTierStyle {
    /// Ascending order, used for tallies and sorting.
    static let ordered: [Achievement.Tier] = [.bronze, .silver, .gold, .platinum]

    static func rank(_ tier: Achievement.Tier) -> Int {
        switch tier {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        case .platinum: 3
        }
    }

    static func name(_ tier: Achievement.Tier) -> String {
        switch tier {
        case .bronze: "Bronze"
        case .silver: "Silber"
        case .gold: "Gold"
        case .platinum: "Platin"
        }
    }
}

/// Formatting used by the Gipfelbuch.
enum AchFormat {
    /// Progress floored to whole percent so a locked achievement never reads "100 %".
    /// The tiny tolerance keeps binary rounding from dropping a point (0.29 × 100 = 28.999… → would read "28 %").
    static func flooredFraction(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        guard clamped < 1 else { return 1 }
        return min((clamped * 100 + 1e-9).rounded(.down), 99) / 100
    }

    /// "87 %"
    static func percent(_ fraction: Double) -> String {
        Format.percent(flooredFraction(fraction))
    }

    /// Remaining share to the goal, consistent with `percent(_:)` ("13 %").
    static func remainingPercent(_ fraction: Double) -> String {
        Format.percent(max(0, 1 - flooredFraction(fraction)))
    }

    /// "2026/27" (or "2026" when the period stays within one calendar year).
    static func ticketYear(_ period: TicketPeriod) -> String {
        let calendar = Calendar.vienna
        let first = calendar.component(.year, from: period.start)
        let last = calendar.component(.year, from: period.end)
        guard first != last else { return String(first) }
        let short = last % 100
        return String(first) + "/" + (short < 10 ? "0" : "") + String(short)
    }
}

/// Resolves the SF Symbol for an achievement: no streak flame in the Gipfelbuch (DESIGN §5.6) and a safe
/// fallback should a symbol name be unknown on the running OS.
@MainActor
enum AchSymbols {
    private static var cache: [String: String] = [:]

    static func name(for achievement: Achievement) -> String {
        let original = achievement.symbolName
        if let hit = cache[original] { return hit }
        let preferred = original == "flame.fill" ? "calendar.badge.checkmark" : original
        let resolved = [preferred, original].first { UIImage(systemName: $0) != nil } ?? "rosette"
        cache[original] = resolved
        return resolved
    }
}

// MARK: - Medallion

/// Glass-metal medallion in the tier gradient. Unlocked: full colour, soft tier glow, bouncing symbol.
/// Locked: desaturated coin inside a progress ring (glacier → dusk → dawn) with a percent capsule.
/// `roll` / `pitch` (−1…1, e.g. from MotionTilt) move the specular sheen.
struct AchMedallion: View {
    var achievement: Achievement
    var size: CGFloat
    /// Ring fill for locked medallions (animatable); `nil` = the achievement's progress.
    var ringProgress: Double? = nil
    var roll: Double = 0
    var pitch: Double = 0
    /// Increment to bounce the symbol of an unlocked medallion.
    var bounceTick: Int = 0
    var showsPercentBadge: Bool = true
    var showsGlow: Bool = true

    private var tier: Achievement.Tier { achievement.tier }
    private var isUnlocked: Bool { achievement.isUnlocked }
    private var lineWidth: CGFloat { max(2.5, size * 0.05) }
    private var ringGap: CGFloat { max(3, size * 0.06) }
    /// Outer frame – identical for locked and unlocked so grids stay aligned.
    var outerSize: CGFloat { size + 2 * (ringGap + lineWidth) }

    var body: some View {
        ZStack {
            if isUnlocked && showsGlow { glow }
            if !isUnlocked { ring }
            coin
            if !isUnlocked && showsPercentBadge {
                percentBadge
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: lineWidth * 0.9)
            }
        }
        .frame(width: outerSize, height: outerSize)
    }

    // MARK: Layers

    private var glow: some View {
        Circle()
            .fill(Theme.tierGradient(tier))
            .frame(width: size * 0.9, height: size * 0.9)
            .blur(radius: size * 0.16)
            .opacity(0.55)
            .offset(y: size * 0.07)
    }

    private var ring: some View {
        let progress = min(max(ringProgress ?? achievement.progress, 0), 1)
        return ZStack {
            Circle()
                .stroke(Theme.textTertiary.opacity(0.22), lineWidth: lineWidth)
            // Gradient spans the filled arc only (like ProgressRail): with a full-turn conic gradient the round
            // start cap (just "before" 0°) would pick up the dawn end colour.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [Theme.glacier, Theme.dusk, Theme.dawn], center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
        }
        .padding(lineWidth / 2)
    }

    private var coin: some View {
        ZStack {
            coinBody
                .saturation(isUnlocked ? 1 : 0)
                .opacity(isUnlocked ? 1 : 0.5)
            symbol
        }
        .frame(width: size, height: size)
    }

    private var coinBody: some View {
        let inset = size * 0.075
        return ZStack {
            // Rim
            Circle().fill(Theme.tierGradient(tier))
            // Face with the gradient reversed → bevel
            Circle()
                .fill(Theme.tierGradient(tier))
                .rotationEffect(.degrees(180))
                .padding(inset)
            Circle()
                .fill(Color.black.opacity(0.08))
                .padding(inset)
            // Engraved inner line
            Circle()
                .strokeBorder(Color.white.opacity(0.42), lineWidth: max(0.75, size * 0.012))
                .padding(size * 0.13)
            gloss
            sheen
            // Specular rim + hairline for light backgrounds
            Circle().strokeBorder(rimLight, lineWidth: max(1, size * 0.018))
            Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(isUnlocked ? 0.24 : 0.1), radius: size * 0.07, y: size * 0.05)
    }

    private var gloss: some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
            .frame(width: size * 0.74, height: size * 0.42)
            .offset(y: -size * 0.21)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }

    private var sheen: some View {
        LinearGradient(
            stops: [.init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0), location: 0.3),
                    .init(color: .white.opacity(0.6), location: 0.46),
                    .init(color: .white.opacity(0), location: 0.62),
                    .init(color: .white.opacity(0), location: 1)],
            startPoint: UnitPoint(x: -0.1 - roll * 0.6, y: -0.1 - pitch * 0.45),
            endPoint: UnitPoint(x: 1.1 - roll * 0.6, y: 1.1 - pitch * 0.45))
            .blendMode(.overlay)
            .clipShape(Circle())
    }

    private var rimLight: LinearGradient {
        LinearGradient(stops: [.init(color: .white.opacity(0.95), location: 0),
                               .init(color: .white.opacity(0.15), location: 0.45),
                               .init(color: .white.opacity(0.55), location: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var symbol: some View {
        Image(systemName: AchSymbols.name(for: achievement))
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(isUnlocked ? Color.white : Theme.textSecondary)
            .shadow(color: Color.black.opacity(isUnlocked ? 0.3 : 0), radius: max(0.5, size * 0.015), y: size * 0.012)
            .symbolEffect(.bounce, value: isUnlocked ? bounceTick : 0)
    }

    private var percentBadge: some View {
        Text(AchFormat.percent(achievement.progress))
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.sheetBackground))
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
            .fixedSize()
    }
}

/// Small tier coin (tallies, stat rows).
struct AchTierCoin: View {
    var tier: Achievement.Tier
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(Theme.tierGradient(tier))
            Circle()
                .fill(Theme.tierGradient(tier))
                .rotationEffect(.degrees(180))
                .padding(size * 0.14)
            Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: max(0.75, size * 0.06))
            Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.15), radius: size * 0.12, y: size * 0.06)
        .accessibilityHidden(true)
    }
}
