import SwiftUI
import KlimaCore

// MARK: stops – station picker row, route-card meta row (ENRICH_SPEC §3.3, BADGE_SPEC §4.1, LOGO_SPEC §4.3).

extension StationIndex {
    /// The enriched place (lines, tags) of a station of the picker; nil while the place index is not attached yet.
    func richPlace(for station: Station) -> Place? { places?.place(id: station.id) }
}

/// The single area mark of a row (LOGO_SPEC §4.3): official brand if the pack has one, else the own badge.
struct StopRowArea {
    var brandID: String?
    var ski: SkiArea?
    var regionName: String?

    var isEmpty: Bool { brandID == nil && ski == nil && regionName == nil }

    /// `place`'s mark: pack brand → own ski-pass badge → own region chip.
    @MainActor
    init(place: Place, index: PlaceIndex?) {
        let tags = place.tags
        if let ski = tags.primarySkiArea { self.ski = index?.skiArea(id: ski.id) }
        if let r = PlaceMarkSelection.detailRegions(tags: tags, skiArea: nil, regionName: { _ in nil }).first {
            regionName = index?.region(id: r.id)?.name
        }
        if case .brand(let id)? = PlaceMarkSelection.rowAreaMark(place: place, tags: tags,
                                                                 brands: LogoPackStore.shared.areaBrandProvider) {
            brandID = id
        }
        // Row rule: a ski area wins; the region chip only shows without one.
        if ski != nil { regionName = nil }
    }
}

/// What a suggestion row shows; built from the place (`init(place:index:query:)`) or by hand (previews, tests).
struct StopSuggestionRowModel {
    var title: String
    var spokenTitle: String
    var kindLabel: String
    var mode: TransportMode
    var isTown = false
    var inSkiArea: Bool
    var state: Bundesland?
    var municipality: String?
    var area: StopRowArea
    var placeMark: StopMark?
    var plates: [LineBadge]
    var overflow: Int
    var spoken: String

    @MainActor
    init(place: Place, index: PlaceIndex?, maxPlates: Int = 4) {
        let tags = place.tags
        let state = place.federalState.flatMap { $0 == .foreign ? nil : $0 }
        title = PlaceTitle.display(name: place.name, stateShown: state != nil, state: place.state)
        spokenTitle = PlaceNames.display(place.name)
        kindLabel = StopKindLabel.label(place: place, tags: tags)
        mode = place.products.primaryMode
        isTown = place.kind == .town
        inSkiArea = tags.showsSnowcap
        self.state = state
        if let m = place.municipality, place.kind == .stop, !PlaceNormalizer.fold(title).hasPrefix(PlaceNormalizer.fold(m)) {
            municipality = m
        }
        area = StopRowArea(place: place, index: index)
        placeMark = PlaceMarkSelection.rowMark(tags: tags)
        let picked = LinePlateOrder.diverse(place.lines, maxCount: maxPlates, services: tags.services)
        plates = picked.shown.map { LineBadge($0, size: .s, services: tags.services) }
        overflow = picked.overflow
        spoken = SpokenLabels.stopRow(place: place, tags: tags, lines: picked.shown, overflow: picked.overflow,
                                      skiAreaName: area.ski?.name ?? tags.primarySkiArea.flatMap { index?.skiArea(id: $0.id)?.name },
                                      municipality: municipality)
    }
}

