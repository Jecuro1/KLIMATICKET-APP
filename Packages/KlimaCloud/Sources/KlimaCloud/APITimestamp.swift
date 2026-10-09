import Foundation

/// Wire timestamps (contract §3.4) <-> Date without DateFormatter, at microsecond precision.
///
/// Writes the canonical form `YYYY-MM-DDTHH:MM:SS.ffffffZ` (UTC, exactly six fraction digits). Reads RFC 3339 with any
/// fraction length and the offsets `Z`, `±HH`, `±HHMM`, `±HH:MM`, `±HH:MM:SS`, with a "T", "t" or space separator, so
/// microsecond precision survives a round trip through the server.
public enum APITimestamp {
    /// `2026-10-09T07:00:00.123456Z` (UTC, microseconds).
    public static func string(from date: Date) -> String {
        let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
        var seconds = micros / 1_000_000
        var fraction = micros % 1_000_000
        if fraction < 0 { fraction += 1_000_000; seconds -= 1 }
        var days = seconds / 86_400
        var secondOfDay = seconds % 86_400
        if secondOfDay < 0 { secondOfDay += 86_400; days -= 1 }
        let (year, month, day) = civil(fromDays: days)
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(secondOfDay / 3600, 2)):\(pad(secondOfDay % 3600 / 60, 2)):"
            + "\(pad(secondOfDay % 60, 2)).\(pad(fraction, 6))Z"
    }

    public static func date(from string: String) -> Date? {
        let b = Array(string.utf8)
        var i = 0

        func digits(_ count: Int) -> Int64? {
            guard i + count <= b.count else { return nil }
            var value: Int64 = 0
            for k in i..<(i + count) {
                guard b[k] >= 48, b[k] <= 57 else { return nil }
                value = value * 10 + Int64(b[k] - 48)
            }
            i += count
            return value
        }
        func take(_ char: UInt8) -> Bool {
            guard i < b.count, b[i] == char else { return false }
            i += 1
            return true
        }

        guard let year = digits(4), take(45), let month = digits(2), take(45), let day = digits(2),
              (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year) else { return nil }
        var hour: Int64 = 0, minute: Int64 = 0, second: Int64 = 0
        var micros: Int64 = 0
        var offset: Int64 = 0
        if i < b.count {
            guard take(84) || take(116) || take(32) else { return nil }   // "T", "t", " "
            guard let h = digits(2), take(58), let m = digits(2) else { return nil }
            hour = h
            minute = m
            if take(58) {
                guard let s = digits(2) else { return nil }
                second = s
                if take(46) || take(44) {   // "." or ","
                    // Digits after the sixth are truncated, exactly like the server canonicalizes (§3.4).
                    var scale: Int64 = 100_000
                    var count = 0
                    while i < b.count, b[i] >= 48, b[i] <= 57 {
                        micros += Int64(b[i] - 48) * scale
                        scale /= 10
                        i += 1
                        count += 1
                    }
                    guard count > 0 else { return nil }
                }
            }
            guard hour <= 24, minute <= 59, second <= 60 else { return nil }
            if i < b.count {
                if take(90) || take(122) {   // "Z" / "z"
                    offset = 0
                } else {
                    let sign: Int64
                    if take(43) { sign = 1 } else if take(45) { sign = -1 } else { return nil }
                    guard let oh = digits(2) else { return nil }
                    var om: Int64 = 0, os: Int64 = 0
                    if take(58) {
                        guard let m = digits(2) else { return nil }
                        om = m
                        if take(58) {
                            guard let s = digits(2) else { return nil }
                            os = s
                        }
                    } else if let m = digits(2) {
                        om = m
                    }
                    guard oh <= 23, om <= 59, os <= 59 else { return nil }
                    offset = sign * (oh * 3600 + om * 60 + os)
                }
            }
            guard i == b.count else { return nil }
        }
        let seconds = days(fromCivil: year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: Double(seconds) + Double(micros) / 1_000_000)
    }

    private static func pad(_ value: Int64, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    private static func isLeap(_ year: Int64) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    private static func daysIn(month: Int64, year: Int64) -> Int64 {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 (proleptic Gregorian, H. Hinnant's algorithm).
    private static func days(fromCivil year: Int64, _ month: Int64, _ day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civil(fromDays days: Int64) -> (Int64, Int64, Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

/// JSON coders for the API: dates are canonical `APITimestamp` strings.
public enum CloudCoding {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(APITimestamp.string(from: date))
        }
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            if let date = APITimestamp.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unbekanntes Datumsformat: \(raw)")
        }
        return d
    }
}
