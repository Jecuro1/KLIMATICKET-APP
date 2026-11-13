import SwiftUI

// MARK: radar2 – how a part of the radar marks one vehicle marker (specs/radar2/README.md §3.1): radarmine highlights the lines you
// remembered, dims the rest while its stop panel is open and numbers the arrivals. `RadarMarker` applies it; `.plain` changes nothing.

struct RadarMarkerDecoration: Equatable {
    enum Emphasis: Equatable {
        case normal, highlighted, dimmed
    }

    enum Badge: Equatable {
        case star
        case number(Int)
    }

    var emphasis: Emphasis = .normal
    var badge: Badge?

    /// No emphasis, no badge: the marker as it always was.
    static let plain = RadarMarkerDecoration()

    /// A dimmed marker is drawn at 35 % and without its arrow: still there, but the highlighted ones lead.
    var opacity: Double { emphasis == .dimmed ? 0.35 : 1 }
    var showsArrow: Bool { emphasis != .dimmed }
}

/// The badge of a decorated marker: a gold star (a remembered line) or a number (the order of arrivals at a stop). Nothing for `.plain`.
struct RadarDecorationBadge: View {
    var decoration: RadarMarkerDecoration

    var body: some View {
        if let badge = decoration.badge {
            Group {
                switch badge {
                case .star:
                    Image(systemName: "star.fill").font(.system(size: 7, weight: .heavy))
                case .number(let n):
                    Text("\(n)").font(.system(size: 9, weight: .heavy, design: .rounded)).monospacedDigit()
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 14, minHeight: 14)
            .background(Theme.gold, in: .circle)
            .overlay(Circle().strokeBorder(Theme.snow, lineWidth: 1))
            .offset(x: 6, y: -6)
            .accessibilityHidden(true)
        }
    }
}

/// The outer glow of a highlighted marker: a soft gold halo behind the plate. Nothing unless `.highlighted`.
struct RadarDecorationHalo: View {
    var decoration: RadarMarkerDecoration

    var body: some View {
        if decoration.emphasis == .highlighted {
            Capsule()
                .strokeBorder(Theme.gold, lineWidth: 2.5)
                .padding(-4)
                .accessibilityHidden(true)
        }
    }
}
