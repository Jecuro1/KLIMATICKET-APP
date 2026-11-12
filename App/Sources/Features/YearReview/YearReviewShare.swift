import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers
import KlimaCore

// The last page: "Dein Jahr als Bild". A live preview of `YearReviewShareCard` (rendered with `ImageRenderer`, so the
// preview is the export), format 9:16 or 4:5, style Hell / Dunkel / Gipfel, and a switch for stations and names – off by
// default: then the image carries totals only, no station names and no holder name. Shared with `ShareLink` and a PNG
// `Transferable` (the pattern of `StatsSharePayload`); the share sheet itself offers "Bild sichern", so no photo-library
// permission is needed.

enum YearReviewShareFormat: String, CaseIterable, Identifiable, Hashable {
    case story
    case portrait

    var id: String { rawValue }
    var title: String { self == .story ? "9:16" : "4:5" }
    var spokenTitle: String { self == .story ? "Story, neun zu sechzehn" : "Beitrag, vier zu fünf" }

    /// The card is laid out in points and exported at `scale`× – exactly 1080 × 1920 and 1080 × 1350 pixels.
    var cardSize: CGSize { self == .story ? CGSize(width: 360, height: 640) : CGSize(width: 360, height: 450) }
    static let scale: CGFloat = 3
    var pixelSize: CGSize { CGSize(width: cardSize.width * Self.scale, height: cardSize.height * Self.scale) }
    var pixelText: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px" }
}

enum YearReviewShareStyle: String, CaseIterable, Identifiable, Hashable {
    case light
    case dark
    case summit

    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "Hell"
        case .dark: "Dunkel"
        case .summit: "Gipfel"
        }
    }

    var scheme: ColorScheme { self == .light ? .light : .dark }
}

/// What the share page lets you choose. `style` nil follows the system appearance until you pick one.
struct YearReviewShareOptions: Equatable {
    var format: YearReviewShareFormat = .story
    var style: YearReviewShareStyle?
    /// "Strecken und Namen zeigen": stations, routes and the holder name. Off = totals only.
    var showsDetails = false

    func resolvedStyle(for scheme: ColorScheme) -> YearReviewShareStyle { style ?? (scheme == .dark ? .dark : .light) }
}

// MARK: - Content

/// Everything the image says, already formatted. Without `details` it holds totals only.
struct YearReviewShareContent: Hashable {
    struct Tile: Hashable {
        var value: String
        var unit: String?
        var label: String
    }

    struct Line: Hashable {
        var label: String
        var text: String
    }

    var periodTitle: String
    var yearLabel: String
    var heroValue: String
    var heroCaption: String
    var tiles: [Tile]
    /// "7 von 9 Bundesländern" – a total, so it is part of the default image.
    var statesLine: String?
    /// Only with "Strecken und Namen zeigen".
    var holderName: String?
    var detailLines: [Line]

    var hasDetails: Bool { holderName != nil || !detailLines.isEmpty }

    /// VoiceOver text of the preview.
    var spoken: String {
        let tileText = tiles.map { "\($0.value)\($0.unit.map { " \($0)" } ?? "") \($0.label)" }.joined(separator: ", ")
        return "Vorschau deines Bildes: \(periodTitle), \(heroValue) \(heroCaption), \(tileText)."
    }

    var fileName: String { "KlimaBilanz-Jahresrueckblick-\(yearLabel.replacingOccurrences(of: "/", with: "-")).png" }

