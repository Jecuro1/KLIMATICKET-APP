import Foundation

/// HAFAS HCI responses → domain values (SPEC §A3.2, §A3.4). Pure and stateless: no I/O, no clock.
/// Error mapping: top-level `err` first (AUTH → `.blocked`, PARSE/HAMM → `.decoding`, other → `.hafas`), then the
/// addressed `svcResL[i].err` (H890 → `.noConnection`, other → `.hafas(code:message:)` with the German `errTxtOut`).
public enum HafasCodec {

    // MARK: - Public API

    /// TripSearch / Reconstruction. An empty `outConL` is `.noConnection`.
    public static func journeyPage(from data: Data, serviceIndex: Int = 0) throws -> JourneyPage {
        let res = try serviceResult(from: data, serviceIndex: serviceIndex)
        return try journeyPage(res)
    }

    /// Batch TripSearch / Reconstruction: one result per `svcResL` element, errors isolated per element.
    /// Throws only for envelope-level problems (non-JSON, top-level `err`).
    public static func journeyPages(from data: Data) throws -> [Result<JourneyPage, LiveError>] {
        let raw = try envelope(from: data)
        return (raw.svcResL ?? []).map { svc in
            do {
                return .success(try journeyPage(try checked(svc)))
            } catch let e as LiveError {
                return .failure(e)
            } catch {
                return .failure(.decoding(String(describing: error)))
            }
        }
    }

    /// StationBoard; entries sorted by effective time (realtime, else planned).
    public static func board(from data: Data, serviceIndex: Int = 0) throws -> Board {
        let res = try serviceResult(from: data, serviceIndex: serviceIndex)
        let ctx = Context(res.common)
        let kind = BoardKind(rawValue: res.type ?? "DEP") ?? .departures
        let entries = (res.jnyL ?? []).compactMap { ctx.boardEntry($0, kind: kind) }
        return Board(kind: kind, entries: sortedByEffectiveTime(entries), realtimeUpdatedAt: HafasTime.epoch(res.planrtTS))
    }

    /// JourneyDetails: the whole run (stopovers with `index`, polyline when requested).
    public static func trip(from data: Data, serviceIndex: Int = 0) throws -> TripDetails {
        let res = try serviceResult(from: data, serviceIndex: serviceIndex)
        guard let j = res.journey else { throw LiveError.decoding("JourneyDetails ohne journey") }
        return Context(res.common).trip(j, updatedAt: HafasTime.epoch(res.planrtTS))
    }

