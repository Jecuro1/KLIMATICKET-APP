import Foundation

// MARK: radarmodes – „Betreiber“ of the radar filter (docs/RADAR_MODES.md §6): the operator as the Auskunft names it, with the two quirks of the
// recorded answers smoothed out. ÖBB trains are called „Nahreisezug“ in `opL` (data quirk) and long forms like „OEBB Personenverkehr AG Kundenservice“
// occur; WESTbahn as „WESTbahn Management GmbH“ or admin „3236__“. The measurement of 2026-11-13 found operator names on every radar vehicle and
// no `admin` code (§8): the name decides.

public enum RadarOperator {
    public static let unknown = "Unbekannt"

    /// The operator's display name.
    public static func name(of line: Line?) -> String {
        guard let line else { return unknown }
        switch line.admin?.trimmingCharacters(in: .whitespaces) {
        case "81____": return "ÖBB"
        case "3236__": return "WESTbahn"
        default: break
        }
        let raw = (line.operatorName ?? "").trimmingCharacters(in: .whitespaces)
        let folded = RadarText.fold(raw)
        if folded == "nahreisezug" || folded.hasPrefix("oebb") || folded.hasPrefix("obb ") || folded == "obb" || folded.contains("osterreichische bundesbahnen") {
            return "ÖBB"
        }
        if folded.contains("westbahn") { return "WESTbahn" }
        return raw.isEmpty ? unknown : raw
    }

    /// The operators of the loaded vehicles with their counts, most first (the filter's Betreiber section).
    public static func counts(_ vehicles: [RadarVehicle]) -> [(name: String, count: Int)] {
        Dictionary(grouping: vehicles, by: { name(of: $0.line) }).map { ($0.key, $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
