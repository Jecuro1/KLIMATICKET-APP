import Foundation

// HAFAS HCI request envelope + service-request encoders (SPEC §A3.1, §A3.3). Shared with the VAO tariff client (WP-B).
// The `/gate` parser is strict: an unknown key or enum value rejects the whole envelope with err PARSE. So every
// encoder below emits exactly the keys of §A3.3; optionals are omitted (synthesized Encodable uses encodeIfPresent),
// never `null`, and `cfg.rtMode` is never sent.

/// `{"lang","ver","ext"?,"client":{id,type,name,l?,v?},"auth":{"type":"AID","aid"},"svcReqL":[…]}`.
public struct HafasEnvelope<Request: Encodable>: Encodable {
    public struct Auth: Encodable, Sendable, Hashable {
        public var type: String
        public var aid: String

        public init(type: String = "AID", aid: String) {
            self.type = type
            self.aid = aid
        }
    }

    public var lang: String
    public var ver: String
    public var ext: String?
    public var client: HafasProfile.Client
    public var auth: Auth
    public var svcReqL: [Request]

    public init(profile: HafasProfile, svcReqL: [Request]) {
        lang = profile.lang
        ver = profile.ver
        ext = profile.ext
        client = profile.client
        auth = Auth(aid: profile.aid)
        self.svcReqL = svcReqL
    }
}

/// One element of `svcReqL`: `{"meth":"TripSearch","cfg":{"polyEnc":"GPA"}?,"req":{…}}`.
public struct HafasServiceRequest<Req: Encodable>: Encodable {
    public var meth: String
    public var cfg: HafasRequestConfig?
    public var req: Req

    public init(meth: String, cfg: HafasRequestConfig? = nil, req: Req) {
        self.meth = meth
        self.cfg = cfg
        self.req = req
    }
}

/// `cfg` of a service request. Only `polyEnc` is allowed (`rtMode` gives PARSE on `/gate`).
public struct HafasRequestConfig: Encodable, Sendable, Hashable {
    public var polyEnc: String?

    public init(polyEnc: String? = "GPA") { self.polyEnc = polyEnc }

    public static let gpa = HafasRequestConfig(polyEnc: "GPA")
}

/// Minimal location reference `{"lid":"A=1@L=8100108@","type":"S"}`.
public struct HafasLocationRef: Encodable, Sendable, Hashable {
    public var lid: String
    public var type: String

    public init(lid: String, type: String = "S") {
        self.lid = lid
        self.type = type
    }

    public init(_ location: Location) {
        self.init(lid: location.lid, type: location.kind.rawValue)
    }
}

/// `jnyFltrL` / `locFltrL` / `himFltrL` element. PROD values are Strings ("8191").
public struct HafasFilter: Encodable, Sendable, Hashable {
    public var type: String
    public var mode: String
    public var value: String?
    public var meta: String?

    public init(type: String, mode: String = "INC", value: String? = nil, meta: String? = nil) {
        self.type = type
        self.mode = mode
        self.value = value
        self.meta = meta
    }

    public static func products(_ mask: ProductMask) -> HafasFilter { HafasFilter(type: "PROD", value: String(mask.rawValue)) }
    public static let bikeCarriage = HafasFilter(type: "BC")
    public static func accessibility(_ a: JourneyQuery.Accessibility) -> HafasFilter { HafasFilter(type: "META", meta: a.rawValue) }
}

// MARK: - Service request bodies (ÖBB HAFAS, §A3.3)

enum HafasRequests {
    struct LocMatchLoc: Encodable { var type: String; var name: String }
    struct LocMatchInput: Encodable { var loc: LocMatchLoc; var maxLoc: Int; var field: String }
    struct LocMatch: Encodable { var input: LocMatchInput }

    struct Coord: Encodable { var x: Int; var y: Int }
    struct Ring: Encodable { var cCrd: Coord; var maxDist: Int; var minDist: Int }
    struct LocGeoPos: Encodable {
        var ring: Ring
        var getStops: Bool
        var getPOIs: Bool
        var maxLoc: Int
        var locFltrL: [HafasFilter]
    }

    struct ViaLoc: Encodable { var loc: HafasLocationRef; var min: Int? }
    struct TripSearch: Encodable {
        var depLocL: [HafasLocationRef]
        var arrLocL: [HafasLocationRef]
        var viaLocL: [ViaLoc]?
        var outDate: String?
        var outTime: String?
        var outFrwd: Bool?
        var ctxScr: String?
        var maxChg: Int
        var minChgTime: Int
        var numF: Int
        var getPasslist: Bool
        var getPolyline: Bool
        var getPT: Bool
        var getIV: Bool
        var getTariff: Bool
        var ushrp: Bool
        var jnyFltrL: [HafasFilter]
    }

    struct ReconCtx: Encodable { var ctx: String }
    struct Reconstruction: Encodable {
        var outReconL: [ReconCtx]
        var getIST: Bool
        var getPasslist: Bool
        var getPolyline: Bool
    }

