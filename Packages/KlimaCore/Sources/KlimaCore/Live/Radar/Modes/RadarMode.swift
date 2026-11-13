import Foundation

// MARK: radarmodes – the transport modes of the Zug-Radar (docs/RADAR_MODES.md §2). Each chip is a set of HAFAS product classes the radar asks
// for. Until radar2 the chip „Züge“ asked for `.rail` (4157), which contains the S-Bahn (32): S-Bahnen were on the map whether the S-Bahn chip
// was on or off. Now „Züge“ is every train without the S-Bahn (4125) and „S-Bahn“ is 32; the default selection {Züge, S-Bahn} asks for the
// same 4157 as before.

public enum RadarMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    case rail, suburban, bus, tram, subway

    public var id: Self { self }

    /// The chip title.
    public var title: String {
        switch self {
        case .rail: "Züge"
        case .suburban: "S-Bahn"
        case .bus: "Bus"
        case .tram: "Bim"
        case .subway: "U-Bahn"
        }
    }

    /// The product classes this mode asks for. `rail` = high speed, IC/EC, night, regional, WESTbahn (4125): every train but the S-Bahn.
    public var products: ProductMask {
        switch self {
        case .rail: RadarMode.trainClasses
        case .suburban: .suburban
        case .bus: .bus
        case .tram: .tram
        case .subway: .subway
        }
    }

    /// 1|4|8|16|4096 = 4125.
    public static let trainClasses: ProductMask = [.highSpeed, .intercity, .night, .regional, .westbahn]

    /// The modes whose vehicles are counted in the hundreds in a city: they are asked by the radar's city lane, only while the map is zoomed in
    /// (docs/RADAR_MODES.md §3).
    public var isCity: Bool { self == .bus || self == .tram || self == .subway }

    /// The app's transport mode (symbol, colour).
    public var transportMode: TransportMode {
        switch self {
        case .rail: .train
        case .suburban: .sBahn
        case .bus: .bus
        case .tram: .tram
        case .subway: .metro
        }
    }

    /// The mode of a vehicle, from its product class bit (`Line.productClass`), never from `Line.mode`: the codec maps rail replacement (2) and
    /// long-distance coaches (1024) to `.bus`, and they are no city bus. nil: none of the five („Andere“: class 0, SEV, coach, ship, …).
    public static func of(productClass: Int) -> RadarMode? {
        switch productClass {
        case 1, 4, 8, 16, 4096: .rail
        case 32: .suburban
        case 64: .bus
        case 512: .tram
        case 256: .subway
        default: nil
        }
    }

    /// The mode of a radar vehicle (nil: „Andere“, see `of(productClass:)`).
    public static func of(_ vehicle: RadarVehicle) -> RadarMode? {
        of(productClass: vehicle.line?.productClass ?? 0)
    }
}
