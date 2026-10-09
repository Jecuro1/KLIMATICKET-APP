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

    /// Amortisation percent that never claims "100 %" before the break-even (DESIGN_FINAL_SYNTHESIS §4.3) – the same
    /// rounding as the Übersicht hero (`SummitFigures.percent`).
    static func percent(_ fraction: Double) -> String {
        "\(Format.number(SummitFigures.percent(fraction))) %"
    }

    /// The fraction rounded the way `percent` shows it, for components that format it themselves: the DS `TicketCard`
    /// stub uses `Format.percent`, which would turn 99,6 % into "100 %" before the break-even (§4.3).
    static func displayFraction(_ fraction: Double) -> Double {
        SummitFigures.percent(fraction) / 100
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

@MainActor
enum TktSelection {
    /// `Repository.addTicket` pins the new ticket app-wide. While another ticket is valid today, a ticket year that has
    /// not started yet must not replace it – Übersicht, Statistik and the widgets would show 0 % of a ticket you cannot use
    /// yet. Returns true when it kept the running ticket.
    ///
    /// It goes back to automatic mode (no pin) rather than restoring the previous pin: `Analytics.activeTicket` then shows
    /// the running ticket now and switches to the follow-up by itself on its first day. A restored pin would keep the
    /// expired year on every screen and in the widget after that day. The running ticket stays pinned only when automatic
    /// mode would show a different (overlapping) ticket.
    @discardableResult
    static func keepRunningTicket(repo: Repository, app: AppState, added: TicketEntity,
                                  previousSelection: UUID?, running: TicketEntity?) -> Bool {
        guard let running, running.id != added.id, running.isActive, added.startDate > Date() else { return false }
        let automatic = Analytics.activeTicket(in: repo.liveTickets(), selectedID: nil)
        app.settings.selectedTicketID = automatic?.id == running.id ? nil : running.id
        repo.refreshWidgets()
        return true
    }

    /// Vienna day of the last `releaseStalePin` check.
    private static var lastPinCheckDay: Date?

    /// A pinned ticket year that has expired while a later one is valid today goes back to automatic mode, so every
    /// screen and the widget follow the running ticket. Every ticket used to be pinned when it was added (and a ticket
    /// picked in „Ticket-Verlauf“ stays pinned), so without this the old year would stay on screen forever.
    /// Checked once per day – at launch and on the first activation of a new day – so an old year picked on purpose
    /// survives switching apps. Returns true when it changed the selection (refresh the widgets then).
    @discardableResult
    static func releaseStalePin(tickets: [TicketEntity], app: AppState, now: Date = Date()) -> Bool {
        let day = Calendar.vienna.startOfDay(for: now)
        guard lastPinCheckDay != day else { return false }
        lastPinCheckDay = day
        guard let id = app.settings.selectedTicketID,
              let pinned = tickets.first(where: { $0.id == id && $0.deletedAt == nil }), now > pinned.endDate,
              tickets.contains(where: { $0.deletedAt == nil && $0.startDate > pinned.endDate
                                        && $0.startDate <= now && now <= $0.endDate }) else { return false }
        app.settings.selectedTicketID = nil
        return true
    }
}

// MARK: - Inline title

/// Scroll-driven inline navigation title (Ticket, Ratgeber). The flag lives in this observable box and only
/// `TktInlineTitle` reads it, so crossing the threshold re-renders the toolbar title – not the screen owning the scroll view.
@Observable
@MainActor
final class TktTitleChrome {
    var showsInlineTitle = false
}

/// The principal toolbar title that fades in once the large title has scrolled away.
struct TktInlineTitle: View {
    let title: String
    let chrome: TktTitleChrome

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .opacity(chrome.showsInlineTitle ? 1 : 0)
            .accessibilityHidden(!chrome.showsInlineTitle)
    }
}

extension View {
    /// Flips `chrome.showsInlineTitle` when the content scrolls past `threshold` (apply to the ScrollView).
    func tktInlineTitleTracking(_ chrome: TktTitleChrome, threshold: CGFloat = 52) -> some View {
        onScrollGeometryChange(for: Bool.self, of: { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > threshold
        }, action: { _, isPastHeader in
            guard chrome.showsInlineTitle != isPastHeader else { return }
            withAnimation(.easeInOut(duration: 0.2)) { chrome.showsInlineTitle = isPastHeader }
        })
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
