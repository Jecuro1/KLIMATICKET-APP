import KlimaCore
import SwiftUI

// MARK: stops – the sections of the stop detail (ENRICH_SPEC §3.2, LOGO_SPEC §4.4).

/// Everything the sections derive from the loaded details once per render.
struct StopContext {
    let details: StopDetails
    let index: PlaceIndex?
    /// Official brands of the stop (nil: logos off / no pack yet).
    let brands: StopBrands?
    /// Gebietsleiste cells with an image (≤ 2).
    let cells: [LogoPackManifest.Brand]

    var place: Place { details.place }
    var tags: PlaceTags { details.tags }
    var state: Bundesland? { place.federalState.flatMap { $0 == .foreign ? nil : $0 } }
    var services: [PlaceService] { tags.services }

    @MainActor
    init(details: StopDetails, index: PlaceIndex?, dark: Bool) {
        self.details = details
        self.index = index
        let store = LogoPackStore.shared
        brands = store.brands(for: PlaceMarkSelection.areaBrandQuery(place: details.place, tags: details.tags))
        let ids = PlaceMarkSelection.heroAreaCells(place: details.place, tags: details.tags, brands: store.areaBrandProvider)
        cells = ids.compactMap { mark -> LogoPackManifest.Brand? in
            guard case .brand(let id) = mark, let b = store.brand(id: id), store.image(b, large: true, dark: dark) != nil else { return nil }
            return b
        }
    }

    /// Lines grouped by plate family in family order.
    var groups: [(kind: LineKind, lines: [StopLine])] {
        var byKind: [LineKind: [StopLine]] = [:]
        for l in details.lines {
            let kind = LineKind.classify(l.line, services: services)
            byKind[kind, default: []].append(l)
        }
        var out: [(kind: LineKind, lines: [StopLine])] = []
        for kind in byKind.keys.sorted(by: { $0.familyRank < $1.familyRank }) {
            let rows = byKind[kind] ?? []
            let order = LinePlateOrder.sorted(rows.map(\.line), services: services)
            var sorted: [StopLine] = []
            for ref in order {
                if let row = rows.first(where: { $0.line.id == ref.id }) { sorted.append(row) }
            }
            out.append((kind, sorted))
        }
        return out
    }

    func terminus(_ name: String?, id: String?) -> String? {
        if let id, let p = index?.place(id: id) { return PlaceTitle.display(name: p.name, stateShown: false) }
        return name.flatMap { $0.isEmpty ? nil : PlaceTitle.display(name: $0, stateShown: false) }
    }
}

// MARK: - Small building blocks

struct StopSectionTitle: View {
    let text: String
    var symbol: String?
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true) }
            Text(text.uppercased(with: Format.locale)).font(Theme.Typography.kicker).tracking(1.2)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Hero

