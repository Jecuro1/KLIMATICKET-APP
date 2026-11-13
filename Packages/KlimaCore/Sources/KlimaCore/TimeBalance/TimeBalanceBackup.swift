import Foundation

/// The time fields of a trip in the JSON backup (docs/TIME_BALANCE.md §5). They stay on the device – the sync rows do
/// not carry them – so the backup writes them as optional keys next to the trip row's own keys. A file without them
/// (every backup before the Zeitbilanz) restores with the model defaults for new trips and leaves existing trips as they
/// are; a value of the wrong type or out of range is dropped instead of failing the restore.
public struct TripTimeBackupFields: Codable, Hashable, Sendable {
    /// One direction, minutes (0 = unknown).
    public var durationMinutes: Int?
    /// Arrival delay, minutes (never negative).
    public var delayMinutes: Int?
    /// `TripDelaySource` raw value, "" = not recorded.
    public var delaySource: String?
    /// Arrival the planner or „Fahrten erkennen“ stored – the ride time of those trips is derived from it.
    public var arrivalAt: Date?

    enum CodingKeys: String, CodingKey {
        case durationMinutes = "duration_minutes"
        case delayMinutes = "delay_minutes"
        case delaySource = "delay_source"
        case arrivalAt = "arrival_at"
    }

    public init(durationMinutes: Int? = nil, delayMinutes: Int? = nil, delaySource: String? = nil, arrivalAt: Date? = nil) {
        self.durationMinutes = durationMinutes.map(Self.sanitizedDuration)
        self.delayMinutes = delayMinutes.map { max(0, $0) }
        self.delaySource = delaySource.map(Self.sanitizedSource)
        self.arrivalAt = arrivalAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` flattens: a missing key and a value that does not decode are both nil.
        self.init(durationMinutes: try? c.decodeIfPresent(Int.self, forKey: .durationMinutes),
                  delayMinutes: try? c.decodeIfPresent(Int.self, forKey: .delayMinutes),
                  delaySource: try? c.decodeIfPresent(String.self, forKey: .delaySource),
                  arrivalAt: try? c.decodeIfPresent(Date.self, forKey: .arrivalAt))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(delayMinutes, forKey: .delayMinutes)
        try c.encodeIfPresent(delaySource, forKey: .delaySource)
        try c.encodeIfPresent(arrivalAt, forKey: .arrivalAt)
    }

    /// No key at all (an older backup).
    public var isEmpty: Bool { durationMinutes == nil && delayMinutes == nil && delaySource == nil && arrivalAt == nil }

    /// 0 for anything the resolver would not accept as an entered duration.
    public static func sanitizedDuration(_ minutes: Int) -> Int {
        TravelTimeResolver.enteredMinutes(minutes) == nil ? 0 : minutes
    }

    /// "" for anything that is not a known source.
    public static func sanitizedSource(_ raw: String) -> String {
        TripDelaySource(storedValue: raw)?.rawValue ?? ""
    }
}

/// A backup trip row with the time fields beside its own keys (one flat JSON object). `Base` is the sync row.
public struct TripTimeBackupRow<Base: Codable>: Codable {
    public var base: Base
    public var times: TripTimeBackupFields

    public init(_ base: Base, times: TripTimeBackupFields) {
        self.base = base
        self.times = times
    }

    public init(from decoder: Decoder) throws {
        base = try Base(from: decoder)
        times = try TripTimeBackupFields(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        try times.encode(to: encoder)
    }
}

extension TripTimeBackupRow: Sendable where Base: Sendable {}
extension TripTimeBackupRow: Equatable where Base: Equatable {}
