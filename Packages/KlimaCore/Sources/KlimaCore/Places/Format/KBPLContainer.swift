import Foundation

/// The KBPL file container (docs/ENRICH_SPEC.md §1.2). Little endian, 64-byte header:
///
/// ```
///  0 "KBPL" | 4 u16 version | 6 u16 flags | 8 u32 nRecords | 12 u32 nGemeinden
/// 16 v1: u32 × 8 offset/length of RECS, STRS, GEMS, EXTR      v2: reserved 0
/// 48 u32 nStopRecords | 52 u32 dirOffset (v2) | 56 u32 dirCount (v2) | 60 reserved
/// v2 directory entry (28 B): fourcc | u32 offset | u32 storedLength | u32 rawLength | u8 codec | u8 0 |
///                            u16 countHint | u32 crc32 (of the raw bytes) | u32 reserved
/// ```
///
/// Readers accept versions 1 and 2. Unknown fourccs are ignored; a missing optional section turns its feature off.
/// Section errors (out of bounds, unknown codec, Inflate error, CRC mismatch) throw
/// `PlaceDataset.ReadError.corrupt(section:)`.
struct KBPLContainer {
    struct Entry: Equatable {
        var fourcc: String
        var offset: Int
        var storedLength: Int
        var rawLength: Int
        /// 0 = stored, 1 = raw DEFLATE.
        var codec: UInt8
        var countHint: Int
        /// nil for v1 files (no checksums).
        var crc32: UInt32?
    }

    static let headerSize = 64
    static let entrySize = 28
    /// Largest decoded section accepted (the biggest today, STRS, is 1.6 MB).
    static let maxRawLength = 256 << 20

    let data: Data
    let version: Int
    let flags: Int
    let nRecords: Int
    let nGemeinden: Int
    let nStopRecords: Int
    /// Directory in file order (v1: the four fixed sections).
    let entries: [Entry]

    typealias ReadError = PlaceDataset.ReadError

    init(data: Data) throws {
        self.data = data
        let header: (Int, Int, Int, Int, Int, [Entry]) = try data.withUnsafeBytes { raw in
            guard raw.count >= Self.headerSize else { throw ReadError.truncated }
            guard raw[0] == 0x4B, raw[1] == 0x42, raw[2] == 0x50, raw[3] == 0x4C else { throw ReadError.badMagic }   // "KBPL"
            let version = Int(Self.u16(raw, 4))
            guard version == 1 || version == 2 else { throw ReadError.unsupportedVersion(version) }
            let nRec = Int(Self.u32(raw, 8)), nGem = Int(Self.u32(raw, 12)), nStops = Int(Self.u32(raw, 48))
            var entries: [Entry] = []
            if version == 1 {
                for (k, tag) in ["RECS", "STRS", "GEMS", "EXTR"].enumerated() {
                    let off = Int(Self.u32(raw, 16 + 8 * k)), len = Int(Self.u32(raw, 20 + 8 * k))
                    guard off <= raw.count, len <= raw.count - off else { throw ReadError.truncated }
                    entries.append(Entry(fourcc: tag, offset: off, storedLength: len, rawLength: len, codec: 0, countHint: 0,
                                         crc32: nil))
                }
            } else {
                let dirOff = Int(Self.u32(raw, 52)), dirCount = Int(Self.u32(raw, 56))
                guard dirOff >= Self.headerSize, dirCount <= 4096, dirOff <= raw.count,
                      dirCount * Self.entrySize <= raw.count - dirOff else { throw ReadError.truncated }
                for i in 0..<dirCount {
                    let e = dirOff + Self.entrySize * i
                    let tag = String(decoding: UnsafeRawBufferPointer(rebasing: raw[e..<(e + 4)]), as: UTF8.self)
                    entries.append(Entry(fourcc: tag, offset: Int(Self.u32(raw, e + 4)), storedLength: Int(Self.u32(raw, e + 8)),
                                         rawLength: Int(Self.u32(raw, e + 12)), codec: raw[e + 16],
                                         countHint: Int(Self.u16(raw, e + 18)), crc32: Self.u32(raw, e + 20)))
                }
            }
            return (version, Int(Self.u16(raw, 6)), nRec, nGem, nStops, entries)
        }
        (version, flags, nRecords, nGemeinden, nStopRecords, entries) = header
    }

    /// The first directory entry with this fourcc.
    func entry(_ fourcc: String) -> Entry? { entries.first { $0.fourcc == fourcc } }

    func has(_ fourcc: String) -> Bool { entry(fourcc) != nil }

    /// Decoded (inflated, CRC-checked) bytes of a section; nil if the file has no such section.
    func section(_ fourcc: String) throws -> [UInt8]? {
        guard let e = entry(fourcc) else { return nil }
        return try decode(e)
    }

    /// Like `section` but a missing section is an error (mandatory sections: RECS, STRS, GEMS).
    func required(_ fourcc: String) throws -> [UInt8] {
        guard let bytes = try section(fourcc) else { throw ReadError.corrupt(section: fourcc) }
        return bytes
    }

    func decode(_ e: Entry) throws -> [UInt8] {
        let corrupt = ReadError.corrupt(section: e.fourcc)
        guard e.offset >= 0, e.storedLength >= 0, e.offset <= data.count, e.storedLength <= data.count - e.offset,
              e.rawLength <= Self.maxRawLength else { throw corrupt }
        let out: [UInt8] = try data.withUnsafeBytes { raw in
            let stored = UnsafeRawBufferPointer(rebasing: raw[e.offset..<(e.offset + e.storedLength)])
            switch e.codec {
            case 0:
                guard e.rawLength == e.storedLength else { throw corrupt }
                return [UInt8](stored)
            case 1:
                // DEFLATE cannot expand beyond ~1032:1; a larger claim is a corrupt directory, not a reason to allocate
                guard e.rawLength <= e.storedLength * 1032 + 1024 else { throw corrupt }
                do {
                    return try Inflate.decompress(stored, expectedSize: e.rawLength)
                } catch {
                    throw corrupt
                }
            default:
                throw corrupt
            }
        }
        if let crc = e.crc32, CRC32.checksum(out) != crc { throw corrupt }
        return out
    }

    @inline(__always) static func u32(_ raw: UnsafeRawBufferPointer, _ o: Int) -> UInt32 {
        raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian
    }

    @inline(__always) static func u16(_ raw: UnsafeRawBufferPointer, _ o: Int) -> UInt16 {
        raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian
    }
}