    /// LocMatch (`res.match.locL`) or LocGeoPos (`res.locL`, sorted by distance). A `query` enables the nonsense
    /// filter (SPEC §A3.3: LocMatch never fails and returns popular stations for garbage input).
    public static func locations(from data: Data, serviceIndex: Int = 0, query: String? = nil) throws -> [Location] {
        let res = try serviceResult(from: data, serviceIndex: serviceIndex)
        let ctx = Context(res.common)
        if let match = res.match {
            let all = (match.locL ?? []).compactMap(ctx.location)
            guard let query else { return all }
            return all.filter { plausibleMatch(name: $0.name, query: query) }
        }
        let near = (res.locL ?? []).compactMap(ctx.location)
        return near.enumerated().sorted { a, b in
            let da = a.element.distanceMeters ?? Int.max, db = b.element.distanceMeters ?? Int.max
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
    }

    /// HimSearch: disruption messages (`res.msgL` holds the HIM objects).
    public static func remarks(from data: Data, serviceIndex: Int = 0) throws -> [Remark] {
        let res = try serviceResult(from: data, serviceIndex: serviceIndex)
        let ctx = Context(res.common)
        return dedupe((res.msgL ?? []).compactMap(ctx.him))
    }

    /// Envelope-level error (HTTP 200 with top-level `err`), nil when OK. Non-JSON → `.decoding`.
    public static func envelopeError(_ data: Data) -> LiveError? {
        envelopeError(data, provider: .oebbHafas)
    }

    /// Same as `envelopeError(_:)` for another HAFAS back end (VAO): AUTH maps to `.blocked(provider)`.
    public static func envelopeError(_ data: Data, provider: LiveProvider) -> LiveError? {
        do {
            let raw = try decodeRaw(data)
            return topError(raw, provider: provider)
        } catch let e as LiveError {
            return e
        } catch {
            return .decoding(String(describing: error))
        }
    }

    /// Service-level error of `svcResL[serviceIndex]` (nil when OK). For callers that decode `res` themselves (VAO).
    public static func serviceError(_ data: Data, serviceIndex: Int = 0, provider: LiveProvider = .oebbHafas) -> LiveError? {
        do {
            _ = try serviceResult(from: data, serviceIndex: serviceIndex, provider: provider)
            return nil
        } catch let e as LiveError {
            return e
        } catch {
            return .decoding(String(describing: error))
        }
    }

    /// ServerInfo (Settings „Verbindung testen“).
    static func serverInfo(from data: Data) throws -> HafasServerInfo {
        let res = try serviceResult(from: data, serviceIndex: 0)
        var time: Date?
        if let d = res.sD, let t = res.sT { time = HafasTime.date(base: d, time: t, tzOffsetMinutes: nil) }
        return HafasServerInfo(hciVersion: res.hciVersion, serverVersion: res.serverVersion, serverTime: time,
                               timetableFrom: res.fpB, timetableTo: res.fpE)
    }

    // MARK: - Envelope

    static func decodeRaw(_ data: Data) throws -> HafasRawResponse {
        guard let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }), first == UInt8(ascii: "{") else {
            throw LiveError.decoding("Keine JSON-Antwort")
        }
        do {
            return try JSONDecoder().decode(HafasRawResponse.self, from: data)
        } catch {
            throw LiveError.decoding("Ungültiges JSON: \(error)")
        }
    }

    static func topError(_ raw: HafasRawResponse, provider: LiveProvider = .oebbHafas) -> LiveError? {
        let code = raw.err ?? "OK"
        switch code {
        case "OK": return nil
        case "AUTH": return .blocked(provider)
        case "PARSE", "HAMM": return .decoding(raw.errTxt ?? raw.hammError ?? code)
        default: return .hafas(code: code, message: raw.errTxt)
        }
    }

    static func envelope(from data: Data, provider: LiveProvider = .oebbHafas) throws -> HafasRawResponse {
        let raw = try decodeRaw(data)
        if let e = topError(raw, provider: provider) { throw e }
        return raw
    }

    static func serviceResult(from data: Data, serviceIndex: Int, provider: LiveProvider = .oebbHafas) throws -> HafasRawRes {
        let raw = try envelope(from: data, provider: provider)
        let list = raw.svcResL ?? []
        guard list.indices.contains(serviceIndex) else { throw LiveError.decoding("svcResL[\(serviceIndex)] fehlt") }
        return try checked(list[serviceIndex])
    }

    /// Maps `svcResL[i].err` (SPEC §A3.2).
    static func checked(_ svc: HafasRawServiceResult) throws -> HafasRawRes {
        let code = svc.err ?? "OK"
        if code != "OK" { throw serviceError(code: code, errTxtOut: svc.errTxtOut, errTxt: svc.errTxt) }
        guard let res = svc.res else { throw LiveError.decoding("\(svc.meth ?? "HCI") ohne res") }
        return res
    }

    static func serviceError(code: String, errTxtOut: String?, errTxt: String?) -> LiveError {
        switch code {
        case "H890": return .noConnection
        case "LOCATION", "H9380", "H9381": return .hafas(code: code, message: errTxtOut)
        default: return .hafas(code: code, message: errTxtOut ?? errTxt)
        }
    }

    static func journeyPage(_ res: HafasRawRes) throws -> JourneyPage {
        let ctx = Context(res.common)
        let updatedAt = HafasTime.epoch(res.planrtTS)
        let journeys = (res.outConL ?? []).enumerated().map { ctx.journey($0.element, position: $0.offset, updatedAt: updatedAt) }
        guard !journeys.isEmpty else { throw LiveError.noConnection }
        return JourneyPage(journeys: journeys, earlierContext: res.outCtxScrB, laterContext: res.outCtxScrF, realtimeUpdatedAt: updatedAt)
    }

    // MARK: - Helpers

    static func sortedByEffectiveTime(_ entries: [BoardEntry]) -> [BoardEntry] {
        entries.enumerated().sorted { a, b in
            switch (a.element.event.effective, b.element.event.effective) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Deduplicates by `(kind, id ?? text)`, keeping the first occurrence.
    static func dedupe(_ remarks: [Remark]) -> [Remark] {
        var seen = Set<String>()
        return remarks.filter { seen.insert("\($0.kind.rawValue)|\($0.id ?? $0.text)").inserted }
    }

    /// SPEC §A3.3 nonsense filter: kept when, for at least one normalized query token of ≥ 3 characters, some token of the
    /// normalized result name starts with it or has a same-length prefix within Levenshtein distance 2.
    static func plausibleMatch(name: String, query: String) -> Bool {
        let q = StationIndex.normalize(query.replacingOccurrences(of: "?", with: " ")).split(separator: " ").map(String.init).filter { $0.count >= 3 }
        guard !q.isEmpty else { return true }
        let tokens = StationIndex.normalize(name).split(separator: " ").map(String.init)
        for qt in q {
            for t in tokens {
                if t.hasPrefix(qt) { return true }
                if t.count >= qt.count, StationIndex.levenshtein(String(t.prefix(qt.count)), qt, limit: 2) != nil { return true }
            }
        }
        return false
    }

    static func shopURL(_ trf: HafasRawTariffResult?) -> URL? {
        guard let trf else { return nil }
        if let content = trf.extContActionBar?.content, content.type == "URL_EXT", let b64 = content.content,
           let data = Data(base64Encoded: paddedBase64(b64)), let s = String(data: data, encoding: .utf8), let url = URL(string: s) {
            return url
        }
        if let click = trf.clickout, let url = URL(string: click) { return url }
        return nil
    }

    private static func paddedBase64(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let rem = t.count % 4
        return rem == 0 ? t : t + String(repeating: "=", count: 4 - rem)
    }

    static func mode(forClass cls: Int) -> TransportMode {
        switch cls {
        case 1, 4, 8, 16, 4096: return .train
        case 2, 64, 1024: return .bus
        case 32: return .sBahn
        case 128: return .ferry
        case 256: return .metro
        case 512: return .tram
        case 2048: return .cableCar
        default: return .other
        }
    }

    // MARK: - Index resolution over res.common (per svcResL element)

    struct Context {
        let locL: [HafasRawLoc]
        let prodL: [HafasRawProd]
        let opL: [HafasRawOperator]
        let remL: [HafasRawRem]
        let himL: [HafasRawHim]
        let polyL: [HafasRawPoly]
        let dirL: [HafasRawDir]

        init(_ common: HafasRawCommon?) {
            locL = common?.locL ?? []
            prodL = common?.prodL ?? []
            opL = common?.opL ?? []
            remL = common?.remL ?? []
            himL = common?.himL ?? []
            polyL = common?.polyL ?? []
            dirL = common?.dirL ?? []
        }

        private static func at<T>(_ list: [T], _ i: Int?) -> T? {
            guard let i, list.indices.contains(i) else { return nil }
            return list[i]
        }

        // Locations

        func location(_ l: HafasRawLoc) -> Location? {
            let name = (l.name ?? "").trimmingCharacters(in: .whitespaces)
            guard let lid = l.lid ?? l.extId.map({ "A=1@L=\($0)@" }) else { return nil }
            let kind: Location.Kind
            switch l.type {
            case "A": kind = .address
            case "P": kind = .poi
            default: kind = .station
            }
            var coord: GeoPoint?
            if let x = l.crd?.x, let y = l.crd?.y { coord = GeoPoint(latitude: Double(y) / 1e6, longitude: Double(x) / 1e6) }
            return Location(lid: lid, kind: kind, extId: l.extId, name: name.isEmpty ? (l.extId ?? "Unbekannter Ort") : name,
                            coordinate: coord, products: ProductMask(rawValue: l.pCls ?? 0), isMeta: l.meta == true,
                            distanceMeters: l.dist, countryCode: l.countryCodeL?.first?.lowercased(),
                            uicCode: l.globalIdL?.first(where: { $0.type == "U" })?.id,
                            minTransferSeconds: HafasTime.duration(l.chgTime))
        }

        func location(at index: Int?) -> Location? {
            Self.at(locL, index).flatMap(location)
        }

        func locationOrPlaceholder(at index: Int?) -> Location {
            location(at: index) ?? Location(lid: "", kind: .station, name: "Unbekannter Halt")
        }

        // Lines

        func line(at index: Int?) -> Line? {
            guard let p = Self.at(prodL, index) else { return nil }
            let ctx = p.prodCtx
            let cls = p.cls ?? 0
            let catOutS = ctx?.catOutS?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            let number = (ctx?.num ?? p.number)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            var name = ""
            if let catOutS, [1, 4, 8, 4096].contains(cls) || ctx?.line == nil {
                name = number.map { "\(catOutS) \($0)" } ?? catOutS
            }
            if name.isEmpty { name = (p.nameS ?? p.name ?? "").trimmingCharacters(in: .whitespaces) }
            if name.isEmpty { name = ctx?.catOutL?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Verbindung" }
            return Line(name: name, fullName: p.name?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                        category: ctx?.catOut?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                        categoryShort: catOutS, categoryLong: ctx?.catOutL?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                        lineNumber: ctx?.line?.trimmingCharacters(in: .whitespaces).nilIfEmpty, trainNumber: ctx?.num,
                        lineId: ctx?.lineId, admin: ctx?.admin, operatorName: Self.at(opL, p.oprX)?.name,
                        productClass: cls, mode: HafasCodec.mode(forClass: cls))
        }

        // Remarks

        func remarks(_ refs: [HafasRawMsgRef]?) -> [Remark] {
            guard let refs, !refs.isEmpty else { return [] }
            var out: [Remark] = []
            for m in refs {
                switch m.type {
                case "REM":
                    guard let r = Self.at(remL, m.remX) else { continue }
                    let text = HTMLText.plain(r.txtN ?? r.txtS)
                    guard !text.isEmpty else { continue }
                    let kind: Remark.Kind
                    switch r.type {
                    case "A": kind = .attribute
                    case "I": kind = .info
                    case "H": kind = .hint
                    case "R": kind = .realtime
                    default: kind = .other
                    }
                    out.append(Remark(kind: kind, code: r.code, text: text, priority: r.prio))
                case "HIM":
                    if let h = Self.at(himL, m.himX).flatMap(him) { out.append(h) }
                default:
                    continue
                }
            }
            return HafasCodec.dedupe(out)
        }

        func him(_ h: HafasRawHim) -> Remark? {
            let title = h.head.map { HTMLText.plain($0) }?.nilIfEmpty
            let text = HTMLText.plain(h.text ?? h.lead)
            guard title != nil || !text.isEmpty else { return nil }
            func when(_ d: String?, _ t: String?) -> Date? {
                guard let d else { return nil }
                return HafasTime.date(base: d, time: t ?? "000000", tzOffsetMinutes: nil)
            }
            let lines = (h.affProdRefL ?? []).compactMap { line(at: $0)?.name }
            var unique: [String] = []
            for l in lines where !unique.contains(l) { unique.append(l) }
            return Remark(kind: .disruption, id: h.hid, title: title, text: text.isEmpty ? (title ?? "") : text, priority: h.prio,
                          validFrom: when(h.sDate, h.sTime), validUntil: when(h.eDate, h.eTime),
                          modifiedAt: when(h.lModDate, h.lModTime), affectedLines: unique)
        }

        // Stop events

        enum Side { case departure, arrival }

        func event(_ s: HafasRawStop, _ side: Side, base: String?) -> StopEvent? {
            let timeS: String?, timeR: String?, offS: Int?, offR: Int?
            let pS: HafasRawPlatform?, pR: HafasRawPlatform?, legacyS: String?, legacyR: String?
            let prog: String?, cncl: Bool?, platfCh: Bool?
            switch side {
            case .departure:
                (timeS, timeR, offS, offR) = (s.dTimeS, s.dTimeR, s.dTZOffset, s.dTZOffsetR)
                (pS, pR, legacyS, legacyR) = (s.dPltfS, s.dPltfR, s.dPlatfS, s.dPlatfR)
                (prog, cncl, platfCh) = (s.dProgType, s.dCncl, s.dPlatfCh)
            case .arrival:
                (timeS, timeR, offS, offR) = (s.aTimeS, s.aTimeR, s.aTZOffset, s.aTZOffsetR)
                (pS, pR, legacyS, legacyR) = (s.aPltfS, s.aPltfR, s.aPlatfS, s.aPlatfR)
                (prog, cncl, platfCh) = (s.aProgType, s.aCncl, s.aPlatfCh)
            }
            guard timeS != nil || timeR != nil || cncl == true else { return nil }
            let planned = base.flatMap { b in timeS.flatMap { HafasTime.date(base: b, time: $0, tzOffsetMinutes: offS) } }
            let realtime = base.flatMap { b in timeR.flatMap { HafasTime.date(base: b, time: $0, tzOffsetMinutes: offR ?? offS) } }
            let prognosis: StopEvent.Prognosis?
            switch prog {
            case nil: prognosis = nil
            case "PROGNOSED": prognosis = .prognosed
            case "REPORTED": prognosis = .reported
            default: prognosis = .other
            }
            return StopEvent(planned: planned, realtime: realtime, plannedPlatform: platform(pS, legacy: legacyS),
                             realtimePlatform: platform(pR, legacy: legacyR), isCancelled: cncl == true, prognosis: prognosis,
                             platformChangeFlag: platfCh == true)
        }

        func platform(_ p: HafasRawPlatform?, legacy: String?) -> Platform? {
            if let p, let txt = p.txt?.trimmingCharacters(in: .whitespaces), !txt.isEmpty {
                let kind: Platform.Kind
                switch p.type {
                case "PL": kind = .track
                case "ST": kind = .stand
                default: kind = .unknown
                }
                return Platform(text: txt, kind: kind)
            }
            if let legacy = legacy?.trimmingCharacters(in: .whitespaces), !legacy.isEmpty { return Platform(text: legacy, kind: .unknown) }
            return nil
        }

        func stopover(_ s: HafasRawStop, base: String?) -> Stopover {
            Stopover(location: locationOrPlaceholder(at: s.locX), arrival: event(s, .arrival, base: base),
                     departure: event(s, .departure, base: base), index: s.idx, isAdditional: s.isAdd == true,
                     passesWithoutStop: s.dInS == false && s.aOutS == false, isBorder: s.border == true, remarks: remarks(s.msgL))
        }

        // Polylines

        func polyline(_ group: HafasRawPolyGroup?, inline: HafasRawPoly? = nil) -> [GeoPoint]? {
            let segments = (group?.polyXL ?? []).compactMap { Self.at(polyL, $0)?.crdEncYX }.map { Polyline.decode($0) }
            var points = Polyline.concatenate(segments)
            if points.isEmpty, let enc = inline?.crdEncYX { points = Polyline.decode(enc) }
            return points.isEmpty ? nil : points
        }

        static func coordinate(_ c: HafasRawCoord?) -> GeoPoint? {
            guard let x = c?.x, let y = c?.y else { return nil }
            return GeoPoint(latitude: Double(y) / 1e6, longitude: Double(x) / 1e6)
        }

        // Journeys

        func direction(_ j: HafasRawJourney) -> String? {
            if let t = j.dirTxt?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
            return Self.at(dirL, j.dirL?.first?.dirX)?.txt
        }

        func leg(_ sec: HafasRawSection, cid: String, position: Int, base: String?) -> Leg? {
            let type = sec.type ?? ""
            if sec.hide == true && type != "JNY" { return nil }
            let dep = sec.dep, arr = sec.arr
            let departure = dep.flatMap { event($0, .departure, base: base) } ?? StopEvent()
            let arrival = arr.flatMap { event($0, .arrival, base: base) } ?? StopEvent()
            let origin = locationOrPlaceholder(at: dep?.locX)
            let destination = locationOrPlaceholder(at: arr?.locX)
            let id = sec.id ?? "\(cid)-\(position)"
            if type == "JNY" {
                let j = sec.jny
                let jBase = j?.date ?? base
                let stops = (j?.stopL ?? []).map { stopover($0, base: jBase) }
                let cancelled = j?.isCncl == true || dep?.dCncl == true || arr?.aCncl == true
                return Leg(id: id, kind: .ride, origin: origin, destination: destination, departure: departure, arrival: arrival,
                           line: line(at: j?.prodX), direction: j.flatMap(direction), tripID: j?.jid, stopovers: stops,
                           remarks: remarks(j?.msgL), polyline: polyline(j?.polyG, inline: j?.poly), isReachable: j?.isRchbl,
                           isCancelled: cancelled, isPartiallyCancelled: j?.isPartCncl == true,
                           currentPosition: Self.coordinate(j?.pos))
            }
            let gis = sec.gis
            let kind: Leg.Kind
            switch type {
            case "WALK": kind = (gis?.dist ?? 0) > 0 ? .walk : .transfer
            case "TRSF": kind = .transfer
            default: kind = .walk // GIS, KISS, DEVI, CHKI, CHKO, …
            }
            return Leg(id: id, kind: kind, origin: origin, destination: destination, departure: departure, arrival: arrival,
                       walkDistanceMeters: gis?.dist, walkDurationSeconds: HafasTime.duration(gis?.durS) ?? HafasTime.duration(sec.chg?.durS),
                       remarks: remarks(gis?.msgL), polyline: polyline(gis?.polyG),
                       isCancelled: dep?.dCncl == true || arr?.aCncl == true)
        }

        func journey(_ c: HafasRawConnection, position: Int, updatedAt: Date?) -> Journey {
            let cid = c.cid ?? "C-\(position)"
            let legs = (c.secL ?? []).enumerated().compactMap { leg($0.element, cid: cid, position: $0.offset, base: c.date) }
            return Journey(legs: legs, durationSeconds: HafasTime.duration(c.dur), changes: c.chg ?? max(0, legs.filter { $0.kind == .ride }.count - 1),
                           refreshToken: c.recon?.ctx ?? c.ctxRecon, checksum: c.cksum, serviceDays: c.sDays?.sDaysR,
                           serviceDaysDetail: c.sDays?.sDaysI, remarks: remarks(c.msgL), isAlternative: c.isAlt == true,
                           shopURL: HafasCodec.shopURL(c.trfRes), realtimeUpdatedAt: updatedAt)
        }

        func trip(_ j: HafasRawJourney, updatedAt: Date?) -> TripDetails {
            TripDetails(tripID: j.jid ?? "", line: line(at: j.prodX), direction: direction(j),
                        stopovers: (j.stopL ?? []).map { stopover($0, base: j.date) }, polyline: polyline(j.polyG, inline: j.poly),
                        currentPosition: Self.coordinate(j.pos), remarks: remarks(j.msgL), isCancelled: j.isCncl == true,
                        isPartiallyCancelled: j.isPartCncl == true, realtimeUpdatedAt: updatedAt)
        }

        func boardEntry(_ j: HafasRawJourney, kind: BoardKind) -> BoardEntry? {
            guard let s = j.stbStop else { return nil }
            guard var ev = event(s, kind == .departures ? .departure : .arrival, base: j.date) else { return nil }
            if j.isCncl == true { ev.isCancelled = true }
            let ref = j.prodL?.first
            let other = location(at: kind == .departures ? ref?.tLocX : ref?.fLocX)
            return BoardEntry(tripID: j.jid ?? "", line: line(at: j.prodX ?? ref?.prodX), direction: direction(j),
                              stop: locationOrPlaceholder(at: s.locX), event: ev, terminusOrOrigin: other, remarks: remarks(j.msgL),
                              isRedirected: j.isRedir == true, currentPosition: Self.coordinate(j.pos))
        }
    }
}

/// Result of `HafasClient.serverInfo()` (Settings „Verbindung testen“).
public struct HafasServerInfo: Sendable, Hashable {
    public var hciVersion: String?
    public var serverVersion: String?
    public var serverTime: Date?
    /// Timetable period `fpB` / `fpE` ("20260807" … "20271211").
    public var timetableFrom: String?
    public var timetableTo: String?

    public init(hciVersion: String? = nil, serverVersion: String? = nil, serverTime: Date? = nil, timetableFrom: String? = nil,
                timetableTo: String? = nil) {
        self.hciVersion = hciVersion
        self.serverVersion = serverVersion
        self.serverTime = serverTime
        self.timetableFrom = timetableFrom
        self.timetableTo = timetableTo
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
