import Foundation

// Raw DEFLATE (RFC 1951) decoder and CRC-32 for KBPL v2 sections with codec 1 (docs/ENRICH_SPEC.md §1.3).
// Pure Swift: swift-corelibs-foundation has no zlib API, so iOS and the Linux CI run the same code path. Every
// malformed input throws (never traps, never reads or writes out of bounds); the output size is known up front
// (directory `rawLength`) and enforced exactly.

enum InflateError: Error, Equatable {
    case truncated, invalidBlockType, invalidStoredLength, invalidCodeLengths, invalidSymbol, invalidDistance, sizeMismatch
}

enum Inflate {
    private static let lengthBase: [UInt16] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
                                               83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
                                               5, 5, 0]
    private static let distBase: [UInt16] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
                                             1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra: [UInt8] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
                                             12, 12, 13, 13]
    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// Canonical Huffman code as a single-level table indexed by the next `maxLen` input bits (LSB first).
    /// Entry = symbol << 4 | code length (0 = no code for this bit pattern).
    struct Table {
        var entries: [UInt16]
        var maxLen: Int

        init(lengths: ArraySlice<UInt8>) throws {
            var count = [Int](repeating: 0, count: 16)
            for l in lengths where l > 0 { count[Int(l)] += 1 }
            var maxLen = 0
            for l in 1..<16 where count[l] > 0 { maxLen = l }
            if maxLen == 0 { maxLen = 1 }
            var left = 1
            for l in 1..<16 {
                left = (left << 1) - count[l]
                if left < 0 { throw InflateError.invalidCodeLengths }      // over-subscribed
            }
            var next = [Int](repeating: 0, count: 16)
            var code = 0
            for l in 1..<16 {
                next[l] = code
                code = (code + count[l]) << 1
            }
            let size = 1 << maxLen
            var entries = [UInt16](repeating: 0, count: size)
            for (sym, len) in lengths.enumerated() where len > 0 {
                let l = Int(len)
                let c = next[l]
                next[l] += 1
                var rev = 0
                for b in 0..<l where c & (1 << b) != 0 { rev |= 1 << (l - 1 - b) }
                let e = UInt16(truncatingIfNeeded: sym << 4 | l)
                var k = rev
                while k < size {
                    entries[k] = e
                    k += 1 << l
                }
            }
            self.entries = entries
            self.maxLen = maxLen
        }

        static let fixedLiteral: Table = {
            var l = [UInt8](repeating: 8, count: 288)
            for i in 144..<256 { l[i] = 9 }
            for i in 256..<280 { l[i] = 7 }
            return try! Table(lengths: l[...])      // the RFC 1951 fixed code is complete by construction
        }()
        static let fixedDistance: Table = try! Table(lengths: [UInt8](repeating: 5, count: 30)[...])
    }

    /// LSB-first bit reader over the input; never reads past its end.
    struct BitReader {
        let input: UnsafeRawBufferPointer
        var pos = 0
        var buffer: UInt64 = 0
        var count = 0

        init(_ input: UnsafeRawBufferPointer) { self.input = input }

        @inline(__always) mutating func refill() {
            while count <= 56 && pos < input.count {
                buffer |= UInt64(input[pos]) << UInt64(count)
                pos += 1
                count += 8
            }
        }

        @inline(__always) mutating func bits(_ k: Int) throws -> Int {
            if count < k {
                refill()
                if count < k { throw InflateError.truncated }
            }
            let v = Int(truncatingIfNeeded: buffer & ((1 << UInt64(k)) - 1))
            buffer >>= UInt64(k)
            count -= k
            return v
        }

        @inline(__always) mutating func decode(_ t: Table) throws -> Int {
            if count < t.maxLen { refill() }
            let e = Int(t.entries[Int(truncatingIfNeeded: buffer & ((1 << UInt64(t.maxLen)) - 1))])
            let l = e & 15
            if l == 0 { throw InflateError.invalidSymbol }
            if l > count { throw InflateError.truncated }
            buffer >>= UInt64(l)
            count -= l
            return e >> 4
        }

        /// Drops the bits up to the next byte boundary (stored blocks).
        mutating func alignToByte() {
            let drop = count & 7
            buffer >>= UInt64(drop)
            count -= drop
        }
    }

    /// Decodes a raw DEFLATE stream whose decoded size is known (KBPL directory `rawLength`).
    static func decompress(_ input: [UInt8], expectedSize: Int) throws -> [UInt8] {
        try input.withUnsafeBytes { try decompress($0, expectedSize: expectedSize) }
    }

    static func decompress(_ input: UnsafeRawBufferPointer, expectedSize: Int) throws -> [UInt8] {
        guard expectedSize >= 0 else { throw InflateError.sizeMismatch }
        var out = [UInt8](repeating: 0, count: expectedSize)
        let produced = try out.withUnsafeMutableBufferPointer { o in try run(input, o) }
        guard produced == expectedSize else { throw InflateError.sizeMismatch }
        return out
    }

    private static func run(_ input: UnsafeRawBufferPointer, _ out: UnsafeMutableBufferPointer<UInt8>) throws -> Int {
        var r = BitReader(input)
        var op = 0
        let cap = out.count
        var final = false
        while !final {
            final = try r.bits(1) == 1
            switch try r.bits(2) {
            case 0:
                r.alignToByte()
                let len = try r.bits(16), nlen = try r.bits(16)
                guard len == (~nlen & 0xFFFF) else { throw InflateError.invalidStoredLength }
                guard op + len <= cap else { throw InflateError.sizeMismatch }
                var remaining = len
                while remaining > 0 && r.count >= 8 {          // whole bytes still in the bit buffer
                    out[op] = UInt8(truncatingIfNeeded: r.buffer)
                    op += 1
                    r.buffer >>= 8
                    r.count -= 8
                    remaining -= 1
                }
                guard r.pos + remaining <= input.count else { throw InflateError.truncated }
                if remaining > 0 {
                    UnsafeMutableRawBufferPointer(UnsafeMutableBufferPointer(rebasing: out[op..<(op + remaining)]))
                        .copyMemory(from: UnsafeRawBufferPointer(rebasing: input[r.pos..<(r.pos + remaining)]))
                    op += remaining
                    r.pos += remaining
                }
            case 1:
                op = try inflateBlock(&r, out, op, Table.fixedLiteral, Table.fixedDistance)
            case 2:
                let hlit = try r.bits(5) + 257, hdist = try r.bits(5) + 1, hclen = try r.bits(4) + 4
                var cl = [UInt8](repeating: 0, count: 19)
                for i in 0..<hclen { cl[codeLengthOrder[i]] = UInt8(try r.bits(3)) }
                let clt = try Table(lengths: cl[...])
                var lens = [UInt8](repeating: 0, count: hlit + hdist)
                var i = 0
                while i < hlit + hdist {
                    let s = try r.decode(clt)
                    var repeatValue: UInt8 = 0, n = 0
                    switch s {
                    case 0..<16:
                        lens[i] = UInt8(s)
                        i += 1
                        continue
                    case 16:
                        guard i > 0 else { throw InflateError.invalidCodeLengths }
                        repeatValue = lens[i - 1]
                        n = 3 + (try r.bits(2))
                    case 17:
                        n = 3 + (try r.bits(3))
                    case 18:
                        n = 11 + (try r.bits(7))
                    default:
                        throw InflateError.invalidCodeLengths
                    }
                    guard i + n <= hlit + hdist else { throw InflateError.invalidCodeLengths }
                    for k in i..<(i + n) { lens[k] = repeatValue }
                    i += n
                }
                guard lens[256] > 0 else { throw InflateError.invalidCodeLengths }   // no end-of-block code
                let lit = try Table(lengths: lens[0..<hlit])
                let dist = try Table(lengths: lens[hlit...])
                op = try inflateBlock(&r, out, op, lit, dist)
            default:
                throw InflateError.invalidBlockType
            }
        }
        return op
    }

    @inline(__always)
    private static func inflateBlock(_ r: inout BitReader, _ out: UnsafeMutableBufferPointer<UInt8>, _ start: Int,
                                     _ lit: Table, _ dist: Table) throws -> Int {
        var op = start
        let cap = out.count
        while true {
            let s = try r.decode(lit)
            if s < 256 {
                guard op < cap else { throw InflateError.sizeMismatch }
                out[op] = UInt8(truncatingIfNeeded: s)
                op += 1
            } else if s == 256 {
                return op
            } else {
                let li = s - 257
                guard li < 29 else { throw InflateError.invalidSymbol }
                let lx = Int(lengthExtra[li])
                let len = Int(lengthBase[li]) + (lx > 0 ? try r.bits(lx) : 0)
                let di = try r.decode(dist)
                guard di < 30 else { throw InflateError.invalidDistance }
                let dx = Int(distExtra[di])
                let d = Int(distBase[di]) + (dx > 0 ? try r.bits(dx) : 0)
                guard d <= op else { throw InflateError.invalidDistance }
                guard op + len <= cap else { throw InflateError.sizeMismatch }
                var from = op - d
                for _ in 0..<len {                    // byte by byte: overlapping matches (d < len) repeat
                    out[op] = out[from]
                    op += 1
                    from += 1
                }
            }
        }
    }
}

/// CRC-32/ISO-HDLC (= zlib `crc32`, Python `zlib.crc32`) for the KBPL directory integrity check.
enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        table.withUnsafeBufferPointer { t in
            var crc: UInt32 = 0xFFFF_FFFF
            for b in bytes { crc = t[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
            return crc ^ 0xFFFF_FFFF
        }
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 { bytes.withUnsafeBytes { checksum($0) } }
}
