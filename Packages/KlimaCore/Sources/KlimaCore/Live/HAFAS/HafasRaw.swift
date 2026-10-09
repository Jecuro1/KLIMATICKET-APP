import Foundation

// Raw Decodable mirrors of HAFAS HCI responses (SPEC §A3.4). Every field is optional and tolerant: unknown keys are
// ignored, and a field whose JSON type drifted (Int ↔ String, object ↔ array …) decodes as nil instead of failing the
// whole response. Only the fields the codec reads are declared (e.g. the large `freq.jnyL` alternatives are skipped).

/// Decodes `Value` when present and well-typed, else nil. Numeric strings are accepted for Int and Ints for String.
@propertyWrapper
struct Lenient<Value: Decodable>: Decodable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.singleValueContainer(), !c.decodeNil() else {
            wrappedValue = nil
            return
        }
        if let v = try? c.decode(Value.self) {
            wrappedValue = v
        } else if Value.self == Int.self, let s = try? c.decode(String.self), let i = Int(s.trimmingCharacters(in: .whitespaces)) {
            wrappedValue = i as? Value
        } else if Value.self == String.self, let i = try? c.decode(Int.self) {
            wrappedValue = String(i) as? Value
        } else {
            wrappedValue = nil
        }
    }
}

extension KeyedDecodingContainer {
    func decode<V>(_ type: Lenient<V>.Type, forKey key: Key) throws -> Lenient<V> {
        (try? decodeIfPresent(type, forKey: key)) ?? Lenient(wrappedValue: nil)
    }
}

struct HafasRawResponse: Decodable {
    @Lenient var ver: String?
    @Lenient var err: String?
    @Lenient var errTxt: String?
    @Lenient var hammError: String?
    @Lenient var svcResL: [HafasRawServiceResult]?
}

/// Top-level status only (`err`, `errTxt`, `hammError`): the cheap envelope check before the full decode.
struct HafasRawStatus: Decodable {
    @Lenient var err: String?
    @Lenient var errTxt: String?
    @Lenient var hammError: String?
}

struct HafasRawServiceResult: Decodable {
    @Lenient var meth: String?
    @Lenient var err: String?
    @Lenient var errTxt: String?
    @Lenient var errTxtOut: String?
    @Lenient var res: HafasRawRes?
}

struct HafasRawRes: Decodable {
    @Lenient var common: HafasRawCommon?
    // TripSearch / Reconstruction
    @Lenient var outConL: [HafasRawConnection]?
    @Lenient var outCtxScrB: String?
    @Lenient var outCtxScrF: String?
    @Lenient var planrtTS: String?
    // LocMatch / LocGeoPos
    @Lenient var match: HafasRawMatch?
    @Lenient var locL: [HafasRawLoc]?
    // JourneyDetails
    @Lenient var journey: HafasRawJourney?
    // StationBoard
    @Lenient var jnyL: [HafasRawJourney]?
    @Lenient var type: String?
    // HimSearch (`msgL` holds the HIM objects themselves here)
    @Lenient var msgL: [HafasRawHim]?
    // ServerInfo
    @Lenient var hciVersion: String?
    @Lenient var serverVersion: String?
    @Lenient var fpB: String?
    @Lenient var fpE: String?
    @Lenient var sD: String?
    @Lenient var sT: String?
}

struct HafasRawCommon: Decodable {
    @Lenient var locL: [HafasRawLoc]?
    @Lenient var prodL: [HafasRawProd]?
    @Lenient var opL: [HafasRawOperator]?
    @Lenient var remL: [HafasRawRem]?
    @Lenient var himL: [HafasRawHim]?
    @Lenient var polyL: [HafasRawPoly]?
    @Lenient var dirL: [HafasRawDir]?
}

struct HafasRawMatch: Decodable {
    @Lenient var locL: [HafasRawLoc]?
}

struct HafasRawCoord: Decodable {
    @Lenient var x: Int?
    @Lenient var y: Int?
}

struct HafasRawGlobalID: Decodable {
    @Lenient var id: String?
    @Lenient var type: String?
}

struct HafasRawLoc: Decodable {
    @Lenient var lid: String?
    @Lenient var type: String?
    @Lenient var name: String?
    @Lenient var extId: String?
    @Lenient var crd: HafasRawCoord?
    @Lenient var pCls: Int?
    @Lenient var meta: Bool?
    @Lenient var dist: Int?
    @Lenient var countryCodeL: [String]?
    @Lenient var globalIdL: [HafasRawGlobalID]?
    @Lenient var chgTime: String?
    @Lenient var msgL: [HafasRawMsgRef]?
}

struct HafasRawProdCtx: Decodable {
    @Lenient var name: String?
    @Lenient var num: String?
    @Lenient var catOut: String?
    @Lenient var catOutS: String?
    @Lenient var catOutL: String?
    @Lenient var line: String?
    @Lenient var lineId: String?
    @Lenient var admin: String?
}

struct HafasRawProd: Decodable {
    @Lenient var name: String?
    @Lenient var nameS: String?
    @Lenient var number: String?
    @Lenient var cls: Int?
    @Lenient var oprX: Int?
    @Lenient var prodCtx: HafasRawProdCtx?
}

struct HafasRawOperator: Decodable {
    @Lenient var name: String?
}

struct HafasRawRem: Decodable {
    @Lenient var type: String?
    @Lenient var code: String?
    @Lenient var txtN: String?
    @Lenient var txtS: String?
    @Lenient var prio: Int?
}

