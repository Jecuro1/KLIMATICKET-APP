import Foundation

// MARK: radarmodes – how much the city lane downloads (docs/RADAR_MODES.md §4). An estimate, said as one: the answers of `/gate` are not compressed
// (docs/OEBB_LIVE.md §A2.1), a bus or tram entry is about 1.7 KB (Wien, §R11.1 c: 1 666 493 B for 1000; the radarmodes measurement of 2026-11-13:
// 1.6 to 2.2 KB), a train about 2 KB.

public enum RadarDataEstimate {
    public static let bytesPerCityEntry = 1700.0
    public static let bytesPerTrainEntry = 2000.0
    /// The radar says the volume from this many MB a minute on.
    public static let noteFromMegabytes = 2.0

    /// MB (10^6 bytes) a minute: the vehicles of the last answer of every visible city tile, once per `period` (the stretched period of the
    /// lane, `RadarLaneStatus.period`).
    public static func megabytesPerMinute(cityTileCounts: [Int], period: TimeInterval) -> Double {
        guard period.isFinite, period > 0 else { return 0 }
        let perRound = Double(cityTileCounts.reduce(0) { $0 + max($1, 0) }) * bytesPerCityEntry
        return perRound * 60 / period / 1_000_000
    }

    /// Whole MB for the note; nil below `noteFromMegabytes` (no note).
    public static func noteMegabytes(_ megabytes: Double) -> Int? {
        guard megabytes.isFinite, megabytes >= noteFromMegabytes else { return nil }
        return Int(megabytes.rounded())
    }

    /// The hard ceiling: the whole budget, every answer full (24 × 1000 × 1.7 KB ≈ 41 MB a minute).
    public static var ceilingMegabytesPerMinute: Double {
        Double(RadarSchedulerConfig.standard.perMinute) * Double(RadarTiling.requestCap) * bytesPerCityEntry / 1_000_000
    }
}
