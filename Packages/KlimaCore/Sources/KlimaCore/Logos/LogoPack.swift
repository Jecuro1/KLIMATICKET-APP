import Foundation

// Official logos and Landeswappen (docs/LOGO_SPEC.md): the remote-config block, the logo-pack manifest, a reader for
// the stored zip, the verifying installer, the brand resolver and the bundled Wappen asset names. Foundation only and
// Linux-tested; the app adds CryptoKit hashing, the URLSession download and image decoding (LOGO_SPEC §3.4).
// This file contains no logo data: ski-area and region logos come only from the Cloudflare logo pack.

// MARK: - Remote config ("logos" block of GET /v1/config or logos/config.json, LOGO_SPEC §3.2)

public struct LogoConfig: Codable, Sendable, Hashable {
    public struct Pack: Codable, Sendable, Hashable {
        public var schema: Int
        public var version: Int
        public var url: String
        /// Lowercase hex SHA-256 of the whole zip.
        public var sha256: String
        public var bytes: Int

        public init(schema: Int = LogoPackManifest.supportedSchema, version: Int, url: String, sha256: String, bytes: Int) {
            self.schema = schema
            self.version = version
            self.url = url
            self.sha256 = sha256
            self.bytes = bytes
        }
    }

    /// Master switch (`false`: own Wegzeichen everywhere, nothing is downloaded).
    public var enabled: Bool
    public var pack: Pack?
    /// Brand ids that must disappear immediately (takedown request) – their cached files are deleted too.
    public var revoked: [String]
    /// State codes (B, K, NÖ, OÖ, S, ST, T, V, W) whose bundled Wappen are replaced by the own Landesmarke.
    public var armsDisabled: [String]
    /// State codes whose Wappen come from the pack (`manifest.arms`), e.g. ["NÖ"] after written approval.
    public var armsEnabled: [String]

    public init(enabled: Bool = true, pack: Pack? = nil, revoked: [String] = [], armsDisabled: [String] = [],
                armsEnabled: [String] = []) {
        self.enabled = enabled
        self.pack = pack
        self.revoked = revoked
        self.armsDisabled = armsDisabled
        self.armsEnabled = armsEnabled
    }

    private enum CodingKeys: String, CodingKey { case enabled, pack, revoked, armsDisabled, armsEnabled }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pack = try c.decodeIfPresent(Pack.self, forKey: .pack)
        revoked = try c.decodeIfPresent([String].self, forKey: .revoked) ?? []
        armsDisabled = try c.decodeIfPresent([String].self, forKey: .armsDisabled) ?? []
        armsEnabled = try c.decodeIfPresent([String].self, forKey: .armsEnabled) ?? []
    }

    /// Until the first remote answer (or when the block is missing or invalid): logos on, no pack, Niederösterreich
    /// stays on the own Landesmarke.
    public static let `default` = LogoConfig(enabled: true, pack: nil, revoked: [], armsDisabled: ["NÖ"], armsEnabled: [])

    /// The `logos` block of a /v1/config (or logos/config.json) answer; `.default` when it is missing or invalid.
    public static func from(configJSON data: Data) -> LogoConfig {
        struct Wrapper: Decodable { var logos: LogoConfig? }
        return ((try? JSONDecoder().decode(Wrapper.self, from: data))?.logos) ?? .default
    }
}

// MARK: - Pack manifest (manifest.json inside the zip, schema 1, LOGO_SPEC §2.2)

public struct LogoPackManifest: Codable, Sendable {
    public static let supportedSchema = 1

    public struct Image: Codable, Sendable, Hashable {
        /// Path inside the zip.
        public var f: String
        /// Pixels (@3x).
        public var w: Int
        public var h: Int
        public var sha256: String

        public init(f: String, w: Int, h: Int, sha256: String) {
            self.f = f
            self.w = w
            self.h = h
            self.sha256 = sha256
        }
    }

    public struct Images: Codable, Sendable, Hashable {
        /// 60 px high = 20 pt @3x (rows).
        public var s: Image
        /// ≤ 144 px high = 48 pt @3x (hero, cards).
        public var l: Image
        /// Official dark-mode variants.
        public var sd: Image?
        public var ld: Image?

