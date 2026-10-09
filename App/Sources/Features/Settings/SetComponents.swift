import SwiftUI
import UIKit
import KlimaCore

// Building blocks of the settings module (DESIGN.md §5.7): icon tiles, row labels, headers, pills,
// the pale sky backdrop for grouped lists, the app icon and small formatting helpers.

// MARK: - Icon tile & row label

/// Coloured rounded-square icon tile (iOS-Settings style, "farbige Icon-Kacheln", radius ≈ 9).
/// Colours resolve to their saturated light variants so the white glyph keeps its contrast in dark mode.
struct SetIconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 30

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(max(scale, 1), 1.6)
        Image(systemName: symbol)
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(
                LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: side * 0.3, style: .continuous))
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }
}

/// Standard settings row label: icon tile + title (+ optional secondary line).
/// Built on `Label`, so list separators align with the title like in the system Settings app.
struct SetRowLabel: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String
    var tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            SetIconTile(symbol: symbol, tint: tint)
        }
    }
}

/// Uppercase eyebrow used as section header ("KONTO", "UPDATES").
struct SetSectionHeader: View {
    var title: String

    var body: some View {
        Kicker(text: title)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Calm explanatory section footer.
struct SetFooter: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Small status capsule ("Cloud-Sync aktiv", "v4"). `tint` must be a text-safe colour.
struct SetPill: View {
    var text: String
    var symbol: String? = nil
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

// MARK: - Backdrop

/// Pale alpine sky for grouped lists and sheets: calm `sheetBackground` with the ambient sky fading out
/// towards the middle ("kein Himmel-Mesh voll deckend – höchstens blass", DESIGN.md §2).
struct SetBackdrop: View {
    var skyOpacity: Double = 0.55
    /// 0…1 – where the sky has fully faded into the calm surface.
    var fadeEnd: Double = 0.5

    var body: some View {
        ZStack(alignment: .top) {
            Theme.sheetBackground
            AmbientBackground(style: .standard, glow: 0.6)
                .opacity(skyOpacity)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black.opacity(0.65), location: fadeEnd * 0.45),
                                           .init(color: .clear, location: fadeEnd)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - App icon

/// The real app icon (read from the bundle), with a vector fallback drawn from the icon artwork.
struct SetAppIconView: View {
    var size: CGFloat = 60

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Group {
            if let image = SetAppIconView.bundleIcon {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                SetDrawnAppIcon()
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: max(0.5, size / 120)) }
        .shadow(color: Color.black.opacity(0.16), radius: size / 10, y: size / 22)
        .accessibilityHidden(true)
    }

    /// Primary icon from Info.plist (`CFBundleIcons › CFBundlePrimaryIcon`), nil if not loadable.
    static let bundleIcon: UIImage? = {
        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
            if let files = primary["CFBundleIconFiles"] as? [String] {
                for name in files.reversed() {
                    if let image = UIImage(named: name) { return image }
                }
            }
            if let name = primary["CFBundleIconName"] as? String, let image = UIImage(named: name) {
                return image
            }
        }
        return UIImage(named: "AppIcon")
    }()
}

/// Vector version of design/icon/icon.svg (sky, two ridges, climbing route, summit dot) using brand tokens.
private struct SetDrawnAppIcon: View {
    private static let far: [CGPoint] = SetDrawnAppIcon.unit([(0, 690), (130, 590), (230, 640), (360, 500), (450, 560), (520, 470),
                                                               (600, 520), (760, 400), (880, 500), (1024, 450), (1024, 1024), (0, 1024)])
    private static let near: [CGPoint] = SetDrawnAppIcon.unit([(0, 860), (170, 760), (250, 790), (360, 650), (430, 690), (640, 300),
                                                                (760, 470), (830, 430), (1024, 680), (1024, 1024), (0, 1024)])
    private static let shade: [CGPoint] = SetDrawnAppIcon.unit([(640, 300), (760, 470), (700, 440), (655, 520), (620, 430), (600, 470)])
    private static let route: [CGPoint] = SetDrawnAppIcon.unit([(120, 880), (250, 790), (360, 650), (430, 690), (640, 300)])

    private static func unit(_ points: [(Double, Double)]) -> [CGPoint] {
        points.map { CGPoint(x: $0.0 / 1024, y: $0.1 / 1024) }
    }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                LinearGradient(colors: [Theme.glacier, Theme.dusk, Theme.dawn],
                               startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.6, y: 1))
                RadialGradient(colors: [Theme.dawn2.opacity(0.85), Theme.dawn2.opacity(0)],
                               center: UnitPoint(x: 0.62, y: 0.34), startRadius: 0, endRadius: s * 0.42)
                SetUnitPolygon(points: SetDrawnAppIcon.far)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                SetUnitPolygon(points: SetDrawnAppIcon.near)
                    .fill(LinearGradient(colors: [Color.white, Theme.sheetBackground], startPoint: .top, endPoint: .bottom))
                SetUnitPolygon(points: SetDrawnAppIcon.shade)
                    .fill(Theme.dusk.opacity(0.22))
                SetUnitPolygon(points: SetDrawnAppIcon.route, closed: false)
                    .stroke(LinearGradient(colors: [Theme.glacier, Theme.dusk], startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: s * 0.039, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(Theme.dawn)
                    .overlay { Circle().strokeBorder(Color.white, lineWidth: s * 0.0176) }
                    .frame(width: s * 0.1035, height: s * 0.1035)
                    .position(x: s * 0.625, y: s * 0.293)
            }
        }
        .environment(\.colorScheme, .light)
    }
}

/// Polygon / polyline defined in unit coordinates (0…1).
private struct SetUnitPolygon: Shape {
    var points: [CGPoint]
    var closed: Bool = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        if closed { path.closeSubpath() }
        return path
    }
}

