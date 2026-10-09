import SwiftUI

/// Visual themes for the ticket card (stored in TicketEntity.themeRaw). "twilight" is the signature pass.
enum TicketTheme: String, CaseIterable, Identifiable {
    case twilight, aurora, alpenglow, glacier, signal, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twilight: "Dämmerung"
        case .aurora: "Aurora"
        case .alpenglow: "Alpenglühen"
        case .glacier: "Gletscher"
        case .signal: "Signalgelb"
        case .night: "Nacht"
        }
    }

    var colors: [Color] {
        switch self {
        case .twilight: [Color(hex: "#12284E"), Color(hex: "#1B3A70"), Color(hex: "#2C4A86")]
        case .aurora: [Color(hex: "#3B6CFF"), Color(hex: "#6A4DFF"), Color(hex: "#B05CFF")]
        case .alpenglow: [Color(hex: "#FF9A6B"), Color(hex: "#FF6F91"), Color(hex: "#8A5CFF")]
        case .glacier: [Color(hex: "#20C3B0"), Color(hex: "#2E8BFF"), Color(hex: "#3A4CC9")]
        case .signal: [Color(hex: "#FFE04A"), Color(hex: "#FFD100"), Color(hex: "#FFB800")]
        case .night: [Color(hex: "#1B2140"), Color(hex: "#2B2F5C"), Color(hex: "#0E1024")]
        }
    }

    /// Text colour on the card.
    var ink: Color { self == .signal ? Color(hex: "#111111") : .white }

    /// Unknown/empty raw values fall back to the signature twilight pass.
    static func from(_ raw: String) -> TicketTheme { TicketTheme(rawValue: raw) ?? .twilight }
}

