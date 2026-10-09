import Foundation

/// RFC-4180 CSV export (semicolon-separated for Austrian Excel, UTF-8 BOM).
public enum CSVExport {
    public static func trips(_ trips: [TripRecord], calendar: Calendar = .vienna) -> String {
        let header = ["Datum", "Uhrzeit", "Von", "Nach", "Verkehrsmittel", "Hin & Retour", "Distanz (km)", "Normalpreis (€)", "Wert gesamt (€)"]
        var lines = [header.map(escape).joined(separator: ";")]
        for t in trips.sorted(by: { $0.date < $1.date }) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: t.date)
            let date = String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            let row = [date, time, t.fromName, t.toName, t.mode.displayName, t.isRoundTrip ? "ja" : "nein",
                       decimal(t.totalDistanceKm, 1), decimal(t.fareEUR, 2), decimal(t.totalValue, 2)]
            lines.append(row.map(escape).joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ field: String) -> String {
        if field.contains(";") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func decimal(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }
}