    static func make(review: YearReview, showsDetails: Bool, holderName: String) -> YearReviewShareContent? {
        guard let finale = review.finale, let savings = review.savings else { return nil }
        let hero: (String, String)
        switch YearReviewText.verdict(savings) {
        case .profit(let amount) where amount >= 1:
            // "Gewinn", not "gespart": the value of every trip against the ticket price – the same figure as the Übersicht hero, and
            // it may include trips you would not have made without the ticket (the story's honest line says so).
            hero = ("+ \(SummitFigures.euro(amount))", savings.costIsPartial ? "Gewinn gegenüber den anteiligen Ticketkosten" : "Gewinn gegenüber dem Ticketpreis")
        case .profit:
            hero = ("100 %", "amortisiert")
        case .remaining:
            hero = (Format.number(SummitFigures.percent(savings.totalValue / max(savings.ticketCost, 0.01))) + " %",
                    savings.costIsPartial ? "der anteiligen Ticketkosten" : "amortisiert")
        case .valueOnly(let value):
            hero = (SummitFigures.euro(value), "Fahrtwert")
        }

        var tiles = [YearReviewShareContent.Tile(value: Format.number(Double(finale.tripCount)), unit: nil, label: "Fahrten")]
        tiles.append(.init(value: Format.number(finale.distanceKm, decimals: finale.distanceKm < 10 ? 1 : 0), unit: "km", label: "unterwegs"))
        if let co2 = finale.co2SavedKg {
            let parts = StatsCalc.co2Parts(co2)
            tiles.append(.init(value: parts.value, unit: parts.unit, label: "CO₂ gespart"))
        } else if let road = review.onTheRoad, road.stateCount > 0 {
            tiles.append(.init(value: "\(road.stateCount)/\(YearReview.OnTheRoad.totalStates)", unit: nil, label: "Bundesländer"))
        }

        var lines: [YearReviewShareContent.Line] = []
        var holder: String?
        if showsDetails {
            let name = holderName.trimmingCharacters(in: .whitespacesAndNewlines)
            holder = name.isEmpty ? nil : name
            if let top = review.favoriteRoute?.top {
                lines.append(.init(label: "Lieblingsroute", text: "\(YearReviewText.routeTitle(top)) · \(top.trips)×"))
            }
            if let trip = review.onTheRoad?.longestTrip {
                lines.append(.init(label: "Längste Fahrt", text: "\(YearReviewText.tripTitle(trip)) · \(YearReviewText.tripDistance(trip))"))
            }
            if let reference = review.distance?.reference {
                lines.append(.init(label: "Entspricht", text: YearReviewText.referenceLine(reference)))
            }
        }

        var states: String?
        if let road = review.onTheRoad, road.stateCount > 0 {
            states = "\(road.stateCount) von \(YearReview.OnTheRoad.totalStates) Bundesländern"
        }
        return YearReviewShareContent(periodTitle: review.period.title(), yearLabel: review.period.yearLabel(), heroValue: hero.0,
                                      heroCaption: hero.1, tiles: tiles, statesLine: states, holderName: holder, detailLines: lines)
    }
}

// MARK: - Card

/// The image: laid out at `format.cardSize`, exported at 3×. No materials, no animation, only gradients – so
/// `ImageRenderer` captures it exactly as the preview shows it.
struct YearReviewShareCard: View {
    let content: YearReviewShareContent
    let format: YearReviewShareFormat
    let style: YearReviewShareStyle

    private var isStory: Bool { format == .story }