/// Signature pass ("Begleitkarte · kein Fahrschein"): twilight gradient with radial glows, topographic contour lines,
/// iridescent foil + holo seal that follow the device tilt, perforation with real notches, and a stub showing the
/// amortisation with a mini summit. Never shows a scannable code – the official ticket stays the real document.
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
    /// Whether the user stored a photo/PDF of the real ticket.
    var hasPhoto: Bool = false
    /// Amortisation shown on the stub (nil shows the ticket number instead).
    var amortizedFraction: Double? = nil
    /// "€ 946 von € 1.400"
    var valueText: String? = nil
    /// "Original" capsule action (open photo/PDF or import). Nil hides the button.
    var onOriginal: (() -> Void)? = nil

    private let height: CGFloat = 280
    private let notchY: CGFloat = 194

    var body: some View {
        let ink = theme.ink
        let shape = TicketShape(notchY: notchY)
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 0) {
                topHalf
                    .frame(height: notchY, alignment: .topLeading)
                stub
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            perforation(ink: ink)
        }
        .foregroundStyle(ink)
        .frame(height: height)
        .clipShape(shape)
        .overlay(foil.clipShape(shape).allowsHitTesting(false))
        .overlay(
            shape.stroke(LinearGradient(stops: [.init(color: .white.opacity(0.7), location: 0), .init(color: .white.opacity(0.08), location: 0.4),
                                                .init(color: .white.opacity(0), location: 0.6), .init(color: Color(hex: "#FFBEA0").opacity(0.45), location: 1)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: Color(red: 16 / 255, green: 36 / 255, blue: 80 / 255).opacity(0.38), radius: 26, y: 22)
        .shadow(color: Color(red: 16 / 255, green: 36 / 255, blue: 80 / 255).opacity(0.18), radius: 10, y: 6)
        .rotation3DEffect(.degrees(roll * 3), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(-pitch * 2), axis: (x: 1, y: 0, z: 0))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle), Inhaber \(holder.isEmpty ? "nicht angegeben" : holder), gültig bis \(Format.date(validUntil, .long)). Begleitkarte, kein Fahrschein.")
    }

    // MARK: Parts

    private var topHalf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [Color(hex: "#3B5BDB"), Color(hex: "#F29C7B")], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: .rect(cornerRadius: 8, style: .continuous))
                Text("KlimaBilanz").font(.system(size: 15, weight: .semibold))
                Spacer()
                holoSeal
            }
            .padding(.top, 18)
            Text(subtitle.uppercased(with: Locale(identifier: "de_AT")))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .opacity(0.66)
                .lineLimit(1)
                .padding(.top, 14)
            titleText
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 3)
            HStack(alignment: .top, spacing: 26) {
                field("INHABER:IN", holder.isEmpty ? "—" : holder)
                field("GÜLTIG", "\(shortDate(validFrom)) – \(shortDate(validUntil))")
            }
            .padding(.top, 14)
        }
    }

    /// "KlimaTicket Ö" bold + trailing variant ("Klassik") light.
    private var titleText: Text {
        let variants = ["Klassik", "Jugend", "Senior", "Spezial", "Familie", "Classic"]
        if let last = title.split(separator: " ").last, variants.contains(String(last)) {
            let head = String(title.dropLast(last.count)).trimmingCharacters(in: .whitespaces)
            return Text("\(Text(head).font(.system(size: 27, weight: .bold))) \(Text(String(last)).font(.system(size: 27, weight: .light)))")
        }
        return Text(title).font(.system(size: 27, weight: .bold))
    }

    private var stub: some View {
        HStack(spacing: 12) {
            if let fraction = amortizedFraction {
                MiniSummit(progress: fraction)
                    .frame(width: 56, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Format.percent(fraction))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                        Text(fraction >= 1 ? "rentiert" : "amortisiert")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if let valueText {
                        Text(valueText)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .opacity(0.72)
                    }
                }
                .layoutPriority(1)
            } else {
                Text(ticketNumber.isEmpty ? "Begleitkarte · kein Fahrschein" : "Nr. \(ticketNumber)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(0.8)
            }
            Spacer(minLength: 4)
            if let onOriginal {
                Button(action: onOriginal) {
                    Image(systemName: hasPhoto ? "doc.text.image" : "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white.opacity(0.16)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasPhoto ? "Original-Ticket anzeigen" : "Foto des Original-Tickets hinzufügen")
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10.5, weight: .semibold)).tracking(1).opacity(0.62)
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(Format.locale))
    }

    private func perforation(ink: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 18, y: notchY))
            p.addLine(to: CGPoint(x: 2000, y: notchY))
        }
        .stroke(ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        .padding(.trailing, 18)
        .accessibilityHidden(true)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: theme.colors, startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
            if theme == .twilight || theme == .night {
                RadialGradient(colors: [Color(red: 90 / 255, green: 190 / 255, blue: 235 / 255).opacity(0.45), .clear],
                               center: UnitPoint(x: 0.1, y: 0.05), startRadius: 0, endRadius: 200)
                RadialGradient(colors: [Color(red: 150 / 255, green: 130 / 255, blue: 240 / 255).opacity(0.35), .clear],
                               center: UnitPoint(x: 0.7, y: 0.35), startRadius: 0, endRadius: 180)
                RadialGradient(colors: [Color(red: 1, green: 160 / 255, blue: 125 / 255).opacity(0.55), .clear],
                               center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 190)
            }
            TopoLines()
                .stroke(theme.ink.opacity(theme == .signal ? 0.10 : 0.14), lineWidth: 0.8)
        }
    }

    private var foil: some View {
        AngularGradient(colors: [Color(hex: "#FF9FB1"), Color(hex: "#FFD6A5"), Color(hex: "#FDFFB6"), Color(hex: "#CAFFBF"),
                                 Color(hex: "#9BF6FF"), Color(hex: "#A0C4FF"), Color(hex: "#BDB2FF"), Color(hex: "#FFC6FF"), Color(hex: "#FF9FB1")],
                        center: UnitPoint(x: 0.62, y: 0.4), angle: .degrees(210 + roll * 25))
            .blendMode(.overlay)
            .opacity(0.5)
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0.30 + roll * 0.08), .init(color: .black, location: 0.44 + roll * 0.08),
                                       .init(color: .black, location: 0.52 + roll * 0.08), .init(color: .clear, location: 0.66 + roll * 0.08)],
                               startPoint: UnitPoint(x: 0, y: 0.1 + pitch * 0.1), endPoint: UnitPoint(x: 1, y: 0.9 - pitch * 0.1))
            )
    }

    private var holoSeal: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(hex: "#FFB3F0"), Color(hex: "#9EF3FF"), Color(hex: "#FFF59E"), Color(hex: "#B5A8FF"), Color(hex: "#FFB3F0")],
                                      center: .center, angle: .degrees(roll * 90)))
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2])).foregroundStyle(.white.opacity(0.7)).padding(5)
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "#1B2A55").opacity(0.75))
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// Tiny summit route used on the ticket stub.
struct MiniSummit: View {
    /// 0…1+
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let p = min(max(progress, 0), 1)
            let peak = CGPoint(x: w * 0.78, y: h * 0.12)
            let start = CGPoint(x: 0, y: h * 0.95)
            let climber = CGPoint(x: start.x + (peak.x - start.x) * p, y: start.y + (peak.y - start.y) * p)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.55))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.68))
                    path.addLine(to: peak)
                    path.addLine(to: CGPoint(x: w, y: h * 0.6))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                .fill(.white.opacity(0.14))
                Path { path in
                    path.move(to: start)
                    path.addLine(to: climber)
                }
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Path { path in
                    path.move(to: climber)
                    path.addLine(to: peak)
                }
                .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1, 3]))
                FlagShape().fill(Theme.dawn).frame(width: 9, height: 13).position(x: peak.x + 4, y: peak.y - 6)
                Circle().fill(.white).frame(width: 7, height: 7).position(climber)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ticket outline with perforation notches cut out on both edges (shadow follows the shape).
struct TicketShape: Shape {
    var notchY: CGFloat?

    func path(in rect: CGRect) -> Path {
        let base = Path(roundedRect: rect, cornerRadius: Theme.Radius.pass, style: .continuous)
        guard let notchY else { return base }
        let r: CGFloat = 12
        var notches = Path()
        notches.addEllipse(in: CGRect(x: rect.minX - r, y: rect.minY + notchY - r, width: r * 2, height: r * 2))
        notches.addEllipse(in: CGRect(x: rect.maxX - r, y: rect.minY + notchY - r, width: r * 2, height: r * 2))
        return base.subtracting(notches)
    }
}

/// Topographic contour lines (two centres of concentric distorted loops).
struct TopoLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func loops(center: CGPoint, rings: Int, step: CGFloat) {
            for k in 1...rings {
                let r = CGFloat(k) * step
                var first = true
                var theta: CGFloat = 0
                while theta <= .pi * 2 + 0.01 {
                    let f = 1 + 0.16 * sin(3 * theta) + 0.09 * sin(5 * theta) + 0.05 * sin(2 * theta)
                    let pt = CGPoint(x: center.x + cos(theta) * r * f * 1.25, y: center.y + sin(theta) * r * f)
                    if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    theta += 0.08
                }
                p.closeSubpath()
            }
        }
        loops(center: CGPoint(x: rect.maxX - 70, y: rect.minY + 92), rings: 14, step: 17)
        loops(center: CGPoint(x: rect.minX + 40, y: rect.maxY - 20), rings: 8, step: 18)
        return p
    }
}
