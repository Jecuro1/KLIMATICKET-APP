import Foundation

/// German word for what a place is (rows, VoiceOver, detail eyebrow; docs/ENRICH_SPEC.md §2.5).
public enum StopKindLabel {
    /// „Hauptbahnhof“, „Bahnhof“, „U-Bahn“, „Straßenbahn“, „Schiffsanlegestelle“, „Seilbahn“, „Bushaltestelle“, „Ort“
    /// (+ „Adresse“, POI category for live rows). Tags win over the product bits; without tags (v1 data) the
    /// products and the name decide.
    public static func label(place: Place, tags: PlaceTags = .empty) -> String {
        switch place.kind {
        case .town: return "Ort"
        case .address: return "Adresse"
        case .poi: return place.poiCategoryLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "Ziel"
        case .station, .stop: break
        }
        let p = place.products
        let rail = tags.has(.trainStation) || tags.has(.mainStation) || place.kind == .station || p.isRail
        if tags.has(.mainStation) || (rail && isMainStationName(place.name)) { return "Hauptbahnhof" }
        if rail { return "Bahnhof" }
        if tags.has(.uBahn) || p.contains(.subway) { return "U-Bahn" }
        if tags.has(.tram) || p.contains(.tram) { return "Straßenbahn" }
        if tags.has(.ship) || p.contains(.ship) { return "Schiffsanlegestelle" }
        if tags.has(.cableCar) || (p.contains(.onDemandOrCable) && !p.contains(.bus) && !tags.has(.onDemand)) {
            return "Seilbahn"
        }
        return "Bushaltestelle"
    }

    /// Detail eyebrow (upper-case): „BUSHALTESTELLE · GEMEINDE WARTH“, „BAHNHOF · FERNVERKEHR & NACHTZUG“.
    public static func eyebrow(place: Place, tags: PlaceTags = .empty) -> String {
        let kind = label(place: place, tags: tags)
        var second: String?
        if kind == "Bahnhof" || kind == "Hauptbahnhof" {
            let fern = tags.has(.longDistance), nacht = tags.has(.nightTrain)
            if fern && nacht { second = "Fernverkehr & Nachtzug" } else if fern { second = "Fernverkehr" } else if nacht {
                second = "Nachtzug"
            }
        }
        if second == nil, let m = place.municipality, !m.isEmpty, place.kind != .town { second = "Gemeinde " + m }
        return [kind, second].compactMap { $0 }.joined(separator: " · ").uppercased(with: Locale(identifier: "de_AT"))
    }

    static func isMainStationName(_ name: String) -> Bool {
        let f = PlaceNormalizer.fold(name)
        return f.hasSuffix(" hbf") || f.hasSuffix(" hauptbahnhof") || f.contains(" hbf ") || f.contains(" hauptbahnhof ")
    }
}
