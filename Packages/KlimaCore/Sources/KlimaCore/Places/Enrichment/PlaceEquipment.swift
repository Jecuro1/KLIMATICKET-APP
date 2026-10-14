import Foundation

/// The EQUI section of stops_osm.bin (docs/ENRICH_SPEC.md §1.11): the facilities of each stop from OpenStreetMap.
///
/// Dense layout: one little-endian u64 per stop record, index = stop index (offset 8 × index). Feature `f` has its
/// state in bits 2f…2f+1 (00 not recorded, 01 no, 10 yes, 11 special) and a "from a nearby object" bit at `nearby + f`.
/// Counts and attributes sit in the fields of META.equipment.bits. Slots and fields are resolved by name from META.
///
/// A missing section, missing or foreign META, or an inconsistent layout means "no facility data" (`init` returns nil).
/// It is never an error and never a trap: a corrupt facility section must not switch off the rest of the OSM layer.
struct PlaceEquipment: Sendable {
    private let bytes: [UInt8]
    private let stopCount: Int
    private let slots: [FacilityKind: Int]
    private let fields: [String: (offset: Int, width: Int)]
    private let nearbyBase: Int

    static let fieldNames = ["elevator_n", "toilets_n", "toilets_wheelchair", "toilets_fee", "bicycle_stands",
                             "bicycle_covered", "ticket_n"]

    init?(section: [UInt8]?, meta: [String: Any]?, stopCount: Int) {
        guard let section, let eq = meta?["equipment"] as? [String: Any],
              eq["v"] as? Int == 1, eq["record"] as? String == "u64le",
              stopCount > 0, section.count == 8 * stopCount,
              let names = eq["features"] as? [String], names.count <= 24,
              let bits = eq["bits"] as? [String: Any],
              let nearby = Self.range(bits["nearby"]), nearby.offset >= 2 * names.count,
              nearby.offset + names.count <= 64
        else { return nil }
        var fields: [String: (offset: Int, width: Int)] = [:]
        for name in Self.fieldNames {
            guard let r = Self.range(bits[name]), r.offset >= 2 * names.count,
                  r.offset + r.width <= nearby.offset || r.offset >= nearby.offset + names.count
            else { return nil }
            fields[name] = r
        }
        var slots: [FacilityKind: Int] = [:]
        for (slot, name) in names.enumerated() {
            if let kind = FacilityKind(wireName: name) { slots[kind] = slot }
        }
        self.bytes = section
        self.stopCount = stopCount
        self.slots = slots
        self.fields = fields
        self.nearbyBase = nearby.offset
    }

    /// Facilities of one stop (stop index, RECS order): one entry per kind, `.notRecorded` where OSM says nothing.
    func facilities(stop i: Int) -> [StopFacility] {
        guard i >= 0, i < stopCount else { return [] }
        let word = self.word(i)
        return FacilityKind.allCases.map { decode($0, word: word) }
    }

    // MARK: Decoding

    private func word(_ i: Int) -> UInt64 {
        var w: UInt64 = 0
        for k in 0..<8 { w |= UInt64(bytes[8 * i + k]) << UInt64(8 * k) }
        return w
    }

    private func field(_ word: UInt64, _ name: String) -> (value: Int, capped: Bool) {
        guard let f = fields[name] else { return (0, false) }
        let max = (UInt64(1) << UInt64(f.width)) - 1
        let v = (word >> UInt64(f.offset)) & max
        return (Int(v), v == max)
    }

    private func decode(_ kind: FacilityKind, word: UInt64) -> StopFacility {
        guard let slot = slots[kind] else { return StopFacility(kind: kind, status: .notRecorded) }
        let state = Int((word >> UInt64(2 * slot)) & 3)
        let nearby = (word >> UInt64(nearbyBase + slot)) & 1 == 1
        let status = Self.status(kind, state: state)
        guard status != .notRecorded else { return StopFacility(kind: kind, status: .notRecorded) }
        let source: FacilitySource = nearby ? .nearbyObject : .stopTag
        // A statement of absence carries no counts or attributes.
        if status == .absent { return StopFacility(kind: kind, status: status, source: source) }
        switch kind {
        case .elevator:
            let n = field(word, "elevator_n")
            return StopFacility(kind: kind, status: status, count: n.value, countIsAtLeast: n.capped, source: source)
        case .ticketMachine:
            let n = field(word, "ticket_n")
            return StopFacility(kind: kind, status: status, count: n.value, countIsAtLeast: n.capped, source: source)
        case .toilets:
            let n = field(word, "toilets_n")
            return StopFacility(kind: kind, status: status, count: n.value, countIsAtLeast: n.capped, source: source,
                                toiletWheelchair: Self.toiletWheelchair(field(word, "toilets_wheelchair").value),
                                toiletFee: Self.yesNo(field(word, "toilets_fee").value))
        case .bicycleParking:
            let n = field(word, "bicycle_stands")
            return StopFacility(kind: kind, status: status, count: n.value, countIsAtLeast: n.capped,
                                covered: Self.yesNo(field(word, "bicycle_covered").value), source: source)
        case .shelter, .bench, .tactilePaving, .departuresBoard, .wheelchair:
            return StopFacility(kind: kind, status: status, source: source)
        }
    }

    /// Feature state → status. Code 11 is special for two features only; elsewhere it carries no statement.
    static func status(_ kind: FacilityKind, state: Int) -> FacilityStatus {
        switch state {
        case 2: return .present
        case 1: return .absent
        case 3:
            switch kind {
            case .wheelchair: return .limited
            case .departuresBoard: return .realtime
            default: return .notRecorded
            }
        default: return .notRecorded
        }
    }

    /// 2-bit code: 00 not recorded, 01 no, 10 yes.
    static func yesNo(_ code: Int) -> Bool? {
        switch code {
        case 2: return true
        case 1: return false
        default: return nil
        }
    }

    /// Toilet wheelchair code: 00 not recorded, 01 no, 10 yes, 11 limited.
    static func toiletWheelchair(_ code: Int) -> FacilityStatus? {
        switch code {
        case 2: return .present
        case 3: return .limited
        case 1: return .absent
        default: return nil
        }
    }

    /// `[offset, width]` from META, validated: non-negative, width ≥ 1 and inside the 64 bits.
    private static func range(_ any: Any?) -> (offset: Int, width: Int)? {
        guard let a = any as? [Any], a.count == 2, let offset = a[0] as? Int, let width = a[1] as? Int,
              offset >= 0, width >= 1, offset + width <= 64
        else { return nil }
        return (offset, width)
    }
}