        public init(s: Image, l: Image, sd: Image? = nil, ld: Image? = nil) {
            self.s = s
            self.l = l
            self.sd = sd
            self.ld = ld
        }

        public var all: [Image] { [s, l] + [sd, ld].compactMap { $0 } }
    }

    public struct Plate: Codable, Sendable, Hashable {
        /// Needs the dark „Nacht“ plate in light mode (white-only marks).
        public var light: Bool
        /// Needs the light „Firn“ plate in dark mode.
        public var dark: Bool

        public init(light: Bool = false, dark: Bool = false) {
            self.light = light
            self.dark = dark
        }
    }

    public enum Level: String, Codable, Sendable { case ski, lift, region, ort, land }
    public enum Compact: String, Codable, Sendable { case tile, logo, none }
    public enum Match: String, Codable, Sendable { case tags, gkz, state }

    public struct Brand: Codable, Sendable, Identifiable, Hashable {
        public var id: String
        public var level: Level
        public var name: String
        public var owner: String
        /// „Logo © …“
        public var attribution: String
        public var web: String
        public var states: [String]
        public var match: Match
        public var tags: [String: [String]]
        public var img: Images
        public var aspect: Double
        public var compact: Compact
        public var hero: Bool
        public var selfPlate: Bool
        public var plate: Plate
        public var status: String
        public var gkz: [String]?
        /// Local brands: the stop name must contain one of these places (case- and accent-insensitive).
        public var localities: [String]?

        public init(id: String, level: Level, name: String, owner: String = "", attribution: String = "", web: String = "",
                    states: [String] = [], match: Match, tags: [String: [String]] = [:], img: Images, aspect: Double = 1,
                    compact: Compact, hero: Bool, selfPlate: Bool = false, plate: Plate = Plate(), status: String = "pending",
                    gkz: [String]? = nil, localities: [String]? = nil) {
            self.id = id
            self.level = level
            self.name = name
            self.owner = owner
            self.attribution = attribution
            self.web = web
            self.states = states
            self.match = match
            self.tags = tags
            self.img = img
            self.aspect = aspect
            self.compact = compact
            self.hero = hero
            self.selfPlate = selfPlate
            self.plate = plate
            self.status = status
            self.gkz = gkz
            self.localities = localities
        }
    }

    public struct Held: Codable, Sendable, Hashable {
        public var id: String
        public var name: String
        public var status: String
        public var reason: String
    }

    public struct ArmsImage: Codable, Sendable, Hashable {
        public var f: String
        public var hPt: Double
        public var sha256: String?

        public init(f: String, hPt: Double, sha256: String? = nil) {
            self.f = f
            self.hPt = hPt
            self.sha256 = sha256
        }
    }

    public var schema: Int
    public var packVersion: Int
    public var generated: String
    public var minApp: String
    public var imageFormat: String
    public var scale: Int
    public var brands: [Brand]
    /// {"ski": {"ski-arlberg": "ski_arlberg"}, "region": {"bregenzerwald": "bregenzerwald"}} – stop tags → brands.
    public var byTag: [String: [String: String]]
    /// GKZ → brands without a tag (local tourism boards, lift companies, umbrella regions).
    public var byGkz: [String: [String]]
    /// State code → state tourism brand („Über diese Haltestelle“ only).
    public var byState: [String: String]
    public var held: [Held]
    /// ISO code ("AT-3") → size ("chip", "chip-m", "detail") → image; empty until NÖ approves.
    public var arms: [String: [String: ArmsImage]]

    public init(schema: Int = LogoPackManifest.supportedSchema, packVersion: Int, generated: String = "",
                minApp: String = "1.0.0", imageFormat: String = "webp", scale: Int = 3, brands: [Brand],
                byTag: [String: [String: String]] = [:], byGkz: [String: [String]] = [:], byState: [String: String] = [:],
                held: [Held] = [], arms: [String: [String: ArmsImage]] = [:]) {
        self.schema = schema
        self.packVersion = packVersion
        self.generated = generated
        self.minApp = minApp
        self.imageFormat = imageFormat
        self.scale = scale
        self.brands = brands
        self.byTag = byTag
        self.byGkz = byGkz
        self.byState = byState
        self.held = held
        self.arms = arms
    }