    var body: some View {
        ZStack {
            YearReviewShareBackdrop(style: style, isStory: isStory)
            VStack(alignment: .leading, spacing: 0) {
                brandRow
                Color.clear.frame(height: isStory ? 64 : 8)
                Kicker(text: content.periodTitle, color: Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(content.heroValue)
                    .font(.system(size: isStory ? 92 : 70, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.top, 2)
                Text(content.heroCaption)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.positiveText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let states = content.statesLine {
                    Label(states, systemImage: "map.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: .capsule)
                        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                        .padding(.top, 12)
                }
                if content.hasDetails { detailsPanel.padding(.top, 12) }
                Spacer(minLength: 8)
                tilesRow
                Text("Hat sich dein Ticket schon rentiert?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 10)
            }
            .padding(24)
        }
        .frame(width: format.cardSize.width, height: format.cardSize.height)
        .clipped()
        .environment(\.colorScheme, style.scheme)
    }

    private var brandRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.ctaGradient, in: .rect(cornerRadius: 8, style: .continuous))
            Text("KlimaBilanz")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Text(content.holderName ?? content.yearLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(content.detailLines, id: \.self) { line in
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.label.uppercased(with: Format.locale))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                    Text(line.text)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelFill, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    /// The Gipfel look has mountains behind the panels: they get a calm backing so the text stays readable.
    private var panelFill: AnyShapeStyle {
        style == .summit ? AnyShapeStyle(Theme.background.opacity(0.78)) : AnyShapeStyle(Theme.surface)
    }

    private var tilesRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(content.tiles.enumerated()), id: \.offset) { index, tile in
                if index > 0 {
                    Rectangle().fill(Theme.separator).frame(width: 1, height: 30)
                }
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(tile.value)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        if let unit = tile.unit {
                            Text(unit)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Text(tile.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(panelFill, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }
}

/// The three looks. Hell: morning sky with a pale ridge. Dunkel: "Blaue Stunde" with a dusky ridge. Gipfel: the dark sky with
/// a glowing horizon and tall ridges.
private struct YearReviewShareBackdrop: View {
    let style: YearReviewShareStyle
    let isStory: Bool

    var body: some View {
        ZStack {
            Theme.background
            switch style {
            case .light:
                LinearGradient(colors: [Theme.background, Theme.glacier.opacity(0.20), Theme.dawn.opacity(0.26)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.dawn.opacity(0.40), Theme.dawn.opacity(0)], center: UnitPoint(x: 0.82, y: 0.84), startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Theme.glacier.opacity(0.28), Theme.glacier.opacity(0)], center: UnitPoint(x: 0.1, y: 0.04), startRadius: 0, endRadius: 280)
                ridges(farOpacity: 0.20, nearOpacity: 0.26, height: isStory ? 0.34 : 0.28)
            case .dark:
                LinearGradient(colors: [Theme.background, Theme.dusk.opacity(0.32), Theme.dawn.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.alpenglow.opacity(0.35), Theme.alpenglow.opacity(0)], center: UnitPoint(x: 0.78, y: 0.7), startRadius: 0, endRadius: 240)
                RadialGradient(colors: [Theme.glacier.opacity(0.22), Theme.glacier.opacity(0)], center: UnitPoint(x: 0.1, y: 0.05), startRadius: 0, endRadius: 270)
                ridges(farOpacity: 0.30, nearOpacity: 0.40, height: isStory ? 0.34 : 0.28)
            case .summit:
                LinearGradient(colors: [Theme.background, Theme.dusk.opacity(0.55), Theme.alpenglow.opacity(0.45), Theme.dawn.opacity(0.70)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.dawn.opacity(0.85), Theme.dawn.opacity(0)], center: UnitPoint(x: 0.7, y: isStory ? 0.72 : 0.74), startRadius: 0, endRadius: 210)
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        RidgeShape(peakX: 0.7, peakY: 0.22, seed: 21, roughness: 0.8)
                            .fill(LinearGradient(colors: [Theme.dusk.opacity(0.9), Theme.background], startPoint: .top, endPoint: .bottom))
                            .frame(height: proxy.size.height * (isStory ? 0.44 : 0.38))
                        RidgeShape(peakX: 0.26, peakY: 0.34, seed: 8, roughness: 0.6)
                            .fill(Theme.background.opacity(0.94))
                            .frame(height: proxy.size.height * (isStory ? 0.3 : 0.25))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func ridges(farOpacity: Double, nearOpacity: Double, height: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RidgeShape(peakX: 0.72, peakY: 0.2, seed: 11, roughness: 0.7)
                    .fill(LinearGradient(colors: [Theme.dusk.opacity(farOpacity), Theme.dusk.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .frame(height: proxy.size.height * height)
                RidgeShape(peakX: 0.3, peakY: 0.34, seed: 5, roughness: 0.5)
                    .fill(LinearGradient(colors: [Theme.glacier.opacity(nearOpacity), Theme.glacier.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .frame(height: proxy.size.height * height * 0.78)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Export

enum YearReviewShareRenderer {
    /// The card as an image at 3× (1080 × 1920 or 1080 × 1350 px).
    @MainActor
    static func image(content: YearReviewShareContent, format: YearReviewShareFormat, style: YearReviewShareStyle) -> UIImage? {
        let renderer = ImageRenderer(content: YearReviewShareCard(content: content, format: format, style: style))
        renderer.scale = YearReviewShareFormat.scale
        renderer.proposedSize = ProposedViewSize(width: format.cardSize.width, height: format.cardSize.height)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// PNG with exactly `format.pixelSize` pixels: the render is used as is when it has that size, otherwise it is drawn
    /// once more into a bitmap of exactly that size.
    @MainActor
    static func pngData(content: YearReviewShareContent, format: YearReviewShareFormat, style: YearReviewShareStyle) -> Data? {
        guard let image = image(content: content, format: format, style: style) else { return nil }
        let target = format.pixelSize
        if let cgImage = image.cgImage, CGFloat(cgImage.width) == target.width, CGFloat(cgImage.height) == target.height {
            return image.pngData()
        }
        let bitmap = UIGraphicsImageRendererFormat()
        bitmap.scale = 1
        bitmap.opaque = true
        return UIGraphicsImageRenderer(size: target, format: bitmap).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Pixel size of a rendered image (for the check in the screenshot host).
    static func pixelSize(of image: UIImage) -> CGSize {
        if let cgImage = image.cgImage { return CGSize(width: cgImage.width, height: cgImage.height) }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
}

/// The PNG the share sheet exports – rendered only when it is asked for, like `StatsSharePayload`.
struct YearReviewSharePayload: Transferable {
    let content: YearReviewShareContent
    let format: YearReviewShareFormat
    let style: YearReviewShareStyle

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in
            try await payload.renderPNG()
        }
        .suggestedFileName("KlimaBilanz-Jahresrueckblick.png")
    }

    @MainActor
    func renderPNG() throws -> Data {
        guard let data = YearReviewShareRenderer.pngData(content: content, format: format, style: style) else {
            throw TktShareError.renderFailed
        }
        return data
    }
}

// MARK: - Page

struct YearReviewFinalePage: View {
    let finale: YearReview.Finale
    let ctx: YearReviewPageContext

    @Environment(\.colorScheme) private var colorScheme
    /// Format, style and names: plain page state, mirrored to the store so they survive paging back and forth.
    @State private var options: YearReviewShareOptions
    @State private var previewImage: UIImage?
    @State private var pageHeight: CGFloat = 640

    init(finale: YearReview.Finale, ctx: YearReviewPageContext) {
        self.finale = finale
        self.ctx = ctx
        _options = State(initialValue: ctx.store.shareOptions)
    }

    var body: some View {
        let style = options.resolvedStyle(for: colorScheme)
        let content = YearReviewShareContent.make(review: ctx.review, showsDetails: options.showsDetails, holderName: ctx.store.holderName)
        // The preview takes what the controls below leave over (they need about 360 pt).
        let previewHeight = min(430, max(200, pageHeight - 360))
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryKicker(kind: .finale, symbol: "square.and.arrow.up")
                    .reveal(.fade)
                titleRow($options)
                    .reveal(order: 1)
                if let content {
                    preview(content: content, options: options, style: style, height: previewHeight)
                        .reveal(.focus, order: 2)
                    controls($options, style: style)
                        .reveal(order: 3)
                    shareButton(content: content, options: options, style: style)
                        .reveal(order: 4)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
        }
        .scrollIndicators(.visible)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .onChange(of: options) { _, new in ctx.store.shareOptions = new }
        .task(id: PreviewKey(content: content, format: options.format, style: style)) {
            guard let content else { return }
            previewImage = YearReviewShareRenderer.image(content: content, format: options.format, style: style)
        }
    }

    private struct PreviewKey: Hashable {
        var content: YearReviewShareContent?
        var format: YearReviewShareFormat
        var style: YearReviewShareStyle
    }

    // MARK: Preview

    @ViewBuilder
    private func preview(content: YearReviewShareContent, options: YearReviewShareOptions, style: YearReviewShareStyle, height: CGFloat) -> some View {
        let size = options.format.cardSize
        HStack {
            Spacer(minLength: 0)
            Group {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    // The first frame, before the render is ready: the card itself, scaled.
                    YearReviewShareCard(content: content, format: options.format, style: style)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(height / size.height)
                        .frame(width: size.width * height / size.height, height: height)
                }
            }
            .frame(height: height)
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
            .shadow(color: Theme.textPrimary.opacity(0.18), radius: 16, y: 8)
            .motionAnimation(Motion.smooth, value: options.format)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spoken)
    }

    // MARK: Controls

    /// "Dein Jahr als Bild" with the format next to it (below it at large text sizes).
    private func titleRow(_ options: Binding<YearReviewShareOptions>) -> some View {
        let title = Text("Dein Jahr als Bild")
            .font(.title2.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                title
                Spacer(minLength: Theme.Spacing.xs)
                formatPicker(options).frame(width: 132)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                title
                formatPicker(options)
            }
        }
    }

    private func controls(_ options: Binding<YearReviewShareOptions>, style: YearReviewShareStyle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            stylePicker(options, style: style)
            Toggle(isOn: options.showsDetails) {
                Text("Strecken und Namen zeigen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .haptic(.selection, trigger: options.wrappedValue.showsDetails)
            Text(options.wrappedValue.showsDetails
                 ? "Mit Lieblingsroute, längster Fahrt und deinem Namen."
                 : "Nur Gesamtzahlen – keine Stationen, kein Name.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatPicker(_ options: Binding<YearReviewShareOptions>) -> some View {
        GlassSegmentedPicker(selection: options.format, options: YearReviewShareFormat.allCases) { format in
            Text(format.title).accessibilityLabel(format.spokenTitle)
        }
        .accessibilityLabel("Format")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // a segmented control: at AX5 "Dunkel" would read "Dun"
    }

    private func stylePicker(_ options: Binding<YearReviewShareOptions>, style: YearReviewShareStyle) -> some View {
        GlassSegmentedPicker(selection: Binding(get: { style }, set: { options.wrappedValue.style = $0 }),
                             options: YearReviewShareStyle.allCases) { style in
            Text(style.title)
        }
        .accessibilityLabel("Stil")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: Share

    private func shareButton(content: YearReviewShareContent, options: YearReviewShareOptions, style: YearReviewShareStyle) -> some View {
        let payload = YearReviewSharePayload(content: content, format: options.format, style: style)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ShareLink(item: payload, preview: SharePreview("Mein KlimaTicket-Jahr", image: payload)) {
                Label("Bild teilen", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.primary)
            Text("PNG · \(options.format.pixelText) · „Bild sichern“ im Teilen-Menü")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