struct StopHeroCard: View {
    let ctx: StopContext
    var onBrandTap: (LogoPackManifest.Brand) -> Void
    var onShowLines: () -> Void

    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let d = ctx.details
        let hero = PlaceTitle.hero(name: d.place.name, stateShown: ctx.state != nil, state: d.place.state)
        GlassCard(padding: 18, cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    StopTile(place: d.place, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(StopKindLabel.eyebrow(place: d.place, tags: d.tags))
                            .font(.system(size: 11, weight: .semibold)).tracking(1.0)
                            .foregroundStyle(Theme.textSecondary).lineLimit(2)
                        Text(hero.title)
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(dts.isAccessibilitySize ? 3 : 2)
                            .minimumScaleFactor(0.85)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(PlaceNames.display(d.place.name)), \(StopKindLabel.label(place: d.place, tags: d.tags))"))
                .accessibilityAddTraits(.isHeader)

                badges
                if !ctx.cells.isEmpty {
                    GebietsLeiste(cells: ctx.cells, onTap: onBrandTap)
                }
                lineFamilies
            }
        }
    }

    private var ownSkiBadgeNeeded: Bool {
        ctx.details.skiArea != nil && !ctx.cells.contains { $0.level == .ski }
    }

    /// Region chips without a logo cell and without the ski area's own name.
    private var regionChips: [Region] {
        let cellNames = Set(ctx.cells.map { PlaceNormalizer.fold($0.name) })
        let ids = PlaceMarkSelection.detailRegions(tags: ctx.tags, skiArea: ctx.details.skiArea) { id in
            ctx.details.regions.first { $0.id == id }?.name
        }
        return ids.compactMap { t in ctx.details.regions.first { $0.id == t.id } }
            .filter { !cellNames.contains(PlaceNormalizer.fold($0.name)) }
            .prefix(3).map { $0 }
    }

    private var badges: some View {
        MetaFlowLayout(spacing: 6, lineSpacing: 6) {
            if let state = ctx.state { StateMarkW(state: state, style: .full) }
            if ownSkiBadgeNeeded, let ski = ctx.details.skiArea { SkiPassBadge(area: ski, style: .full) }
            ForEach(regionChips) { RegionChip(name: $0.name, size: .detail) }
            ForEach(PlaceMarkSelection.heroChips(tags: ctx.tags).prefix(3)) { PlaceMarkChip(mark: $0, size: .detail) }
            KlimaTicketChip(status: ctx.tags.klimaTicket.status)
        }
    }

    @ViewBuilder
    private var lineFamilies: some View {
        let groups = ctx.groups
        if !groups.isEmpty {
            let total = groups.reduce(0) { $0 + $1.lines.count }
            let size: PlateSize = total <= 4 ? .l : .m
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups.prefix(4), id: \.kind) { g in
                    LineFamilyRow(kind: g.kind, badges: g.lines.map { LineBadge($0.line, size: size, services: ctx.services) }, size: size)
                }
                if groups.count > 4 {
                    let rest = groups.dropFirst(4).reduce(0) { $0 + $1.lines.count }
                    Button(action: onShowLines) {
                        Text("und \(rest) weitere Linien").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Lines

struct StopLinesSection: View {
    let ctx: StopContext
    @State private var expanded: Set<LineKind> = []

    private static let collapsedCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StopSectionTitle(text: "Linien an dieser Haltestelle")
            SurfaceCard(padding: 16, cornerRadius: 24) {
                if ctx.details.lines.isEmpty || linesExpired {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(linesExpired ? PlaceCopy.outdatedLines : PlaceCopy.noLines)
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(ctx.groups, id: \.kind) { g in
                            group(g.kind, g.lines)
                        }
                    }
                }
            }
        }
    }

    private var linesExpired: Bool {
        if let until = ctx.details.dataValidUntil { return until < Date() }
        return false
    }

    @ViewBuilder
    private func group(_ kind: LineKind, _ lines: [StopLine]) -> some View {
        let season = groupSeason(lines)
        VStack(alignment: .leading, spacing: 10) {
            LineFamilyHeader(kind: kind, count: lines.count, season: season)
            if kind == .fern || kind == .nacht {
                LongDistanceSummaryRow(badges: lines.map { LineBadge($0.line, size: .m, services: ctx.services) },
                                       destinations: destinations(lines))
            } else {
                let shown = expanded.contains(kind) ? lines : Array(lines.prefix(Self.collapsedCount))
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(shown) { row($0, kind: kind) }
                }
                if lines.count > Self.collapsedCount {
                    Button {
                        withMotion(Motion.smooth) {
                            if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
                        }
                    } label: {
                        Text(expanded.contains(kind) ? "Weniger anzeigen" : "Alle \(lines.count) Linien anzeigen")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func groupSeason(_ lines: [StopLine]) -> String? {
        let texts = lines.map { SeasonTag.text(for: $0.line.flags) }
        guard let first = texts.first, let t = first, texts.allSatisfy({ $0 == t }) else { return nil }
        return t
    }

    private func destinations(_ lines: [StopLine]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for l in lines {
            let names = l.directions + [ctx.terminus(l.line.termini?.to, id: l.line.termini?.toStopID)].compactMap { $0 }
            for n in names where seen.insert(PlaceNormalizer.fold(n)).inserted { out.append(n) }
        }
        return Array(out.prefix(4))
    }

    private func row(_ l: StopLine, kind: LineKind) -> some View {
        let t = l.line.termini
        var from = ctx.terminus(t?.from, id: t?.fromStopID)
        var to = ctx.terminus(t?.to, id: t?.toStopID)
        if from == nil && to == nil { to = l.directions.first.map { PlaceTitle.display(name: $0, stateShown: false) } }
        if from == to { from = nil }
        let op = l.line.operatorName ?? l.line.operatorLegalName.map { ctx.index?.operatorName($0) ?? OperatorNames.display($0) }
        let operatorText = [op, l.line.network.flatMap { $0 == .international ? nil : $0.rawValue }].compactMap { $0 }
            .reduce(into: [String]()) { if !$1.isEmpty && !$0.contains($1) { $0.append($1) } }.joined(separator: " · ")
        let foreign = l.line.states.compactMap(FederalState.init(rawValue:))
            .filter { $0 != ctx.state && $0 != .foreign }.prefix(2).map { $0 }
        let season = SeasonTag.text(for: l.line.flags)
        return StopLineRow(line: l, badge: LineBadge(l.line, size: .m, services: ctx.services), from: from, to: to,
                           operatorText: operatorText.isEmpty ? nil : operatorText, foreignStates: foreign, season: season,
                           spoken: SpokenLabels.lineRow(l.line, from: from, to: to, services: ctx.services))
    }
}

// MARK: - Ski

struct StopSkiSection: View {
    let ctx: StopContext
    var onWebsite: (LogoPackManifest.Brand) -> Void

    var body: some View {
        if let area = ctx.details.skiArea {
            VStack(alignment: .leading, spacing: 10) {
                StopSectionTitle(text: "Skigebiet", symbol: "mountain.2.fill")
                SkiPassCard(area: area, valleyStation: valleyText, allianceNames: allianceNames,
                            brand: ctx.brands?.ski, liftBrand: ctx.brands?.lift.first, onWebsite: onWebsite)
            }
        }
    }

    private var valleyText: String? {
        guard let l = ctx.tags.lift, l.role == .valley, l.confidence >= PlaceTags.badgeMinConfidence else { return nil }
        var parts = ["Talstation " + l.name]
        if let d = l.distanceMeters { parts.append("\(d) m") }
        if let m = l.walkMinutes { parts.append("\(m) min zu Fuß") }
        return parts.joined(separator: " · ")
    }

    private var allianceNames: [String] {
        ctx.tags.skiAlliances.compactMap { ctx.index?.skiArea(id: $0)?.name }
    }
}

// MARK: - KlimaTicket

struct StopKlimaTicketCard: View {
    let ctx: StopContext
    /// Trips of the user that start or end here.
    let tripCount: Int
    let tripValue: Double
    var onTrips: () -> Void

    var body: some View {
        let validity = ctx.tags.klimaTicket
        VStack(alignment: .leading, spacing: 10) {
            StopSectionTitle(text: "KlimaTicket")
            SurfaceCard(padding: 16, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(validity.status))
                            .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(LinearGradient(colors: [tint(validity.status), tint(validity.status).mix(with: .black, by: 0.25)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: .rect(cornerRadius: 13, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(validity)).font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(subtitle(validity)).font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if validity.status == .valid || validity.status == .border {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(ctx.details.klimaTicketProducts.enumerated()), id: \.offset) { i, p in
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positiveText).accessibilityHidden(true)
                                    Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    Spacer(minLength: 6)
                                    Text(scope(i)).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    if tripCount > 0 {
                        Button(action: onTrips) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(tripCount)").font(Theme.Typography.numberSmall).foregroundStyle(Theme.textPrimary)
                                    Text(tripCount == 1 ? "Fahrt hier" : "Fahrten hier").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Format.euro(tripValue, decimals: 2)).font(Theme.Typography.numberSmall).foregroundStyle(Theme.positiveText)
                                    Text("Normalpreis-Wert").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                                    .padding(.leading, 6)
                            }
                            .padding(12)
                            .background(Theme.surfaceSecondary, in: .rect(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(tripCount) \(tripCount == 1 ? "Fahrt" : "Fahrten") hier, Normalpreis-Wert \(Format.euro(tripValue, decimals: 2))"))
                        .accessibilityHint(Text("Öffnet deine Fahrten"))
                    }
                }
            }
        }
    }

    private func tint(_ s: KlimaTicketValidity.Status) -> Color {
        switch s {
        case .valid: Color(hex: "#23876A")
        case .check: Color(hex: "#C9622C")
        case .notIncluded: Color(hex: "#C23B3B")
        case .border: Color(hex: "#2A6FD1")
        }
    }

    private func symbol(_ s: KlimaTicketValidity.Status) -> String {
        switch s {
        case .valid: "checkmark.seal.fill"
        case .check: "questionmark.circle.fill"
        case .notIncluded: "xmark.seal.fill"
        case .border: "arrow.triangle.swap"
        }
    }

    private func title(_ v: KlimaTicketValidity) -> String {
        switch v.status {
        case .valid: "Mit deinem KlimaTicket gratis"
        case .check: "KlimaTicket: bitte prüfen"
        case .notIncluded: "Nicht im KlimaTicket enthalten"
        case .border: "Im Übergangsbereich"
        }
    }

    private func subtitle(_ v: KlimaTicketValidity) -> String {
        switch v.status {
        case .valid:
            let nets = ctx.details.lines.compactMap(\.line.network).filter { $0 != .international && $0 != .oebb }
            let top = Dictionary(grouping: nets, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            return top?.displayName ?? "Gültig in ganz Österreich"
        case .check: return v.reason ?? "Ob die Haltestelle im KlimaTicket liegt, ist nicht eindeutig."
        case .notIncluded: return v.reason ?? "Hier gilt dein KlimaTicket nicht."
        case .border: return v.reason ?? "Teilweise im Geltungsbereich – am Rand des Netzes."
        }
    }

    private func scope(_ i: Int) -> String {
        i == 0 ? "Österreich" : (ctx.state?.displayName ?? "Region")
    }
}

// MARK: - Facts

struct StopFactsSection: View {
    let ctx: StopContext
    var onBrandTap: (LogoPackManifest.Brand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StopSectionTitle(text: "Über diese Haltestelle")
            SurfaceCard(padding: 16, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    if let state = ctx.state {
                        fact("Bundesland") { StateMarkW(state: state, style: .full) }
                    }
                    if let bezirk { fact("Bezirk") { Text(bezirk).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary) } }
                    if let gem = ctx.place.municipality, !gem.isEmpty {
                        fact("Gemeinde") { Text(gem).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary) }
                    }
                    if !ctx.details.regions.isEmpty {
                        fact("Region") {
                            MetaFlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(ctx.details.regions.prefix(4)) { RegionChip(name: $0.name, size: .detail) }
                            }
                        }
                    }
                    if !tourism.isEmpty {
                        fact("Tourismus") {
                            MetaFlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(tourism) { b in
                                    Button { onBrandTap(b) } label: {
                                        BrandChip(brand: b, size: .detail) { Text(b.name).font(.footnote.weight(.semibold)) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    fact("Ausstattung") { facilities }
                    fact("Haltestellen-ID", divider: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ctx.place.id).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                            if let eva = ctx.place.extId, !eva.isEmpty {
                                Text("EVA \(eva)").font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var tourism: [LogoPackManifest.Brand] {
        guard let b = ctx.brands else { return [] }
        var seen = Set<String>()
        return (b.local + b.regions + [b.land].compactMap { $0 }).filter { seen.insert($0.id).inserted }
            .filter { LogoPackStore.shared.image($0, large: false, dark: false) != nil }
    }

    private var bezirk: String? {
        if let n = ctx.tags.wienBezirk, let name = ctx.details.wienBezirkName { return "\(n). Bezirk · \(name)" }
        if let name = ctx.details.bezirkName { return "Bezirk \(name)" }
        return nil
    }

    @ViewBuilder
    private var facilities: some View {
        let marks = PlaceMarkSelection.detailMarks(tags: ctx.tags).filter { [.facility].contains($0.group) && $0.kind != .klimaticket }
        if marks.isEmpty {
            Text("Keine Angaben zur Barrierefreiheit").font(.subheadline).foregroundStyle(Theme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MetaFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(marks) { PlaceMarkChip(mark: $0, size: .detail) }
                }
                if ctx.tags.accessibility == nil {
                    Text("Keine Angaben zur Barrierefreiheit").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func fact(_ label: String, divider: Bool = true, @ViewBuilder _ value: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary).frame(width: 104, alignment: .leading)
                value().frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 11)
            if divider { Divider().overlay(Theme.separator) }
        }
    }
}

// MARK: - Sources

struct StopSourcesFooter: View {
    let ctx: StopContext
    var liveShown = false

    var body: some View {
        let store = LogoPackStore.shared
        let brands = [ctx.brands?.ski, ctx.brands?.alliance].compactMap { $0 }
            + (ctx.brands?.local ?? []) + (ctx.brands?.regions ?? []) + (ctx.brands?.lift ?? []) + [ctx.brands?.land].compactMap { $0 }
        let shown = (ctx.cells + brands).filter { store.image($0, large: false, dark: false) != nil }
        let wappen = ctx.state.map { store.wappen($0, size: .chip) != nil } ?? false
        let text = PlaceCopy.footer(attribution: ctx.details.attribution, liveShown: liveShown,
                                    logoOwners: BrandText.owners(shown), showsWappen: wappen)
        Text(text)
            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