    /// Every file the pack must contain (brand images and Wappen), each with its expected SHA-256 if known.
    public var files: [(path: String, sha256: String?)] {
        var out: [(path: String, sha256: String?)] = []
        for b in brands { for img in b.img.all { out.append((img.f, img.sha256)) } }
        for code in arms.keys.sorted() {
            for size in (arms[code] ?? [:]).keys.sorted() { if let a = arms[code]?[size] { out.append((a.f, a.sha256)) } }
        }
        return out
    }
}

// MARK: - Reader for STORED zips (method 0, no zip64, no encryption) – what build_logo_pack.py writes (LOGO_SPEC §2.1)

public enum LogoPackError: Error, Equatable, Sendable {
    case notAZip
    case unsupported(String)
    case corrupt(String)
    case checksum(String)
    case schema(Int)
}

public struct StoredZip: Sendable {
    /// Entry name → byte range of its (stored) data.
    public let entries: [String: Range<Int>]
    private let bytes: [UInt8]

    /// Parses the central directory. Every offset and length is bounds-checked (a corrupt or hostile file throws,
    /// never traps); names with `..`, a leading `/`, a backslash or NUL are rejected (no path traversal on install).
    public init(data: Data) throws {
        let b = [UInt8](data)
        bytes = b
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard b.count >= 22 else { throw LogoPackError.notAZip }
        // End of central directory: the last 0x06054b50 within the final 64 KiB + 22 bytes.
        var eocd = -1
        var i = b.count - 22
        let floor = max(0, b.count - 65_557)
        while i >= floor {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw LogoPackError.notAZip }
        let count = u16(eocd + 10), cdOffset = u32(eocd + 16)
        guard count != 0xFFFF, cdOffset != 0xFFFF_FFFF else { throw LogoPackError.unsupported("zip64") }
        guard cdOffset <= eocd else { throw LogoPackError.corrupt("central directory offset") }
        var map: [String: Range<Int>] = [:]
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x0201_4B50 else { throw LogoPackError.corrupt("central directory") }
            let flags = u16(p + 8), method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), xlen = u16(p + 30), clen = u16(p + 32), lho = u32(p + 42)
            guard p + 46 + nlen + xlen + clen <= b.count else { throw LogoPackError.corrupt("central directory") }
            guard flags & 0x1 == 0 else { throw LogoPackError.unsupported("encryption") }
            guard method == 0, csize == usize else { throw LogoPackError.unsupported("compression method \(method)") }
            guard csize != 0xFFFF_FFFF, lho != 0xFFFF_FFFF else { throw LogoPackError.unsupported("zip64") }
            guard let name = String(bytes: b[(p + 46)..<(p + 46 + nlen)], encoding: .utf8), !name.isEmpty else {
                throw LogoPackError.corrupt("name")
            }
            guard Self.isSafe(name) else { throw LogoPackError.corrupt("path \(name)") }
            guard lho + 30 <= b.count, u32(lho) == 0x0403_4B50 else { throw LogoPackError.corrupt("local header \(name)") }
            let start = lho + 30 + u16(lho + 26) + u16(lho + 28)
            guard start <= b.count, csize <= b.count - start else { throw LogoPackError.corrupt("data \(name)") }
            map[name] = start..<(start + csize)
            p += 46 + nlen + xlen + clen
        }
        entries = map
    }

    /// A relative path without `..` components, backslashes or NUL.
    static func isSafe(_ name: String) -> Bool {
        if name.hasPrefix("/") || name.contains("\\") || name.contains("\0") { return false }
        return !name.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." }
            && !name.contains("..")
    }

    public func data(_ name: String) -> Data? { entries[name].map { Data(bytes[$0]) } }
}

