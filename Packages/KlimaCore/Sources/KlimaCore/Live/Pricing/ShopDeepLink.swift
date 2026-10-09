import Foundation

/// Purchase hand-off to the ÖBB ticket shop (SPEC §B3.7, §2.5). KlimaBilanz never buys: the app opens this link in
/// `SFSafariViewController`. Prefer `Journey.shopURL` (the HAFAS `trfRes` link) when present.
///
/// `https://shop.oebbtickets.at/de/ticket?cref=klimabilanz&stationOrigEva=<9 digits>&stationDestEva=<9 digits>&outwardDateTime=<yyyy-MM-ddTHH:mm Vienna>`
/// (+ `&outwardArrival=true` for arrive-by). Whether the shop SPA applies the prefill is [ASSUMED].
public enum ShopDeepLink {
    public static let base = "https://shop.oebbtickets.at/de/ticket"
    public static let cref = "klimabilanz"

    /// Pure. `from` / `to` are EVA numbers (HAFAS extId = shop station `number`).
    public static func url(from: Int, to: Int, date: Date, arrival: Bool = false) -> URL {
        var items: [(String, String)] = [
            ("cref", cref),
            ("stationOrigEva", eva(from)),
            ("stationDestEva", eva(to)),
            ("outwardDateTime", minuteString(date)),
        ]
        if arrival { items.append(("outwardArrival", "true")) }
        let query = items.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "\(base)?\(query)")!
    }

    /// String extIds ("1290401"); nil when either is not a plain number.
    public static func url(from: String, to: String, date: Date, arrival: Bool = false) -> URL? {
        guard let a = Int(from.trimmingCharacters(in: .whitespaces)), let b = Int(to.trimmingCharacters(in: .whitespaces)),
              a > 0, b > 0 else { return nil }
        return url(from: a, to: b, date: date, arrival: arrival)
    }

    /// 9-digit zero-padded EVA ("001290401").
    static func eva(_ n: Int) -> String { String(format: "%09d", n) }

    /// "2026-10-10T08:28" (Vienna wall clock, no offset).
    static func minuteString(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0)
    }

    /// RFC 3986 unreserved characters stay, everything else (":" included) is percent-encoded.
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