// MARK: - Info page

/// Calm text page for long copy (Preisschätzung, Datenschutz, Hinweis) – pushed from settings.
struct SetInfoPage: View {
    var title: String
    var kicker: String
    var symbol: String
    var tint: Color
    var text: String
    var notesTitle: String? = nil
    var notes: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack(spacing: Theme.Spacing.s) {
                            SetIconTile(symbol: symbol, tint: tint, size: 40)
                            Kicker(text: kicker)
                        }
                        Text(text)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !notes.isEmpty {
                    notesCard
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background { SetBackdrop(skyOpacity: 0.4, fadeEnd: 0.4) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var notesCard: some View {
        SurfaceCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let notesTitle {
                    Kicker(text: notesTitle)
                }
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

/// Formatting helpers specific to settings (relative times, ISO strings, versions, German plurals).
enum SetFormat {
    /// "gerade eben", "vor 5 Minuten", "gestern".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return "gerade eben" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Format.locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Parses "2026-10-09" (also accepts longer ISO strings by their date part).
    static func isoDay(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Vienna")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(string.prefix(10)))
    }

    /// Parses ISO 8601 date-times ("2026-10-09T09:41:00Z"), falling back to the date part.
    static func isoDateTime(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        return isoDay(string)
    }

    /// "1.1" for 1.1.0, otherwise "1.1.2".
    static func shortVersion(_ version: SemanticVersion) -> String {
        version.patch == 0 ? "\(version.major).\(version.minor)" : version.description
    }

    /// "1 Fahrt" / "87 Fahrten".
    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(Format.number(Double(n))) \(n == 1 ? singular : plural)"
    }

    /// "30, 7 und 1 Tag vorher".
    static func reminderOffsets(_ offsets: [Int]) -> String? {
        let sorted = Array(Set(offsets.filter { $0 > 0 })).sorted(by: >)
        guard let last = sorted.last else { return nil }
        let unit = last == 1 ? "Tag" : "Tage"
        if sorted.count == 1 { return "\(last) \(unit) vorher" }
        let head = sorted.dropLast().map(String.init).joined(separator: ", ")
        return "\(head) und \(last) \(unit) vorher"
    }
}

/// Demo identity for CI screenshots (matches the demo ticket holder) – never used outside screenshot mode.
enum SetDemo {
    static let profile = UserProfile(id: "screenshot-demo", displayName: "Lena Hofer", email: "lena.hofer@example.com",
                                     provider: .apple, avatarURL: nil, isCloud: false)
}

extension View {
    /// `.sensoryFeedback` that respects the "Haptisches Feedback" setting.
    func settingsHaptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, enabled: Bool) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in enabled ? feedback : nil }
    }
}