// MARK: - Install (verify + unpack) – the app calls this from its download task (LOGO_SPEC §3.3)

public struct LogoPackInstaller: Sendable {
    /// Lowercase hex SHA-256 of the bytes (CryptoKit in the app).
    public typealias Hasher = @Sendable (Data) -> String
    public let hasher: Hasher

    public init(hasher: @escaping Hasher) { self.hasher = hasher }

    /// Verifies the whole zip against the config (size + SHA-256), parses the manifest (schema, version), checks
    /// every file's SHA-256 and writes the pack to `directory/<version>/` atomically (staging folder + rename).
    /// Returns the manifest. Nothing is written outside `directory`.
    public func install(zip: Data, expected: LogoConfig.Pack, into directory: URL,
                        fileManager: FileManager = .default) throws -> LogoPackManifest {
        guard zip.count == expected.bytes, hasher(zip).lowercased() == expected.sha256.lowercased() else {
            throw LogoPackError.checksum("pack")
        }
        let z = try StoredZip(data: zip)
        guard let mdata = z.data("manifest.json") else { throw LogoPackError.corrupt("manifest.json missing") }
        let manifest: LogoPackManifest
        do {
            manifest = try JSONDecoder().decode(LogoPackManifest.self, from: mdata)
        } catch {
            if let schema = (try? JSONSerialization.jsonObject(with: mdata) as? [String: Any])?["schema"] as? Int,
               schema != LogoPackManifest.supportedSchema {
                throw LogoPackError.schema(schema)
            }
            throw LogoPackError.corrupt("manifest.json")
        }
        guard manifest.schema == LogoPackManifest.supportedSchema else { throw LogoPackError.schema(manifest.schema) }
        guard manifest.packVersion == expected.version else { throw LogoPackError.corrupt("version mismatch") }
        let staging = directory.appendingPathComponent(".staging-\(manifest.packVersion)", isDirectory: true)
        let final = directory.appendingPathComponent(String(manifest.packVersion), isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for file in manifest.files {
                guard StoredZip.isSafe(file.path), let d = z.data(file.path) else { throw LogoPackError.corrupt(file.path) }
                if let h = file.sha256, hasher(d).lowercased() != h.lowercased() { throw LogoPackError.checksum(file.path) }
                let url = staging.appendingPathComponent(file.path)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try d.write(to: url)
            }
            try mdata.write(to: staging.appendingPathComponent("manifest.json"))
            try? fileManager.removeItem(at: final)
            try fileManager.moveItem(at: staging, to: final)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        return manifest
    }

    /// The newest installed pack in `directory` (`<version>/manifest.json` with a supported schema): what the app
    /// activates at launch, before any network call.
    public static func installed(in directory: URL, fileManager: FileManager = .default)
        -> (manifest: LogoPackManifest, directory: URL)? {
        for v in versions(in: directory, fileManager: fileManager).reversed() {
            let dir = directory.appendingPathComponent(String(v), isDirectory: true)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let m = try? JSONDecoder().decode(LogoPackManifest.self, from: data),
                  m.schema == LogoPackManifest.supportedSchema, m.packVersion == v else { continue }
            return (m, dir)
        }
        return nil
    }

    /// Installed pack versions (numeric folder names), ascending.
    public static func versions(in directory: URL, fileManager: FileManager = .default) -> [Int] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { Int($0) }.sorted()
    }

    /// Deletes every other pack version and stale staging folders (after activating `keep`).
    public static func removeVersions(in directory: URL, except keep: Int, fileManager: FileManager = .default) {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for n in names where (Int(n) != nil && Int(n) != keep) || n.hasPrefix(".staging-") {
            try? fileManager.removeItem(at: directory.appendingPathComponent(n))
        }
    }

    /// Deletes the cached images of revoked brands from an installed pack (the resolver ignores them already).
    public static func removeFiles(of revoked: Set<String>, manifest: LogoPackManifest, packDirectory: URL,
                                   fileManager: FileManager = .default) {
        for b in manifest.brands where revoked.contains(b.id) {
            for img in b.img.all where StoredZip.isSafe(img.f) {
                try? fileManager.removeItem(at: packDirectory.appendingPathComponent(img.f))
            }
        }
    }
}

