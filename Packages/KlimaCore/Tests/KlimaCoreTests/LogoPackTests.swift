import Foundation
import XCTest
@testable import KlimaCore

/// LOGO_SPEC (docs/LOGO_SPEC.md §2–§4): remote config, manifest, stored zip, verifying installer, brand resolver and
/// Landeswappen asset names. Every pack here is SYNTHETIC – built at runtime from solid-colour PNGs – no real logo is
/// ever read or committed (LOGO_SPEC §1).
final class LogoPackTests: XCTestCase {
    // MARK: config

    func testLogoConfigBlock() throws {
        let json = #"{"other": 1, "logos": {"enabled": true, "pack": {"schema": 1, "version": 2026100901,"#
            + #" "url": "https://static.example.invalid/logos/v1/pack-2026100901.zip", "sha256": "ABCDEF", "bytes": 12},"#
            + #" "revoked": ["x"], "armsDisabled": ["T"], "armsEnabled": ["NÖ"]}}"#
        let c = LogoConfig.from(configJSON: Data(json.utf8))
        XCTAssertTrue(c.enabled)
        XCTAssertEqual(c.pack?.version, 2026100901)
        XCTAssertEqual(c.pack?.bytes, 12)
        XCTAssertEqual(c.revoked, ["x"])
        XCTAssertEqual(c.armsDisabled, ["T"])
        XCTAssertEqual(c.armsEnabled, ["NÖ"])
        // partial block: defaults for everything missing
        let partial = LogoConfig.from(configJSON: Data(#"{"logos": {"enabled": false}}"#.utf8))
        XCTAssertEqual(partial, LogoConfig(enabled: false))
        // missing or broken block → compile-time default: logos on, no pack, NÖ on the own Landesmarke
        XCTAssertEqual(LogoConfig.from(configJSON: Data(#"{"flags": {}}"#.utf8)), .default)
        XCTAssertEqual(LogoConfig.from(configJSON: Data("not json".utf8)), .default)
        XCTAssertEqual(LogoConfig.from(configJSON: Data(#"{"logos": {"pack": {"version": "x"}}}"#.utf8)), .default)
        XCTAssertEqual(LogoConfig.default.armsDisabled, ["NÖ"])
        XCTAssertNil(LogoConfig.default.pack)
        let round = try JSONDecoder().decode(LogoConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(round, c)
    }

    // MARK: manifest

    func testManifestParsing() throws {
        let pack = SyntheticPack()
        let m = try JSONDecoder().decode(LogoPackManifest.self, from: pack.manifestJSON)
        XCTAssertEqual(m.schema, 1)
        XCTAssertEqual(m.packVersion, pack.version)
        XCTAssertEqual(m.brands.count, SyntheticPack.brands.count)
        XCTAssertEqual(m.byTag["ski"]?["ski-arlberg"], "ski_arlberg")
        XCTAssertEqual(m.byGkz["70621"], ["st_anton_arlberg", "arlberger_bergbahnen"])
        XCTAssertEqual(m.byState["V"], "vorarlberg_tourismus")
        let ski = try XCTUnwrap(m.brands.first { $0.id == "ski_arlberg" })
        XCTAssertEqual(ski.level, .ski)
        XCTAssertEqual(ski.compact, .tile)
        XCTAssertTrue(ski.hero)
        XCTAssertEqual(ski.img.s.h, 60)
        XCTAssertNotNil(m.brands.first { $0.id == "bregenzerwald" }?.img.sd, "dark variant")
        XCTAssertEqual(m.held.first?.status, "hold")
        XCTAssertEqual(m.files.count, m.brands.reduce(0) { $0 + $1.img.all.count })
        // unknown top-level keys are ignored (the real manifest carries a "notice")
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.manifestJSON) as? [String: Any])
        obj["notice"] = "Marken der jeweiligen Inhaber"
        XCTAssertNoThrow(try JSONDecoder().decode(LogoPackManifest.self, from: JSONSerialization.data(withJSONObject: obj)))
    }

    // MARK: stored zip

    func testStoredZipReadsEntries() throws {
        let files: [(String, Data)] = [("manifest.json", Data("{}".utf8)), ("b/a/s.png", SyntheticPack.png(4, 3, (255, 0, 0))),
                                       ("b/a/l.png", SyntheticPack.png(8, 6, (0, 0, 255)))]
        let z = try StoredZip(data: SyntheticPack.zip(files))
        XCTAssertEqual(z.entries.count, 3)
        for (name, data) in files { XCTAssertEqual(z.data(name), data, name) }
        XCTAssertNil(z.data("missing"))
        // the PNG writer makes real images (signature, IHDR) – solid colours, never a logo
        let png = SyntheticPack.png(2, 2, (1, 2, 3))
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(String(decoding: png[12..<16], as: UTF8.self), "IHDR")
    }

    func testStoredZipRejectsPathTraversal() {
        for evil in ["../evil.png", "/etc/passwd", "b/../../x.png", "b\\..\\x.png", "b/./x.png", "a/..", "x\0.png"] {
            XCTAssertThrowsError(try StoredZip(data: SyntheticPack.zip([("ok.png", Data([1])), (evil, Data([2]))])), evil) {
                guard case LogoPackError.corrupt(let what)? = $0 as? LogoPackError else { return XCTFail("\(evil): \($0)") }
                XCTAssertTrue(what.hasPrefix("path"), what)
            }
        }
        XCTAssertFalse(StoredZip.isSafe("b/..hidden"))
        XCTAssertTrue(StoredZip.isSafe("b/ski_arlberg/s.webp"))
    }

    func testStoredZipRejectsWhatItCannotRead() {
        XCTAssertThrowsError(try StoredZip(data: SyntheticPack.zip([("a.png", Data([1, 2, 3]))], method: 8))) {
            XCTAssertEqual($0 as? LogoPackError, .unsupported("compression method 8"))
        }
        XCTAssertThrowsError(try StoredZip(data: SyntheticPack.zip([("a.png", Data([1]))], flags: 1))) {
            XCTAssertEqual($0 as? LogoPackError, .unsupported("encryption"))
        }
        XCTAssertThrowsError(try StoredZip(data: Data("PK no zip at all, just text that is long enough".utf8))) {
            XCTAssertEqual($0 as? LogoPackError, .notAZip)
        }
        XCTAssertThrowsError(try StoredZip(data: Data([0x50, 0x4B])))
        let good = SyntheticPack().zip
        XCTAssertThrowsError(try StoredZip(data: good.prefix(good.count / 2)))
    }

    /// Random flips and truncations of a real (synthetic) pack: the reader throws or reads, it never traps.
    func testStoredZipFuzzNeverTraps() {
        let good = [UInt8](SyntheticPack().zip)
        var rng = SeededRNG(seed: 0x10605)
        var threw = 0
        for i in 0..<600 {
            var b = good
            if i % 3 == 0 {
                b = Array(b.prefix(Int(rng.next() % UInt64(b.count))))
            } else {
                for _ in 0..<(1 + Int(rng.next() % 8)) {
                    // aim at the directory half of the time (that is where the offsets live)
                    let lo = i % 2 == 0 ? max(0, b.count - 600) : 0
                    b[lo + Int(rng.next() % UInt64(b.count - lo))] = UInt8(truncatingIfNeeded: rng.next())
                }
            }
            do {
                let z = try StoredZip(data: Data(b))
                for name in z.entries.keys { _ = z.data(name) }
            } catch {
                threw += 1
            }
        }
        XCTAssertGreaterThan(threw, 100)
    }

    // MARK: installer

    func testInstallVerifiesEveryFile() throws {
        let pack = SyntheticPack()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = LogoPackInstaller(hasher: TestSHA256.hex)
        let m = try installer.install(zip: pack.zip, expected: pack.config, into: dir)
        XCTAssertEqual(m.packVersion, pack.version)
        let packDir = dir.appendingPathComponent(String(pack.version))
        for f in m.files {
            let url = packDir.appendingPathComponent(f.path)
            XCTAssertEqual(try TestSHA256.hex(Data(contentsOf: url)), f.sha256, f.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: packDir.appendingPathComponent("manifest.json").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".staging") })
        XCTAssertEqual(LogoPackInstaller.installed(in: dir)?.manifest.packVersion, pack.version)
        // the same version again replaces it
        XCTAssertNoThrow(try installer.install(zip: pack.zip, expected: pack.config, into: dir))
        XCTAssertEqual(LogoPackInstaller.versions(in: dir), [pack.version])
    }

    func testInstallRejectsTamperedPacks() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = LogoPackInstaller(hasher: TestSHA256.hex)
        let pack = SyntheticPack()
        func expectError(_ zip: Data, _ cfg: LogoConfig.Pack, _ want: LogoPackError, line: UInt = #line) {
            XCTAssertThrowsError(try installer.install(zip: zip, expected: cfg, into: dir), line: line) {
                XCTAssertEqual($0 as? LogoPackError, want, line: line)
            }
            XCTAssertNil(LogoPackInstaller.installed(in: dir), "nothing is activated", line: line)
            XCTAssertFalse((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.contains { $0.hasPrefix(".staging") }
                           ?? false, "no staging left", line: line)
        }
        // whole-file checks: size and SHA-256 of the config
        var wrongHash = pack.config
        wrongHash.sha256 = String(repeating: "0", count: 64)
        expectError(pack.zip, wrongHash, .checksum("pack"))
        var wrongSize = pack.config
        wrongSize.bytes += 1
        expectError(pack.zip, wrongSize, .checksum("pack"))
        var flipped = [UInt8](pack.zip)
        flipped[flipped.count / 3] ^= 0xFF
        expectError(Data(flipped), pack.config, .checksum("pack"))
        // one image swapped although the config matches the (tampered) zip: the per-file SHA-256 catches it
        let tampered = SyntheticPack(replacing: "b/warth_schroecken/s.png", with: SyntheticPack.png(5, 5, (9, 9, 9)))
        expectError(tampered.zip, tampered.config, .checksum("b/warth_schroecken/s.png"))
        // manifest problems
        let otherVersion = SyntheticPack(version: 2026100902)
        var cfg = otherVersion.config
        cfg.version = 2026100901
        expectError(otherVersion.zip, cfg, .corrupt("version mismatch"))
        let schema2 = SyntheticPack(schema: 2)
        expectError(schema2.zip, schema2.config, .schema(2))
        let noManifest = SyntheticPack(omitting: "manifest.json")
        expectError(noManifest.zip, noManifest.config, .corrupt("manifest.json missing"))
        let missingImage = SyntheticPack(omitting: "b/ski_arlberg/l.png")
        expectError(missingImage.zip, missingImage.config, .corrupt("b/ski_arlberg/l.png"))
    }

    func testVersionsAndRevokedFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = LogoPackInstaller(hasher: TestSHA256.hex)
        let v1 = SyntheticPack(version: 2026100901), v2 = SyntheticPack(version: 2026100902)
        _ = try installer.install(zip: v1.zip, expected: v1.config, into: dir)
        let m2 = try installer.install(zip: v2.zip, expected: v2.config, into: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".staging-1"), withIntermediateDirectories: true)
        XCTAssertEqual(LogoPackInstaller.versions(in: dir), [2026100901, 2026100902])
        XCTAssertEqual(LogoPackInstaller.installed(in: dir)?.manifest.packVersion, 2026100902, "the newest wins")
        LogoPackInstaller.removeVersions(in: dir, except: 2026100902)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["2026100902"])
        // takedown: `revoked` deletes the cached files of that brand
        let packDir = dir.appendingPathComponent("2026100902")
        let revoked = try XCTUnwrap(m2.brands.first { $0.id == "bregenzerwald" })
        LogoPackInstaller.removeFiles(of: ["bregenzerwald"], manifest: m2, packDirectory: packDir)
        for img in revoked.img.all {
            XCTAssertFalse(FileManager.default.fileExists(atPath: packDir.appendingPathComponent(img.f).path), img.f)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: packDir.appendingPathComponent("b/ski_arlberg/s.png").path))
        // a broken manifest is never activated
        try Data("{".utf8).write(to: packDir.appendingPathComponent("manifest.json"))
        XCTAssertNil(LogoPackInstaller.installed(in: dir))
    }

    // MARK: brand resolver (LOGO_SPEC §4.1) on the shipped stop tags

    func testBrandResolverWarthAndStAnton() throws {
        let index = PlaceFixtures.index
        let manifest = try JSONDecoder().decode(LogoPackManifest.self, from: SyntheticPack().manifestJSON)
        let resolver = BrandResolver(manifest: manifest, revoked: [])
        func brands(_ id: String) throws -> (Place, StopBrands) {
            let p = try XCTUnwrap(index.place(id: id), id)
            return (p, resolver.resolve(StopBrandInput(PlaceMarkSelection.areaBrandQuery(place: p, tags: p.tags))))
        }

        // Warth (Vorarlberg) Dorfplatz: Ski Arlberg tile in the row, hero Ski Arlberg · Warth-Schröcken
        let (warth, w) = try brands("at:48:344")
        XCTAssertEqual(w.ski?.id, "ski_arlberg")
        XCTAssertEqual(w.rowBrand?.id, "ski_arlberg")
        XCTAssertEqual(w.heroCells.map(\.id), ["ski_arlberg", "warth_schroecken"])
        XCTAssertEqual(w.local.map(\.id), ["warth_schroecken"])
        XCTAssertEqual(w.regions.map(\.id), ["bregenzerwald"])
        XCTAssertEqual(w.land?.id, "vorarlberg_tourismus")
        XCTAssertEqual(PlaceMarkSelection.rowAreaMark(place: warth, tags: warth.tags, brands: resolver), .brand(id: "ski_arlberg"))
        XCTAssertEqual(PlaceMarkSelection.heroAreaCells(place: warth, tags: warth.tags, brands: resolver),
                       [.brand(id: "ski_arlberg"), .brand(id: "warth_schroecken")])
        XCTAssertEqual(Landeswappen.assetName(state: try XCTUnwrap(warth.state), size: .chip, config: .default), "Wappen/AT-8-chip")

        // St. Anton am Arlberg Bahnhof: ski area + Ort brand in the hero, the lift company separately, Tirol
        let (_, s) = try brands("at:47:1222")
        XCTAssertEqual(s.rowBrand?.id, "ski_arlberg")
        XCTAssertEqual(s.heroCells.map(\.id), ["ski_arlberg", "st_anton_arlberg"])
        XCTAssertEqual(s.lift.map(\.id), ["arlberger_bergbahnen"])
        XCTAssertEqual(s.land?.id, "tirol_werbung")

        // St. Christoph (Gemeinde St. Anton, GKZ 70621) is not „St. Anton“: the locality rule keeps the Ort brand out
        let christoph = try XCTUnwrap(index.search("St. Christoph am Arlberg", context: .tripLog, limit: 5).first {
            $0.tags.gkz == 70621 && !PlaceNormalizer.fold($0.name).contains("anton")
        })
        let c = resolver.resolve(StopBrandInput(PlaceMarkSelection.areaBrandQuery(place: christoph, tags: christoph.tags)))
        XCTAssertFalse(c.local.contains { $0.id == "st_anton_arlberg" }, christoph.name)
        XCTAssertEqual(c.lift.map(\.id), ["arlberger_bergbahnen"])

        // homonyms: St. Anton im Montafon and Warth/NÖ get no Arlberg brand
        XCTAssertNil(try brands("at:48:187").1.ski)
        let (noe, n) = try brands("at:43:30742")
        XCTAssertNil(n.ski)
        XCTAssertNil(n.rowBrand)
        XCTAssertTrue(n.heroCells.isEmpty)
        XCTAssertNil(Landeswappen.assetName(state: try XCTUnwrap(noe.state), size: .chip, config: .default), "NÖ: own Landesmarke")

        // a takedown (`revoked`) falls back to the own Wegzeichen in the same place
        let revoked = BrandResolver(manifest: manifest, revoked: ["ski_arlberg"])
        XCTAssertEqual(PlaceMarkSelection.rowAreaMark(place: warth, tags: warth.tags, brands: revoked), .skiArea(id: "ski-arlberg"))
        XCTAssertEqual(revoked.heroBrandIDs(for: PlaceMarkSelection.areaBrandQuery(place: warth, tags: warth.tags)),
                       ["warth_schroecken"])
        XCTAssertNil(revoked.brand("ski_arlberg"))
        // a region brand with `compact: none` is never a row mark (own region chip)
        var tagsOnlyRegion = warth.tags
        tagsOnlyRegion.skiAreas = []
        XCTAssertNil(resolver.rowBrandID(for: PlaceMarkSelection.areaBrandQuery(place: warth, tags: tagsOnlyRegion)))
    }

    // MARK: Landeswappen

    func testLandeswappenAssetNames() throws {
        let cfg = LogoConfig.default
        XCTAssertEqual(Landeswappen.assetName(state: "V", size: .chip, config: cfg), "Wappen/AT-8-chip")
        XCTAssertEqual(Landeswappen.assetName(state: "T", size: .chipM, config: cfg), "Wappen/AT-7-chip-m")
        XCTAssertEqual(Landeswappen.assetName(state: "W", size: .vector, config: cfg), "Wappen/AT-9")
        XCTAssertEqual(Landeswappen.assetName(state: "S", size: .full, config: cfg), "Wappen/AT-5-full")
        XCTAssertEqual(Landeswappen.assetName(state: "T", size: .full, config: cfg), "Wappen/AT-7", "no -full variant")
        XCTAssertNil(Landeswappen.assetName(state: "NÖ", size: .chip, config: LogoConfig()), "not bundled")
        XCTAssertNil(Landeswappen.assetName(state: "X", size: .chip, config: cfg))
        XCTAssertNil(Landeswappen.assetName(state: "T", size: .chip, config: LogoConfig(armsDisabled: ["T"])), "armsDisabled")
        XCTAssertNil(Landeswappen.assetName(state: "V", size: .chip, config: LogoConfig(enabled: false)), "logos off")
        for s in Landeswappen.bundled { XCTAssertNotNil(Landeswappen.assetName(state: s, size: .chip, config: cfg), s) }
        XCTAssertEqual(Set(Landeswappen.iso.keys), Set(FederalState.allCases.map(\.rawValue)).subtracting(["X"]))

        // NÖ after written approval: Wappen from the pack, only with `armsEnabled`
        var m = try JSONDecoder().decode(LogoPackManifest.self, from: SyntheticPack().manifestJSON)
        m.arms = ["AT-3": ["chip": .init(f: "arms/AT-3-chip@3x.png", hPt: 14), "detail": .init(f: "arms/AT-3@3x.png", hPt: 64)]]
        let approved = LogoConfig(armsEnabled: ["NÖ"])
        XCTAssertEqual(Landeswappen.packImagePath(state: "NÖ", size: .chip, config: approved, manifest: m), "arms/AT-3-chip@3x.png")
        XCTAssertEqual(Landeswappen.packImagePath(state: "NÖ", size: .chipM, config: approved, manifest: m), "arms/AT-3@3x.png")
        XCTAssertNil(Landeswappen.packImagePath(state: "NÖ", size: .chip, config: .default, manifest: m))
        XCTAssertNil(Landeswappen.packImagePath(state: "NÖ", size: .chip, config: LogoConfig(armsDisabled: ["NÖ"], armsEnabled: ["NÖ"]),
                                                manifest: m))
        XCTAssertNil(Landeswappen.packImagePath(state: "NÖ", size: .chip, config: approved, manifest: nil))
    }

    func testTestHasherIsSHA256() {
        XCTAssertEqual(TestSHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(TestSHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(TestSHA256.hex(Data(String(repeating: "a", count: 1000).utf8)),
                       "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("logopack-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

// MARK: - Synthetic test pack (solid-colour PNGs, never a real logo)

struct SyntheticPack {
    struct BrandSpec {
        var id: String
        var level: String
        var name: String
        var match: String
        var compact: String
        var hero: Bool
        var gkz: [String]? = nil
        var localities: [String]? = nil
        var states: [String]
        var dark = false
    }

    static let brands: [BrandSpec] = [
        BrandSpec(id: "ski_arlberg", level: "ski", name: "Ski Arlberg", match: "tags", compact: "tile", hero: true, states: ["T", "V"]),
        BrandSpec(id: "bregenzerwald", level: "region", name: "Bregenzerwald", match: "tags", compact: "none", hero: false,
                  states: ["V"], dark: true),
        BrandSpec(id: "warth_schroecken", level: "ort", name: "Warth-Schröcken", match: "gkz", compact: "tile", hero: true,
                  gkz: ["80234", "80239"], states: ["V"]),
        BrandSpec(id: "st_anton_arlberg", level: "ort", name: "St. Anton am Arlberg", match: "gkz", compact: "logo", hero: true,
                  gkz: ["70621"], localities: ["St. Anton"], states: ["T"]),
        BrandSpec(id: "arlberger_bergbahnen", level: "lift", name: "Arlberger Bergbahnen", match: "gkz", compact: "logo",
                  hero: false, gkz: ["70621"], states: ["T", "V"]),
        BrandSpec(id: "vorarlberg_tourismus", level: "land", name: "Vorarlberg", match: "state", compact: "tile", hero: false,
                  states: ["V"]),
        BrandSpec(id: "tirol_werbung", level: "land", name: "Tirol", match: "state", compact: "logo", hero: false, states: ["T"]),
    ]

    let version: Int
    let manifestJSON: Data
    let zip: Data
    let config: LogoConfig.Pack

    /// `replacing` swaps one file's bytes after the manifest was written (tamper test); `omitting` leaves a file out.
    init(version: Int = 2026100901, schema: Int = 1, replacing: String? = nil, with replacement: Data? = nil,
         omitting: String? = nil) {
        self.version = version
        var files: [(String, Data)] = []
        var brands: [[String: Any]] = []
        for (k, b) in Self.brands.enumerated() {
            let colour = (UInt8(40 * k % 256), UInt8(255 - 30 * k), UInt8(90 + 20 * k))
            var img: [String: Any] = [:]
            var variants: [(String, Int, Int)] = [("s", 60, 60), ("l", 144, 144)]
            if b.dark { variants += [("sd", 60, 60), ("ld", 144, 144)] }
            for (key, w, h) in variants {
                let path = "b/\(b.id)/\(key).png"
                let data = Self.png(max(1, w / 12), max(1, h / 12), colour)
                files.append((path, data))
                img[key] = ["f": path, "w": w, "h": h, "sha256": TestSHA256.hex(data)]
            }
            var brand: [String: Any] = [
                "id": b.id, "level": b.level, "name": b.name, "owner": "Test owner \(k)", "attribution": "Logo © Test \(k)",
                "web": "https://example.invalid/\(b.id)", "states": b.states, "match": b.match,
                "tags": b.id == "ski_arlberg" ? ["ski": ["ski-arlberg"]] : (b.id == "bregenzerwald" ? ["region": ["bregenzerwald"]] : [:]),
                "img": img, "aspect": b.compact == "logo" ? 3.4 : 1.0, "compact": b.compact, "hero": b.hero,
                "selfPlate": false, "plate": ["light": false, "dark": b.dark], "status": "pending",
            ]
            if let g = b.gkz { brand["gkz"] = g }
            if let l = b.localities { brand["localities"] = l }
            brands.append(brand)
        }
        let manifest: [String: Any] = [
            "schema": schema, "packVersion": version, "generated": "2026-10-09T00:00:00+00:00", "minApp": "1.0.0",
            "imageFormat": "png", "scale": 3, "brands": brands,
            "byTag": ["ski": ["ski-arlberg": "ski_arlberg"], "region": ["bregenzerwald": "bregenzerwald"]],
            "byGkz": ["80239": ["warth_schroecken"], "80234": ["warth_schroecken"], "70621": ["st_anton_arlberg", "arlberger_bergbahnen"]],
            "byState": ["V": "vorarlberg_tourismus", "T": "tirol_werbung"],
            "held": [["id": "held_brand", "name": "Held", "status": "hold", "reason": "needs a licence"]],
            "arms": [String: Any](),
        ]
        manifestJSON = try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        files.insert(("manifest.json", manifestJSON), at: 0)
        if let r = replacing, let i = files.firstIndex(where: { $0.0 == r }) { files[i].1 = replacement ?? Data() }
        if let o = omitting { files.removeAll { $0.0 == o } }
        zip = Self.zip(files)
        config = LogoConfig.Pack(schema: 1, version: version, url: "https://static.example.invalid/logos/v1/pack-\(version).zip",
                                 sha256: TestSHA256.hex(zip), bytes: zip.count)
    }

    /// Solid-colour RGB PNG (zlib with stored blocks, valid CRCs).
    static func png(_ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8)) -> Data {
        var raw: [UInt8] = []
        for _ in 0..<h {
            raw.append(0)
            for _ in 0..<w { raw += [rgb.0, rgb.1, rgb.2] }
        }
        var z: [UInt8] = [0x78, 0x01]
        var i = 0
        repeat {
            let n = min(65_535, raw.count - i)
            let final: UInt8 = i + n >= raw.count ? 1 : 0
            z += [final, UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
            z += raw[i..<(i + n)]
            i += n
        } while i < raw.count
        var a: UInt32 = 1, b: UInt32 = 0
        for x in raw { a = (a + UInt32(x)) % 65_521; b = (b + a) % 65_521 }
        z += be32(b << 16 | a)
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            let body = Array(type.utf8) + data
            return be32(UInt32(data.count)) + body + be32(CRC32.checksum(body))
        }
        let ihdr = be32(UInt32(w)) + be32(UInt32(h)) + [8, 2, 0, 0, 0]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", ihdr) + chunk("IDAT", z) + chunk("IEND", []))
    }

    /// Zip with every entry stored (method 0 unless overridden), fixed timestamps.
    static func zip(_ files: [(String, Data)], method: UInt16 = 0, flags: UInt16 = 0) -> Data {
        var out: [UInt8] = [], central: [UInt8] = []
        for (name, data) in files {
            let n = Array(name.utf8), d = [UInt8](data), crc = CRC32.checksum(d)
            let offset = out.count
            out += le32(0x0403_4B50) + le16(20) + le16(flags) + le16(method) + le16(0) + le16(0x21) + le32(crc)
            out += le32(UInt32(d.count)) + le32(UInt32(d.count)) + le16(UInt16(n.count)) + le16(0) + n + d
            central += le32(0x0201_4B50) + le16(20) + le16(20) + le16(flags) + le16(method) + le16(0) + le16(0x21) + le32(crc)
            central += le32(UInt32(d.count)) + le32(UInt32(d.count)) + le16(UInt16(n.count)) + le16(0) + le16(0) + le16(0)
            central += le16(0) + le32(0) + le32(UInt32(offset)) + n
        }
        let cdOffset = out.count
        out += central
        out += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(files.count)) + le16(UInt16(files.count))
        out += le32(UInt32(central.count)) + le32(UInt32(cdOffset)) + le16(0)
        return Data(out)
    }

    static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }
    static func be32(_ v: UInt32) -> [UInt8] { (0..<4).reversed().map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }
}

/// SHA-256 (FIPS 180-4) for the injected installer hasher in tests (the app uses CryptoKit).
enum TestSHA256 {
    static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    @Sendable static func hex(_ data: Data) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var msg = [UInt8](data)
        let bitLength = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in (0..<8).reversed() { msg.append(UInt8((bitLength >> (8 * UInt64(i))) & 0xFF)) }
        @inline(__always) func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: msg.count, by: 64) {
            for t in 0..<16 {
                let o = chunk + 4 * t
                w[t] = UInt32(msg[o]) << 24 | UInt32(msg[o + 1]) << 16 | UInt32(msg[o + 2]) << 8 | UInt32(msg[o + 3])
            }
            for t in 16..<64 {
                let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for t in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[t] &+ w[t]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
