import Foundation

/// The stop detail screen's data (docs/ENRICH_SPEC.md §2.1 `StopDetails`, §3.2): every line, the compact lines,
/// the tags resolved to ski area and regions, Bezirk names, neighbours for the map hero, KlimaTicket products and the
/// source footer for the layers actually loaded.
enum StopDetailsBuilder {
    /// §1.10.2 footer parts (the live part „Abfahrten: ÖBB-Fahrplanauskunft (live)“ is added by the UI).
    static let officialAttribution = "Linien: ÖBB-GTFS, Wiener Linien, Land Steiermark, ÖV-Güteklassen"
    static let osmAttribution = "Skigebiet, Lifte, weitere Linien: © OpenStreetMap-Mitwirkende (ODbL)"
    /// Neighbours on the map hero: ≤ 8 within 600 m.
    static let neighbourLimit = 8
    static let neighbourRadius = 600.0

    static func build(index: PlaceIndex, record ri: Int) -> StopDetails {
        let place = index.place(ri)
        let e = index.enrichment
        let s = e != nil && ri < index.enrichIndex.count ? Int(index.enrichIndex[ri]) : -1
        let lines: [StopLine]
        if let e, s >= 0 {
            lines = e.stopLines(s)
        } else if e == nil {
            lines = index.legacyLines(record: ri).map { StopLine(line: $0, confidence: .timetable) }
        } else {
            lines = []
        }
        let tags = place.tags
        let catalog = e?.catalog ?? .empty
        let skiArea = tags.primarySkiArea.flatMap { catalog.areas[$0.id] }
        var regions: [Region] = []
        for t in tags.regions + tags.landscapes where t.confidence >= PlaceTags.regionMinConfidence {
            if let r = catalog.regions[t.id], !regions.contains(where: { $0.id == r.id }) { regions.append(r) }
        }
        var neighbours: [(place: Place, distanceMeters: Double)] = []
        if place.kind.isStopLike {
            neighbours = index.nearest(to: place.coordinate, limit: neighbourLimit + 1, maxMeters: neighbourRadius)
                .filter { $0.place.id != place.id }
            if neighbours.count > neighbourLimit { neighbours.removeLast(neighbours.count - neighbourLimit) }
        }
        var attribution: [String] = []
        if index.dataInfo.formatVersion >= 2 || !lines.isEmpty { attribution.append(officialAttribution) }
        if index.dataInfo.hasOSMLayer { attribution.append(osmAttribution) }
        return StopDetails(place: place, lines: lines, compactLines: place.lines, tags: tags, skiArea: skiArea,
                           regions: regions, bezirkName: catalog.bezirkName(tags.bezirk),
                           wienBezirkName: catalog.wienBezirkName(tags.wienBezirk), neighbours: neighbours,
                           klimaTicketProducts: e == nil ? [] : catalog.products(for: tags.klimaTicket),
                           attribution: attribution, dataValidUntil: catalog.validUntil)
    }
}

extension PlaceIndex {
    /// Everything the stop detail shows (lines M3–M7, compact lines M8, tags, ski area, regions, Bezirk, neighbours,
    /// KlimaTicket products, source footer). Place id or legacy station id; nil for unknown ids.
    public func details(for placeID: String) -> StopDetails? {
        recordIndex(placeID).map { StopDetailsBuilder.build(index: self, record: $0) }
    }
}