    struct JourneyDetails: Encodable { var jid: String; var getPolyline: Bool }

    struct StationBoard: Encodable {
        var type: String
        var stbLoc: HafasLocationRef
        var date: String
        var time: String
        var dur: Int
        var maxJny: Int
        var jnyFltrL: [HafasFilter]
    }

    struct HimSearch: Encodable {
        var maxNum: Int
        var dateB: String
        var timeB: String
        var dateE: String
        var timeE: String
        var himFltrL: [HafasFilter]?
    }

    struct ServerInfo: Encodable { var getVersionInfo: Bool; var getClientFilter: Bool; var getServerDateTime: Bool }

    // Builders

    static func locMatch(_ query: String, types: LocationTypes, maxResults: Int) -> HafasServiceRequest<LocMatch> {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return HafasServiceRequest(meth: "LocMatch", req: LocMatch(input: LocMatchInput(
            loc: LocMatchLoc(type: types.rawValue, name: name.hasSuffix("?") ? name : name + "?"), maxLoc: maxResults, field: "S")))
    }

    /// Coordinates are rounded to 3 decimals (≈ 110 m) before they leave the device (SPEC §2.7).
    static func locGeoPos(_ point: GeoPoint, maxDistanceMeters: Int, maxResults: Int, products: ProductMask) -> HafasServiceRequest<LocGeoPos> {
        let x = Int((point.longitude * 1000).rounded()) * 1000
        let y = Int((point.latitude * 1000).rounded()) * 1000
        return HafasServiceRequest(meth: "LocGeoPos", req: LocGeoPos(
            ring: Ring(cCrd: Coord(x: x, y: y), maxDist: maxDistanceMeters, minDist: 0), getStops: true, getPOIs: false,
            maxLoc: maxResults, locFltrL: [.products(products)]))
    }

    static func tripSearch(_ q: JourneyQuery) -> HafasServiceRequest<TripSearch> {
        var filters: [HafasFilter] = [.products(q.products)]
        if q.bikeCarriage { filters.append(.bikeCarriage) }
        if let a = q.accessibility { filters.append(.accessibility(a)) }
        let via = q.via.prefix(JourneyQuery.maxViaStops).map { stop in
            ViaLoc(loc: HafasLocationRef(stop.location), min: stop.minimumDwellMinutes.flatMap { $0 > 0 ? $0 : nil })
        }
        let paging = q.pageContext != nil
        return HafasServiceRequest(meth: "TripSearch", cfg: .gpa, req: TripSearch(
            depLocL: [HafasLocationRef(q.origin)], arrLocL: [HafasLocationRef(q.destination)],
            viaLocL: via.isEmpty ? nil : Array(via),
            outDate: paging ? nil : HafasTime.dateString(q.date), outTime: paging ? nil : HafasTime.timeString(q.date),
            outFrwd: paging ? nil : !q.isArrival, ctxScr: q.pageContext,
            maxChg: q.maxChanges ?? -1, minChgTime: q.minTransferMinutes ?? -1, numF: q.results,
            getPasslist: q.includeStopovers, getPolyline: q.includePolyline, getPT: true, getIV: false, getTariff: true,
            ushrp: true, jnyFltrL: filters))
    }

    static func reconstruction(_ token: String, includeStopovers: Bool, includePolyline: Bool) -> HafasServiceRequest<Reconstruction> {
        HafasServiceRequest(meth: "Reconstruction", cfg: .gpa, req: Reconstruction(
            outReconL: [ReconCtx(ctx: token)], getIST: true, getPasslist: includeStopovers, getPolyline: includePolyline))
    }

    static func journeyDetails(_ tripID: String, includePolyline: Bool) -> HafasServiceRequest<JourneyDetails> {
        HafasServiceRequest(meth: "JourneyDetails", cfg: .gpa, req: JourneyDetails(jid: tripID, getPolyline: includePolyline))
    }

    static func stationBoard(_ q: BoardQuery) -> HafasServiceRequest<StationBoard> {
        HafasServiceRequest(meth: "StationBoard", req: StationBoard(
            type: q.kind.rawValue, stbLoc: HafasLocationRef(q.station), date: HafasTime.dateString(q.date),
            time: HafasTime.timeString(q.date), dur: q.durationMinutes, maxJny: q.maxResults, jnyFltrL: [.products(q.products)]))
    }

    static func himSearch(_ q: RemarksQuery) -> HafasServiceRequest<HimSearch> {
        HafasServiceRequest(meth: "HimSearch", req: HimSearch(
            maxNum: q.maxResults, dateB: HafasTime.dateString(q.from), timeB: HafasTime.timeString(q.from),
            dateE: HafasTime.dateString(q.to), timeE: HafasTime.timeString(q.to), himFltrL: q.products.map { [.products($0)] }))
    }

    static func serverInfo() -> HafasServiceRequest<ServerInfo> {
        HafasServiceRequest(meth: "ServerInfo", req: ServerInfo(getVersionInfo: true, getClientFilter: true, getServerDateTime: true))
    }
}
