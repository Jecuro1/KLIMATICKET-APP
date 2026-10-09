import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import KlimaCore

// MARK: - Layout

/// Spacing rhythm of the Ticket tab (DESIGN.md §3: cards 10–12 apart, sections 18–24, rows 16 / 12).
enum TktStyle {
    static let cardSpacing: CGFloat = Theme.Spacing.s
    static let sectionSpacing: CGFloat = Theme.Spacing.l + Theme.Spacing.xxs
    static let rowPaddingH: CGFloat = Theme.Spacing.m
    static let rowPaddingV: CGFloat = Theme.Spacing.s
    /// Perforation / notch position of the DS `TicketCard` (280 pt tall pass).
    static let passNotchY: CGFloat = 194
    /// Section titles sit on the 20 pt text margin while cards use the 16 pt gutter.
    static let headerInset: CGFloat = Theme.Spacing.screen - Theme.Spacing.cardGutter
}

// MARK: - Entrance

/// Staggered entrance (fade + rise, the pass additionally tips in from a slight 3D tilt).
/// Settles within ~1.1 s; immediate in screenshot mode (the caller starts with `visible == true`), fade only with Reduce Motion.
struct TktEntrance: ViewModifier {
    var index: Int
    var visible: Bool
    var lift: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let hidden = !visible
        let moves = hidden && !reduceMotion
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: moves ? (lift ? 28 : 16) : 0)
            .rotation3DEffect(.degrees(moves && lift ? 12 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .animation(animation, value: visible)
    }

    private var animation: Animation {
        if reduceMotion { return .easeOut(duration: 0.25) }
        let delay = 0.07 * Double(min(index, 6))
        return lift ? .spring(duration: 0.85, bounce: 0.22).delay(delay) : .spring(duration: 0.6, bounce: 0.14).delay(delay)
    }
}

extension View {
    func tktEntrance(_ index: Int, visible: Bool, lift: Bool = false) -> some View {
        modifier(TktEntrance(index: index, visible: visible, lift: lift))
    }
}

// MARK: - Small building blocks

/// Rounded gradient tile with a white glyph (row icons: bell, card, renewal …).
struct TktIconTile: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color, color.mix(with: .black, by: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: Theme.Radius.modeTile * size / 40, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Hairline separator inside list-style cards.
struct TktHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// "Label ……… Wert" row; stacks label above value when the line gets too long (Dynamic Type, long texts).
struct TktDetailRow<Accessory: View>: View {
    var label: String
    var value: String
    var valueColor: Color = Theme.textPrimary
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                labelText
                Spacer(minLength: Theme.Spacing.s)
                accessory
                valueText
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                labelText
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    valueText
                    accessory
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
    }

    private var valueText: some View {
        Text(value)
            .font(.body.weight(.semibold).monospacedDigit())
            .foregroundStyle(valueColor)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension TktDetailRow where Accessory == EmptyView {
    init(label: String, value: String, valueColor: Color = Theme.textPrimary) {
        self.init(label: label, value: value, valueColor: valueColor, accessory: { EmptyView() })
    }
}

// MARK: - Copy helpers

/// German copy built from ticket data (Du-Form, de-AT).
enum TktText {
    /// Kicker on the pass: "Jahresticket · Ganz Österreich" (the DS card uppercases it).
    static func passKicker(name: String, variant: TicketVariant, family: TicketFamily, states: [String]) -> String {
        if family == .custom {
            return states.isEmpty ? "Eigenes Jahresticket" : "Jahresticket · \(region(family: family, states: states))"
        }
        // "Klassik" is the regular adult ticket – only reduced variants (Jugend, Senior …) are worth naming here.
        let named = variant == .klassik || name.localizedCaseInsensitiveContains(variant.displayName)
        return "\(named ? "Jahresticket" : variant.displayName) · \(region(family: family, states: states))"
    }

    /// "Ganz Österreich" · "Tirol" · "Wien, Niederösterreich & Burgenland".
    static func region(family: TicketFamily, states: [String]) -> String {
        if family == .oe { return "Ganz Österreich" }
        let names = states.compactMap { FederalState(rawValue: $0)?.displayName }
        guard let last = names.last else { return family == .custom ? "Eigenes Ticket" : "Regional" }
        if names.count == 1 { return last }
        return names.dropLast().joined(separator: ", ") + " & " + last
    }

    /// "Klassik · KlimaTicket Ö" / "Jugend · Regional" / "Eigenes Ticket".
    static func ticketType(variant: TicketVariant, family: TicketFamily) -> String {
        switch family {
        case .oe: "\(variant.displayName) · KlimaTicket Ö"
        case .regional: "\(variant.displayName) · Regionalticket"
        case .custom: "Eigenes Ticket"
        }
    }

    /// "2026/27" (or "2026" when the period stays within one calendar year).
    static func ticketYear(start: Date, end: Date) -> String {
        let cal = Calendar.vienna
        let a = cal.component(.year, from: start)
        let b = cal.component(.year, from: end)
        return a == b ? "\(a)" : "\(a)/\(String(format: "%02d", b % 100))"
    }

    /// "+ € 412" / "– € 120" (whole euros).
    static func signedEuro(_ value: Double) -> String {
        value >= 0 ? "+ \(Format.euro(value, decimals: 0))" : "– \(Format.euro(-value, decimals: 0))"
    }

    /// Amortisation percent that never claims "100 %" before the break-even (DESIGN_FINAL_SYNTHESIS §4.3).
    static func percent(_ fraction: Double) -> String {
        let raw = max(fraction, 0) * 100
        let shown = fraction < 1 ? min(99, raw.rounded()) : raw.rounded(.down)
        return "\(Format.number(shown)) %"
    }

    /// The fraction rounded the way `percent` shows it, for components that format it themselves: the DS `TicketCard`
    /// stub uses `Format.percent`, which would turn 99,6 % into "100 %" before the break-even (§4.3).
    static func displayFraction(_ fraction: Double) -> Double {
        let raw = max(fraction, 0) * 100
        let shown = fraction < 1 ? min(99, raw.rounded()) : raw.rounded(.down)
        return shown / 100
    }

    /// Catalog texts carry internal references ("– Details siehe rules.exclusions."); strip them for display.
    static func cleanCatalogText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = result.range(of: " – Details siehe rules") {
            result = String(result[..<range.lowerBound]) + "."
        }
        return result
    }
}

// MARK: - Selection

enum TktSelection {
    /// `Repository.addTicket` selects the new ticket app-wide. While another ticket is valid today, a ticket year that has
    /// not started yet must not replace it – Übersicht, Statistik and the widgets would show 0 % of a ticket you cannot use
    /// yet. Restores the previous selection in that case; returns true when it did.
    @MainActor
    @discardableResult
    static func keepRunningTicket(repo: Repository, app: AppState, added: TicketEntity,
                                  previousSelection: UUID?, running: TicketEntity?) -> Bool {
        guard let running, running.id != added.id, running.isActive, added.startDate > Date() else { return false }
        app.settings.selectedTicketID = previousSelection
        repo.refreshWidgets()
        return true
    }
}

// MARK: - Photo processing

/// Downscales and re-encodes the photo of the real ticket (HEIC/PNG/JPEG → JPEG, max 2000 px, orientation applied).
/// Pure ImageIO, safe to call off the main actor.
enum TktPhoto {
    static func prepared(_ data: Data, maxPixelSize: Int = 2000) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.82]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
