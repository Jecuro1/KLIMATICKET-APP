import Foundation
import KlimaCore

/// Sample spreadsheet for the CI screenshots of the import flow ("importMapping", "importPreview", "importResult").
/// Looks like a typical hand-made Excel sheet: semicolon-separated, Windows line endings, de-AT numbers in every flavour
/// ("€ 23,50", "65,90", "7.20", "1,50"), one quoted note with an embedded semicolon, one row without price (estimated),
/// a duplicate of an existing trip, a duplicate inside the file and two broken rows.
enum RepSampleData {
    static let fileName = "Fahrten 2026 – Export.csv"

    static func csv(duplicating existing: TripEntity?, now: Date = Date()) -> Data {
        let cal = Calendar.vienna
        func day(_ offset: Int) -> String {
            let d = cal.date(byAdding: .day, value: -offset, to: now) ?? now
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return String(format: "%02d.%02d.%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2026)
        }
        var lines = ["Datum;Abfahrt;Von;Nach;Verkehrsmittel;Normalpreis;H+R;Zweck;Bemerkung"]
        lines.append("\(day(41));07:12;St. Anton;Innsbruck;RJX;€ 23,50;ja;Arbeit;")
        lines.append("\(day(39));16:40;Salzburg;Wien;Railjet;65,90;nein;Freizeit;\"Konzert; Musikverein\"")
        lines.append("\(day(36));08:05;Linz;Wels;REX;7.20;ja;Arbeit;")
        lines.append("\(day(33));09:30;Innsbruck;Kufstein;Zug;;nein;Besuch;Preis fehlt – wird geschätzt")
        lines.append("\(day(31));18:15;Bregenz;Dornbirn;Bus;1,50;nein;Erledigung;Komma richtig erkannt")
        lines.append("31.02.2026;07:12;St. Anton;Landeck;Zug;6,70;ja;Arbeit;Tippfehler im Datum")
        if let existing {
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: existing.date)
            let date = String(format: "%02d.%02d.%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2026)
            let time = String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
            let fare = String(format: "%.2f", existing.fareEUR).replacingOccurrences(of: ".", with: ",")
            lines.append("\(date);\(time);\(existing.fromName);\(existing.toName);\(existing.mode.displayName);\(fare);\(existing.isRoundTrip ? "ja" : "nein");;")
        }
        lines.append("\(day(27));10:02;Graz;Leoben;Zug;14,90;ja;Ausflug;")
        lines.append("\(day(27));10:02;Graz;Leoben;Zug;14,90;ja;Ausflug;zweimal eingetragen")
        lines.append("\(day(22));07:48;Hall in Tirol;Omas Garten;Bus;;nein;Besuch;")
        lines.append("\(day(18));06:55;Wien;St. Pölten;WESTbahn;19,10;ja;Dienstreise;")
        lines.append("\(day(12));13:20;Villach;Klagenfurt;S-Bahn;€ 8,40;nein;Freizeit;")
        lines.append("\(day(6));19:05;Feldkirch;Bludenz;Zug;5,60;ja;Arbeit;")
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
