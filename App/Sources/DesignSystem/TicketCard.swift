import SwiftUI

/// Visual themes for the ticket card (stored in TicketEntity.themeRaw).
enum TicketTheme: String, CaseIterable, Identifiable {
    case aurora, alpenglow, glacier, signal, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: "Aurora"
        case .alpenglow: "Alpenglühen"
        case .glacier: "Gletscher"
        case .signal: "Signalgelb"
        case .night: "Nacht"
        }
    }

    var colors: [Color] {
        switch self {
        case .aurora: [Color(hex: "#3B6CFF"), Color(hex: "#6A4DFF"), Color(hex: "#B05CFF")]
        case .alpenglow: [Color(hex: "#FF9A6B"), Color(hex: "#FF6F91"), Color(hex: "#8A5CFF")]
        case .glacier: [Color(hex: "#20C3B0"), Color(hex: "#2E8BFF"), Color(hex: "#3A4CC9")]
        case .signal: [Color(hex: "#FFE04A"), Color(hex: "#FFD100"), Color(hex: "#FFB800")]
        case .night: [Color(hex: "#1B2140"), Color(hex: "#2B2F5C"), Color(hex: "#0E1024")]
        }
    }

    /// Text colour on the card.
    var ink: Color { self == .signal ? Color(hex: "#111111") : .white }

    static func from(_ raw: String) -> TicketTheme { TicketTheme(rawValue: raw) ?? .aurora }
}

/// Premium pass-style ticket card with guilloché lines, perforation and a tilt-driven holographic sheen.
struct TicketCard: View {
    var title: String
    var subtitle: String
    var holder: String
    var validFrom: Date
    var validUntil: Date
    var ticketNumber: String
    var theme: TicketTheme
    /// −1…1 device tilt (MotionTilt.roll / .pitch); 0 = static.
    var roll: Double = 0
    var pitch: Double = 0

    var body: some View {
        let ink = theme.ink
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Label("KlimaBilanz", systemImage: "mountain.2.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("2. KLASSE")
                        .font(.caption.weight(.bold).monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(ink.opacity(0.7), lineWidth: 1))
                }
                Text(title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .opacity(0.85)
                Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: Theme.Spacing.s) {
                    GridRow {
                        field("INHABER:IN", holder.isEmpty ? "—" : holder)
                        field("NUMMER", ticketNumber.isEmpty ? "—" : ticketNumber)
                    }
                    GridRow {
                        field("GÜLTIG AB", Format.date(validFrom, .numeric))
                        field("GÜLTIG BIS", Format.date(validUntil, .numeric))
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.l)

            perforation(ink: ink)

            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "qrcode")
                    .font(.system(size: 34))
                    .padding(8)
                    .background(.white.opacity(theme == .signal ? 0.9 : 0.95), in: .rect(cornerRadius: 10))
                    .foregroundStyle(.black)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nur mit amtlichem Lichtbildausweis gültig")
                        .font(.caption)
                        .opacity(0.85)
                    Text("Digitale Kopie · offizielles Ticket vorzeigen")
                        .font(.caption2)
                        .opacity(0.7)
                }
                Spacer()
                hologram
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
        .foregroundStyle(ink)
        .background(background)
        .clipShape(TicketShape(notchY: nil))
        .overlay(sheen.clipShape(TicketShape(notchY: nil)).allowsHitTesting(false))
        .shadow(color: theme.colors[1].opacity(0.4), radius: 24, y: 14)
        .rotation3DEffect(.degrees(roll * 6), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(-pitch * 4), axis: (x: 1, y: 0, z: 0))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle), gültig bis \(Format.date(validUntil, .long))")
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold).monospaced()).opacity(0.7)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func perforation(ink: Color) -> some View {
        Line()
            .stroke(ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            GuillocheLines()
                .stroke(theme.ink.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var sheen: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.28), Color(hex: "#9EF3FF").opacity(0.18), Color(hex: "#FFB3F0").opacity(0.18), .clear],
            startPoint: UnitPoint(x: 0.0 + roll * 0.5, y: 0.0 + pitch * 0.3),
            endPoint: UnitPoint(x: 1.0 + roll * 0.5, y: 1.0 + pitch * 0.3)
        )
        .blendMode(.softLight)
    }

    private var hologram: some View {
        Circle()
            .fill(AngularGradient(colors: [Color(hex: "#FFB3F0"), Color(hex: "#9EF3FF"), Color(hex: "#FFF59E"), Color(hex: "#B5A8FF"), Color(hex: "#FFB3F0")],
                                  center: .center, angle: .degrees(roll * 90)))
            .frame(width: 52, height: 52)
            .overlay(Text("KB").font(.headline.weight(.heavy)).foregroundStyle(.black.opacity(0.55)))
            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// Rounded rectangle (ticket outline). `notchY` reserved for perforation notches.
struct TicketShape: Shape {
    var notchY: CGFloat?
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: Theme.Radius.card, style: .continuous)
    }
}

/// Fine wavy security lines.
struct GuillocheLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let rows = 14
        for r in 0..<rows {
            let y0 = rect.minY + rect.height * CGFloat(r) / CGFloat(rows)
            p.move(to: CGPoint(x: rect.minX, y: y0))
            var x = rect.minX
            while x <= rect.maxX {
                let y = y0 + sin((x / rect.width) * .pi * 4 + CGFloat(r) * 0.6) * 9
                p.addLine(to: CGPoint(x: x, y: y))
                x += 6
            }
        }
        return p
    }
}