// MARK: - Which logos belong to a stop (LOGO_SPEC §4.1)

public struct StopBrandInput: Sendable {
    /// Gemeindekennziffer as text ("80239").
    public var gkz: String
    /// B, K, NÖ, OÖ, S, ST, T, V, W.
    public var state: String
    /// Official name + aliases (locality rules of local brands).
    public var names: [String]
    /// Ski-area tag (any confidence; the resolver applies ≥ 70).
    public var ski: (id: String, conf: Int)?
    public var skiAlliance: String?
    /// Region tags (any confidence; the resolver applies ≥ 80).
    public var regions: [(id: String, conf: Int)]

    public init(gkz: String, state: String, names: [String], ski: (id: String, conf: Int)?, skiAlliance: String? = nil,
                regions: [(id: String, conf: Int)]) {
        self.gkz = gkz
        self.state = state
        self.names = names
        self.ski = ski
        self.skiAlliance = skiAlliance
        self.regions = regions
    }

    /// From the stop facts the place layer already has (`PlaceMarkSelection.areaBrandQuery`).
    public init(_ q: AreaBrandQuery) {
        self.init(gkz: q.gkz ?? "", state: q.state ?? "", names: q.names, ski: q.skiArea.map { (id: $0.id, conf: $0.confidence) },
                  skiAlliance: q.skiAlliance, regions: q.regions.map { (id: $0.id, conf: $0.confidence) })
    }
}

public struct StopBrands: Sendable {
    public typealias Brand = LogoPackManifest.Brand
    public var ski: Brand?
    public var alliance: Brand?
    /// Ort + GKZ-matched regions, most specific first.
    public var local: [Brand]
    /// Tag-matched regions, by confidence.
    public var regions: [Brand]
    public var lift: [Brand]
    public var land: Brand?

    /// Up to two cells for the hero „Gebietsleiste“: ski area + most local tourism board.
    public var heroCells: [Brand] {
        var out: [Brand] = []
        if let s = ski, s.hero { out.append(s) }
        if let t = (local + regions).first(where: { $0.hero && $0.id != ski?.id }) { out.append(t) }
        return out
    }

    /// The single area mark of a list row (ski area before region); nil → own badge from the tags.
    public var rowBrand: Brand? {
        if let s = ski { return s.compact == .none ? nil : s }
        return regions.first.flatMap { $0.compact == .none ? nil : $0 }
    }
}

public struct BrandResolver: Sendable {
    public let manifest: LogoPackManifest
    public let revoked: Set<String>
    public var minSkiConf = 70
    public var minRegionConf = 80
    private let byId: [String: LogoPackManifest.Brand]

    /// Revoked brands do not exist for the resolver (their place is taken by the own badge).
    public init(manifest: LogoPackManifest, revoked: Set<String>) {
        self.manifest = manifest
        self.revoked = revoked
        var m: [String: LogoPackManifest.Brand] = [:]
        for b in manifest.brands where !revoked.contains(b.id) { m[b.id] = b }
        byId = m
    }

    public func brand(_ id: String?) -> LogoPackManifest.Brand? { id.flatMap { byId[$0] } }

