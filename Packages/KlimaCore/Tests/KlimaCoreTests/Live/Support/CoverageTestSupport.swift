// WP-C test helpers (coverage + presentation). Shared by Tests/KlimaCoreTests/Live/{Coverage,Presentation}.
import Foundation
import XCTest
@testable import KlimaCore

enum CoverageFixtures {
    /// FX/coverage/coverage_rules.json.
    static var rulesData: Data {
        get throws { try Fixture.data("coverage/coverage_rules") }
    }

    /// The bundled App/Resources/stations.json (1,487 stations) – the index the reference engine used for states.
    static let stations: StationIndex = {
        let url = PlaceFixtures.resources.appendingPathComponent("stations.json")
        do {
            return try StationIndex(jsonData: Data(contentsOf: url))
        } catch {
            fatalError("cannot load \(url.path): \(error)")
        }
    }()

    static let evaluator: CoverageEvaluator = {
        do {
            return try CoverageEvaluator(rulesJSON: Fixture.data("coverage/coverage_rules"), stations: stations)
        } catch {
            fatalError("cannot load coverage_rules.json: \(error)")
        }
    }()

    /// `FX/hafas/<scenario>.response` decoded with the WP-A codec.
    static func page(_ scenario: String) throws -> JourneyPage {
        try HafasCodec.journeyPage(from: Fixture.data("hafas/\(scenario).response"))
    }
}

/// Vienna wall-clock dates for tests ("2026-10-09 11:40").
enum Vienna {
    static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Vienna")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        guard let d = f.date(from: s) else { fatalError("bad test date \(s)") }
        return d
    }
}
