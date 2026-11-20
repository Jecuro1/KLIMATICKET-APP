import SwiftUI
import KlimaCore

// MARK: radar2-radarmine – the panel „Meine Fahrzeuge“ (docs/RADAR_MINE.md §9): one glass card above the status card (the layer bar steps aside while
// it is open), at most 36 % of the window's height (42 % at accessibility sizes); its pages scroll inside. Segments „Linien · In der Nähe ·
// Haltestelle“, a menu that forgets what is remembered, a close button. The title row grows only to xxxLarge and the page to AX2, like the radar's
// other bars over the map; from AX3 on the segments become a menu with the current page as its title (one line, never hyphenated).

struct RadarMinePanel: View {
    var mine: RadarMineModel
    var context: RadarMineContext
    /// The height of the radar's window: the panel takes at most 36 % of it (42 % at accessibility sizes) and the page scrolls inside. Not the map's
    /// height: the map shrinks while the panel takes room at the bottom, and a panel sized from it shrank with it (CI screenshots run 2).
    var windowHeight: CGFloat

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var contentHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0
    @State private var confirmLines = false
    @State private var confirmStops = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                pagePicker
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 }
            // The page takes its own height up to what is left of the cap (measured: inside the radar's bottom scroll view a scroll view would
            // otherwise take an arbitrary height and cut the page after its first row, CI screenshots run 1).
            ScrollView {
                page
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)   // the rows grow to AX2 like the status card under them (AX5 showed no row at all)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight > 0 ? min(contentHeight, listCap) : min(160, listCap))
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.card)   // a content card (Reduce Transparency: opaque); its segments are the glass
        .simultaneousGesture(TapGesture().onEnded { mine.interact() })
        .confirmationDialog(RadarMineText.deleteLinesQuestion, isPresented: $confirmLines, titleVisibility: .visible) {
            Button(RadarMineText.delete, role: .destructive) { withMotion(Motion.smooth) { mine.forgetAllLines() } }
            Button(RadarMineText.cancel, role: .cancel) {}
        }
        .confirmationDialog(RadarMineText.deleteStopsQuestion, isPresented: $confirmStops, titleVisibility: .visible) {
            Button(RadarMineText.delete, role: .destructive) { withMotion(Motion.smooth) { mine.forgetRecentStops() } }
            Button(RadarMineText.cancel, role: .cancel) {}
        }
    }

    private var maxHeight: CGFloat { windowHeight * (typeSize.isAccessibilitySize ? 0.42 : 0.36) }

    private var listCap: CGFloat { max(maxHeight - chromeHeight - Theme.Spacing.s * 3, 120) }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "star.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            Text(RadarMineText.panelTitle)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.xs)
            if !mine.lines.isEmpty || !mine.file.stops.isEmpty {
                Menu {
                    if !mine.lines.isEmpty {
                        Button(RadarMineText.deleteLines, systemImage: "star.slash", role: .destructive) { confirmLines = true }
                    }
                    if !mine.file.stops.isEmpty {
                        Button(RadarMineText.deleteStops, systemImage: "clock.arrow.circlepath", role: .destructive) { confirmStops = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceSecondary, in: .circle)
                }
                .accessibilityLabel(RadarMineText.menu)
            }
            Button {
                withMotion(Motion.smooth) { mine.close() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surfaceSecondary, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RadarMineText.close)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // „Meine Fahrzeuge“ and two buttons stay on one line (AX1 still wrapped the title, run 2)
    }

    @ViewBuilder private var pagePicker: some View {
        let selection = Binding(get: { mine.page }, set: { mine.page = $0 })
        if typeSize >= .accessibility3 {
            Menu {
                Picker(RadarMineText.panelTitle, selection: selection) {
                    ForEach(RadarMineText.Page.allCases) { page in
                        Label(page.title, systemImage: page.symbol).tag(page)
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Label(mine.page.title, systemImage: mine.page.symbol)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.bold))
                }
                .font(.headline)
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)   // „Haltestelle“ on one line (AX5 hyphenated it, run 2)
            }
            .accessibilityLabel("\(RadarMineText.panelTitle): \(mine.page.title)")
        } else {
            GlassSegmentedPicker(selection: selection, options: RadarMineText.Page.allCases) { page in
                Text(page.title)
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch mine.page {
        case .lines: RadarMineLinesPage(mine: mine, context: context)
        case .near: RadarMineNearPage(mine: mine, context: context)
        case .stop: RadarMineStopPage(mine: mine, context: context)
        }
    }
}

// MARK: - Shared pieces of the pages

/// A short sentence with an optional button, in the panel's quiet style (a hint, a pause, an empty state).
struct RadarMineNote: View {
    var symbol: String
    var text: String
    var actionTitle: String? = nil
    var tint: Color = Theme.textSecondary
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small print at the end of a page.
struct RadarMineFooter: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xxs)
    }
}

/// Two lines that sit side by side, and stack at accessibility sizes (the ETA never truncates).
struct RadarMineAdaptiveRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                leading
                trailing
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                leading
                Spacer(minLength: Theme.Spacing.xs)
                trailing
            }
        }
    }
}