    public func resolve(_ s: StopBrandInput) -> StopBrands {
        let ski = s.ski.flatMap { $0.conf >= minSkiConf ? brand(manifest.byTag["ski"]?[$0.id]) : nil }
        let alliance = brand(s.skiAlliance.flatMap { manifest.byTag["ski"]?[$0] })
        var seen = Set([ski?.id].compactMap { $0 })
        var regions: [LogoPackManifest.Brand] = []
        for r in s.regions.filter({ $0.conf >= minRegionConf }).enumerated()
            .sorted(by: { $0.element.conf != $1.element.conf ? $0.element.conf > $1.element.conf : $0.offset < $1.offset }) {
            if let b = brand(manifest.byTag["region"]?[r.element.id]), seen.insert(b.id).inserted { regions.append(b) }
        }
        let folded = s.names.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        var local: [LogoPackManifest.Brand] = [], lift: [LogoPackManifest.Brand] = []
        for id in manifest.byGkz[s.gkz] ?? [] {
            guard let b = brand(id), !seen.contains(b.id) else { continue }
            if let locs = b.localities, !locs.isEmpty {
                let hit = locs.contains { l in
                    let f = l.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    return folded.contains { $0.contains(f) }
                }
                if !hit { continue }
            }
            seen.insert(b.id)
            if b.level == .lift { lift.append(b) } else { local.append(b) }
        }
        local = local.enumerated().sorted { a, b in
            let ka = (a.element.gkz?.count ?? 99, a.element.level == .ort ? 0 : 1)
            let kb = (b.element.gkz?.count ?? 99, b.element.level == .ort ? 0 : 1)
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
        return StopBrands(ski: ski, alliance: alliance, local: local, regions: regions, lift: lift,
                          land: brand(manifest.byState[s.state]))
    }
}

/// The logo pack as the seam of the place marks (`PlaceMarkSelection.rowAreaMark` / `heroAreaCells`).
extension BrandResolver: AreaBrandProviding {
    public func rowBrandID(for query: AreaBrandQuery) -> String? { resolve(StopBrandInput(query)).rowBrand?.id }

    public func heroBrandIDs(for query: AreaBrandQuery) -> [String] { resolve(StopBrandInput(query)).heroCells.map(\.id) }
}

// MARK: - Landeswappen (bundled asset names, LOGO_SPEC §3.5 / §3.6)

public enum Landeswappen {
    /// App state code → ISO 3166-2 suffix used in the asset names `Wappen/AT-n…`.
    public static let iso: [String: String] = ["B": "AT-1", "K": "AT-2", "NÖ": "AT-3", "OÖ": "AT-4", "S": "AT-5",
                                               "ST": "AT-6", "T": "AT-7", "V": "AT-8", "W": "AT-9"]
    /// States whose Wappen ship in the app bundle. Niederösterreich only via the pack after written approval.
    public static let bundled: Set<String> = ["B", "K", "OÖ", "S", "ST", "T", "V", "W"]
    /// States with a `-full` variant (with helmet/crown, ≥ 64–96 pt).
    public static let withFullArms: Set<String> = ["K", "OÖ", "S"]

    public enum Size: Sendable {
        /// 14 pt (`-chip`): rows, favourites, route card.
        case chip
        /// 18 pt (`-chip-m`): detail hero, „Über diese Haltestelle“.
        case chipM
        /// PDF vector, ≥ 24 pt.
        case vector
        /// Largest form (`-full` where it exists, else the vector).
        case full
    }

    /// Bundled asset name, or nil → draw the own Landesmarke instead (logos off, Wappen disabled remotely, not bundled).
    public static func assetName(state: String, size: Size, config: LogoConfig) -> String? {
        guard config.enabled, !config.armsDisabled.contains(state), bundled.contains(state), let code = iso[state] else {
            return nil
        }
        switch size {
        case .chip: return "Wappen/\(code)-chip"
        case .chipM: return "Wappen/\(code)-chip-m"
        case .vector: return "Wappen/\(code)"
        case .full: return withFullArms.contains(state) ? "Wappen/\(code)-full" : "Wappen/\(code)"
        }
    }

    /// Wappen of a state from the installed pack (`manifest.arms`, e.g. NÖ after approval and `armsEnabled`):
    /// the path inside the pack folder, or nil.
    public static func packImagePath(state: String, size: Size, config: LogoConfig, manifest: LogoPackManifest?) -> String? {
        guard config.enabled, config.armsEnabled.contains(state), !config.armsDisabled.contains(state),
              let code = iso[state], let arms = manifest?.arms[code] else { return nil }
        let key: String
        switch size {
        case .chip: key = "chip"
        case .chipM: key = "chip-m"
        case .vector, .full: key = "detail"
        }
        return (arms[key] ?? arms["detail"]).map(\.f)
    }
}