struct HafasRawHim: Decodable {
    @Lenient var hid: String?
    @Lenient var head: String?
    @Lenient var lead: String?
    @Lenient var text: String?
    @Lenient var prio: Int?
    @Lenient var sDate: String?
    @Lenient var sTime: String?
    @Lenient var eDate: String?
    @Lenient var eTime: String?
    @Lenient var lModDate: String?
    @Lenient var lModTime: String?
    @Lenient var affProdRefL: [Int]?
}

struct HafasRawPoly: Decodable {
    @Lenient var crdEncYX: String?
}

struct HafasRawPolyGroup: Decodable {
    @Lenient var polyXL: [Int]?
}

struct HafasRawDir: Decodable {
    @Lenient var txt: String?
}

struct HafasRawDirRef: Decodable {
    @Lenient var dirX: Int?
}

struct HafasRawMsgRef: Decodable {
    @Lenient var type: String?
    @Lenient var remX: Int?
    @Lenient var himX: Int?
}

/// Platform: 1.88 object `{"type":"PL","txt":"3"}`.
struct HafasRawPlatform: Decodable {
    @Lenient var type: String?
    @Lenient var txt: String?
}

/// Stop event holder: `secL[].dep/arr`, `jny.stopL[]`, `stbStop`. Prefix `d` = departure, `a` = arrival.
struct HafasRawStop: Decodable {
    @Lenient var locX: Int?
    @Lenient var idx: Int?
    @Lenient var dTimeS: String?
    @Lenient var dTimeR: String?
    @Lenient var aTimeS: String?
    @Lenient var aTimeR: String?
    @Lenient var dTZOffset: Int?
    @Lenient var dTZOffsetR: Int?
    @Lenient var aTZOffset: Int?
    @Lenient var aTZOffsetR: Int?
    @Lenient var dPltfS: HafasRawPlatform?
    @Lenient var dPltfR: HafasRawPlatform?
    @Lenient var aPltfS: HafasRawPlatform?
    @Lenient var aPltfR: HafasRawPlatform?
    // Legacy string platforms (≤ 1.4x, hafas-client parse/journey-leg.js)
    @Lenient var dPlatfS: String?
    @Lenient var dPlatfR: String?
    @Lenient var aPlatfS: String?
    @Lenient var aPlatfR: String?
    @Lenient var dProgType: String?
    @Lenient var aProgType: String?
    @Lenient var dCncl: Bool?
    @Lenient var aCncl: Bool?
    @Lenient var dPlatfCh: Bool?
    @Lenient var aPlatfCh: Bool?
    @Lenient var isAdd: Bool?
    @Lenient var dInS: Bool?
    @Lenient var aOutS: Bool?
    @Lenient var border: Bool?
    @Lenient var msgL: [HafasRawMsgRef]?
}

/// Per-entry product reference of a board entry (`jnyL[i].prodL`) – NOT the common list.
struct HafasRawProdRef: Decodable {
    @Lenient var prodX: Int?
    @Lenient var fLocX: Int?
    @Lenient var tLocX: Int?
}

struct HafasRawJourney: Decodable {
    @Lenient var jid: String?
    @Lenient var date: String?
    @Lenient var prodX: Int?
    @Lenient var dirTxt: String?
    @Lenient var dirL: [HafasRawDirRef]?
    @Lenient var stopL: [HafasRawStop]?
    @Lenient var isRchbl: Bool?
    @Lenient var isCncl: Bool?
    @Lenient var isPartCncl: Bool?
    @Lenient var isRedir: Bool?
    @Lenient var pos: HafasRawCoord?
    @Lenient var msgL: [HafasRawMsgRef]?
    @Lenient var polyG: HafasRawPolyGroup?
    @Lenient var poly: HafasRawPoly?
    @Lenient var stbStop: HafasRawStop?
    @Lenient var prodL: [HafasRawProdRef]?
}

struct HafasRawGis: Decodable {
    @Lenient var dist: Int?
    @Lenient var durS: String?
    @Lenient var polyG: HafasRawPolyGroup?
    @Lenient var msgL: [HafasRawMsgRef]?
}

struct HafasRawChange: Decodable {
    @Lenient var durS: String?
}

struct HafasRawSection: Decodable {
    @Lenient var type: String?
    @Lenient var id: String?
    @Lenient var hide: Bool?
    @Lenient var dep: HafasRawStop?
    @Lenient var arr: HafasRawStop?
    @Lenient var jny: HafasRawJourney?
    @Lenient var gis: HafasRawGis?
    @Lenient var chg: HafasRawChange?
}

struct HafasRawRecon: Decodable {
    @Lenient var ctx: String?
}

struct HafasRawServiceDays: Decodable {
    @Lenient var sDaysR: String?
    @Lenient var sDaysI: String?
}

struct HafasRawActionContent: Decodable {
    @Lenient var type: String?
    @Lenient var content: String?
}

struct HafasRawActionBar: Decodable {
    @Lenient var content: HafasRawActionContent?
}

struct HafasRawTariffResult: Decodable {
    @Lenient var statusCode: String?
    @Lenient var extContActionBar: HafasRawActionBar?
    @Lenient var clickout: String?
}

struct HafasRawConnection: Decodable {
    @Lenient var cid: String?
    @Lenient var date: String?
    @Lenient var dur: String?
    @Lenient var chg: Int?
    @Lenient var dep: HafasRawStop?
    @Lenient var arr: HafasRawStop?
    @Lenient var secL: [HafasRawSection]?
    @Lenient var recon: HafasRawRecon?
    @Lenient var ctxRecon: String?
    @Lenient var cksum: String?
    @Lenient var sDays: HafasRawServiceDays?
    @Lenient var isAlt: Bool?
    @Lenient var msgL: [HafasRawMsgRef]?
    @Lenient var trfRes: HafasRawTariffResult?
}
