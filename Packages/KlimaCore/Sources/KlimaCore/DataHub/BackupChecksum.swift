import Foundation

// MARK: data – the CRC-32 of a version-3 backup (docs/DATA_HUB.md §3). It finds a damaged file (a copy cut short, a flipped
// byte, an editor that changed the encoding); it does not prove who wrote the file – anyone can compute a CRC-32 again.

/// CRC-32 (IEEE 802.3, the one of zip and PNG: reflected polynomial 0xEDB88320, start and final XOR 0xFFFFFFFF).
public enum DataHubCRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// Eight lowercase hex digits ("cbf43926" for "123456789").
    public static func hex(_ value: UInt32) -> String {
        let text = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 8 - text.count)) + text
    }
}

/// The checksum lives in the file itself as `"checksum" : "crc32:<8 hex>"`. It is computed over the whole file with the eight
/// hex digits set to zero, so the file stays plain JSON that a version-2 reader opens (it ignores the unknown key).
public enum BackupChecksum {
    /// What the exporter writes as the checksum's value before sealing.
    public static let placeholder = "crc32:00000000"
    public static let prefix = "crc32:"

    /// What a check tells. The copy says what it means: a checksum finds damage, it does not prove where the file came from.
    public enum Verdict: Equatable, Sendable {
        /// The file is unchanged since it was written.
        case intact(String)
        /// The file was changed or damaged after it was written.
        case damaged(expected: String, actual: String)
        /// A file without checksum (version 1 and 2 backups, or a file a person edited and stripped of it).
        case missing

        public var isDamaged: Bool {
            if case .damaged = self { return true }
            return false
        }

        public var title: String {
            switch self {
            case .intact: "Datei unversehrt"
            case .damaged: "Datei beschädigt"
            case .missing: "Ohne Prüfsumme"
            }
        }

        public var line: String {
            switch self {
            case .intact(let value): "Prüfsumme stimmt (\(value)). Die Datei ist so, wie die App sie geschrieben hat."
            case .damaged: "Prüfsumme stimmt nicht. Die Datei wurde beschädigt oder nachträglich verändert – wiederherstellen geht nicht."
            case .missing: "Ältere Sicherung ohne Prüfsumme. Sie lässt sich wiederherstellen, Beschädigungen erkennt die App hier aber nicht."
            }
        }
    }

    public static let honestyNote = "Die Prüfsumme (CRC-32) erkennt beschädigte Dateien. Absichtliche Änderungen beweist sie nicht – jeder kann sie neu berechnen."

    /// Replaces the placeholder with the file's checksum. nil when the placeholder is not there exactly once as the value of
    /// `checksum`.
    public static func seal(_ data: Data) -> Data? {
        guard let range = valueRange(in: data), data[range] == Data(placeholder.utf8) else { return nil }
        let crc = DataHubCRC32.hex(DataHubCRC32.checksum(data))
        var sealed = data
        sealed.replaceSubrange(range, with: Data((prefix + crc).utf8))
        return sealed
    }

    public static func verify(_ data: Data) -> Verdict {
        guard let range = valueRange(in: data) else { return .missing }
        let stored = String(decoding: data[range], as: UTF8.self)
        let expected = String(stored.dropFirst(prefix.count))
        var zeroed = data
        zeroed.replaceSubrange(range, with: Data(placeholder.utf8))
        let actual = DataHubCRC32.hex(DataHubCRC32.checksum(zeroed))
        return actual == expected ? .intact(actual) : .damaged(expected: expected, actual: actual)
    }

    /// The byte range of `crc32:xxxxxxxx` after the first `"checksum"` key (a key: a colon follows, perhaps after spaces).
    /// A note that contains the word carries it escaped or not followed by a colon, so it is never taken for the key.
    static func valueRange(in data: Data) -> Range<Data.Index>? {
        let bytes = [UInt8](data)
        let key = Array("\"checksum\"".utf8)
        let value = Array("\"\(prefix)".utf8)
        let digits = 8
        var start = 0
        while start + key.count <= bytes.count {
            guard let found = firstIndex(of: key, in: bytes, from: start) else { return nil }
            var cursor = found + key.count
            while cursor < bytes.count, isSpace(bytes[cursor]) { cursor += 1 }
            if cursor < bytes.count, bytes[cursor] == UInt8(ascii: ":") {
                cursor += 1
                while cursor < bytes.count, isSpace(bytes[cursor]) { cursor += 1 }
                let end = cursor + value.count + digits
                if end < bytes.count, Array(bytes[cursor..<(cursor + value.count)]) == value,
                   bytes[(cursor + value.count)..<end].allSatisfy(isHex), bytes[end] == UInt8(ascii: "\"") {
                    let lower = data.startIndex + cursor + 1
                    return lower..<(data.startIndex + end)
                }
            }
            start = found + 1
        }
        return nil
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        var index = start
        outer: while index + needle.count <= haystack.count {
            for offset in 0..<needle.count where haystack[index + offset] != needle[offset] {
                index += 1
                continue outer
            }
            return index
        }
        return nil
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }
    private static func isHex(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
    }
}
