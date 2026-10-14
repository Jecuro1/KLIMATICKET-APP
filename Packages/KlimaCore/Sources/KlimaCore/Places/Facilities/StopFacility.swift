import Foundation

/// The facilities of a stop as OpenStreetMap records them (docs/ENRICH_SPEC.md §1.11, EQUI section of stops_osm.bin).
/// The model says what OSM records and nothing more: `.notRecorded` means "keine Angabe", never "fehlt".
public enum FacilityKind: String, CaseIterable, Sendable {
    case elevator, toilets, bicycleParking, ticketMachine, shelter, bench, tactilePaving, departuresBoard, wheelchair

    /// Feature name in META.equipment.features. Readers resolve slots by this name, never by position.
    public var wireName: String {
        switch self {
        case .elevator: "elevator"
        case .toilets: "toilets"
        case .bicycleParking: "bicycle_parking"
        case .ticketMachine: "ticket_machine"
        case .shelter: "shelter"
        case .bench: "bench"
        case .tactilePaving: "tactile_paving"
        case .departuresBoard: "departures_board"
        case .wheelchair: "wheelchair"
        }
    }

    public init?(wireName: String) {
        guard let kind = Self.allCases.first(where: { $0.wireName == wireName }) else { return nil }
        self = kind
    }
}

/// What OSM says about a facility.
public enum FacilityStatus: String, Sendable {
    /// OSM says it is there (`yes`, or `wheelchair=yes` for barrier-free access).
    case present
    /// Only partly accessible (`wheelchair=limited`).
    case limited
    /// Departure board with real-time data (`departures_board=realtime`).
    case realtime
    /// OSM says explicitly that it is not there (`=no`).
    case absent
    /// OSM says nothing about it. Never shown as "fehlt".
    case notRecorded
}

/// Where the statement comes from.
public enum FacilitySource: String, Sendable {
    /// A tag on the stop's own public-transport node or platform.
    case stopTag
    /// An object within 40 m of such a node or platform (EQUIP radius, ENRICH_SPEC §1.11).
    case nearbyObject
}

/// One facility of one stop. `count` is the number of objects (elevators, toilets, ticket machines) or the bicycle
/// stands (sum of `capacity`, else one per object); 0 when not counted.
public struct StopFacility: Equatable, Sendable {
    public let kind: FacilityKind
    public let status: FacilityStatus
    public let count: Int
    /// The count reached the stored maximum (15 objects, 255 stands): the real number is at least this.
    public let countIsAtLeast: Bool
    /// Bicycle parking: `true` if OSM marks any stand as covered, `false` if it marks only uncovered ones,
    /// `nil` if OSM says nothing.
    public let covered: Bool?
    /// Where the statement comes from; `nil` exactly when the status is `.notRecorded`.
    public let source: FacilitySource?
    /// Toilets: wheelchair access of the toilet (`nil` = not recorded).
    public let toiletWheelchair: FacilityStatus?
    /// Toilets: `true` for a fee, `false` for no fee, `nil` = not recorded.
    public let toiletFee: Bool?

    public init(kind: FacilityKind, status: FacilityStatus, count: Int = 0, countIsAtLeast: Bool = false,
                covered: Bool? = nil, source: FacilitySource? = nil, toiletWheelchair: FacilityStatus? = nil,
                toiletFee: Bool? = nil) {
        self.kind = kind
        self.status = status
        self.count = count
        self.countIsAtLeast = countIsAtLeast
        self.covered = covered
        self.source = status == .notRecorded ? nil : source
        self.toiletWheelchair = toiletWheelchair
        self.toiletFee = toiletFee
    }

    /// Positive statement: OSM says the facility is there (also partly or in real time).
    public var isPresent: Bool {
        status == .present || status == .limited || status == .realtime
    }

    public var isRecorded: Bool { status != .notRecorded }
}