/// Row of the station picker: tile (38, Schneehaube) · title · Landesmarke · Gemeinde · Gebietszeichen · Ortsmarke ·
/// line plates. The row degrades step by step instead of cutting text: Gemeinde last.
struct StopSuggestionRow: View {
    let model: StopSuggestionRowModel
    var query = ""
    var distanceText: String?

    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            StopTile(mode: model.mode, size: 38, snowcap: model.inSkiArea)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(highlighted)
                        .lineLimit(dts.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.tail)
                    if let distanceText {
                        Spacer(minLength: 4)
                        Text(distanceText).font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
                if dts.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        wrappedChips
                        platesRow
                    }
                } else {
                    HStack(spacing: 5) {
                        ViewThatFits(in: .horizontal) {
                            chips(full: true, municipality: true, mark: true)
                            chips(full: true, municipality: true, mark: false)
                            chips(full: false, municipality: true, mark: false)
                            chips(full: false, municipality: false, mark: false)
                        }
                        Spacer(minLength: 6)
                        platesRow.layoutPriority(1)
                    }
                    .frame(minHeight: 18)
                }
            }
        }
        .frame(minHeight: 56)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.spoken))
        .motionAnimation(Motion.smooth, value: LogoPackStore.shared.generation)
    }

    private var platesRow: some View {
        LinePlateRow(badges: model.plates, size: .s, maxCount: 4, extra: model.overflow)
    }

    private var wrappedChips: some View {
        chips(full: true, municipality: true, mark: true).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func chips(full: Bool, municipality: Bool, mark: Bool) -> some View {
        HStack(spacing: 5) {
            if let state = model.state { StateMarkW(state: state, style: .compact) }
            if municipality, let gem = model.municipality {
                Text(gem).font(.footnote.weight(.medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            AreaChip(area: model.area, full: full)
            // One Gebietszeichen or, without one, the Ortsmarke („P+R · 28 m“).
            if mark, model.area.isEmpty, let m = model.placeMark { PlaceMarkChip(mark: m, size: .row) }
        }
        .fixedSize()
    }

    private var highlighted: AttributedString {
        var s = AttributedString(model.title)
        s.font = .system(size: 16.5, weight: .regular)
        s.foregroundColor = Theme.textPrimary
        let title = model.title
        for r in PlaceTitle.highlightRanges(title: title, query: query) {
            if let lo = AttributedString.Index(r.lowerBound, within: s), let hi = AttributedString.Index(r.upperBound, within: s) {
                s[lo..<hi].font = .system(size: 16.5, weight: .bold)
            }
        }
        return s
    }
}

/// The single Gebietszeichen of a row: logo chip when the pack has it, else the own ski-pass badge or region chip.
struct AreaChip: View {
    let area: StopRowArea
    /// Step ① (name visible) vs ② (tile without name, icon-only badge).
    var full = true

    var body: some View {
        if let id = area.brandID, let brand = LogoPackStore.shared.brand(id: id) {
            BrandChip(brand: brand, nameless: !full) { own }
        } else {
            own
        }
    }

    @ViewBuilder
    private var own: some View {
        if let ski = area.ski {
            SkiPassBadge(area: ski, style: full ? .compact : .iconOnly)
        } else if let name = area.regionName {
            RegionChip(name: name)
        }
    }
}

/// Meta line of the trip editor's route card: Landesmarke · Gebietszeichen · Ortsmarke, plates on the right
/// (replaces „Bahnhof · Tirol“; ENRICH_SPEC §3.3).
struct StopMetaRow: View {
    let place: Place
    var index: PlaceIndex?

    var body: some View {
        let model = StopSuggestionRowModel(place: place, index: index, maxPlates: 3)
        HStack(spacing: 5) {
            ViewThatFits(in: .horizontal) {
                metaChips(model, full: true)
                metaChips(model, full: false)
            }
            Spacer(minLength: 6)
            LinePlateRow(badges: model.plates, size: .xs, maxCount: 3, extra: model.overflow)
                .layoutPriority(1)
        }
        .frame(minHeight: 18)
        .motionAnimation(Motion.smooth, value: LogoPackStore.shared.generation)
    }

    @ViewBuilder
    private func metaChips(_ m: StopSuggestionRowModel, full: Bool) -> some View {
        HStack(spacing: 5) {
            Text(m.kindLabel).font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(1)
            if let state = m.state { StateMarkW(state: state, style: .compact) }
            AreaChip(area: m.area, full: full)
            if full, let mark = m.placeMark { PlaceMarkChip(mark: mark, size: .row) }
        }
        .fixedSize()
    }
}
