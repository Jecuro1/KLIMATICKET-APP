import Foundation

/// Operator display names (docs/ENRICH_SPEC.md E4): „Österreichische Postbus AG“ → „Postbus“,
/// „OEBB Personenverkehr AG Kundenservice“ → „ÖBB“. The data build applies the same table (`LineRef.operatorName`);
/// at runtime this maps live operator names (HAFAS) so live and offline lines read the same. Text only.
public enum OperatorNames {
    /// (folded prefix or fragment, display). First match wins; `contains` entries match anywhere.
    static let table: [(match: String, contains: Bool, display: String)] = [
        ("postbus", true, "Postbus"),
        ("obb-personenverkehr", false, "ÖBB"), ("obb personenverkehr", false, "ÖBB"), ("obb-pv", false, "ÖBB"),
        ("osterreichische bundesbahnen", false, "ÖBB"), ("austrian federal railways", false, "ÖBB"),
        ("wiener linien", false, "Wiener Linien"),
        ("wiener lokalbahnen", false, "Wiener Lokalbahnen"),
        ("holding graz", false, "Graz Linien"), ("graz linien", false, "Graz Linien"),
        ("linz linien", false, "Linz AG Linien"), ("linz ag", false, "Linz AG Linien"),
        ("innsbrucker verkehrsbetriebe", false, "IVB"),
        ("salzburg ag", false, "Salzburg AG"),
        ("salzburger lokalbahn", false, "Salzburger Lokalbahn"),
        ("stern & hafferl", false, "Stern & Hafferl"), ("stern und hafferl", false, "Stern & Hafferl"),
        ("montafonerbahn", false, "Montafonerbahn"),
        ("westbahn", false, "WESTbahn"),
        ("db fernverkehr", false, "DB"), ("db regio", false, "DB"), ("deutsche bahn", false, "DB"),
        ("steiermarkbahn", false, "Steiermarkbahn"),
        ("graz-koflacher", false, "GKB"), ("graz koflacher", false, "GKB"),
        ("raaberbahn", false, "Raaberbahn"), ("gysev", false, "Raaberbahn"),
        ("niederosterreichische verkehrsorganisation", false, "NÖVOG"),
        ("oberosterreichischer verkehrsverbund", false, "OÖVV"),
        ("klagenfurt mobil", false, "Klagenfurt Mobil"),
        ("dr. richard", false, "Dr. Richard"),
        ("blaguss", false, "Blaguss"),
        ("zillertaler verkehrsbetriebe", false, "Zillertaler Verkehrsbetriebe"),
    ]

    /// Legal-form suffixes dropped from names the table does not know („Ötztaler Verkehrsgesellschaft mbH“ →
    /// „Ötztaler Verkehrsgesellschaft“). Longest first.
    static let legalSuffixes = [" GmbH & Co. KG", " GmbH & Co KG", " Gesellschaft m.b.H.", " Gesellschaft mbH",
                                " Ges.m.b.H.", " Ges.m.b.H", " GesmbH", " Aktiengesellschaft", " Kundenservice",
                                " GmbH", " m.b.H.", " mbH", " s.r.o.", " s.r.o", " e.U.", " AG", " KG", " OG"]

    /// Display name of one operator; „A;B“ lists → „A / B“ (at most two, duplicates merged).
    public static func display(_ legal: String) -> String {
        let trimmed = legal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains(";") {
            var out: [String] = []
            for part in trimmed.split(separator: ";") {
                let d = single(String(part))
                if !d.isEmpty, !out.contains(d) { out.append(d) }
            }
            return out.prefix(2).joined(separator: " / ")
        }
        return single(trimmed)
    }

    static func single(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = PlaceNormalizer.fold(name)
        if folded == "obb" || folded == "oebb" { return "ÖBB" }
        for e in table where e.contains ? folded.contains(e.match) : folded.hasPrefix(e.match) { return e.display }
        var s = name
        var changed = true
        while changed {
            changed = false
            for suffix in legalSuffixes where s.count > suffix.count + 2 && s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
                changed = true
                break
            }
        }
        return s
    }
}
