import Foundation

// MARK: radarmodes – the one matcher of the radar filter (README radar2 F9: the live pins and the Zeitreise's pins used two), its line keys, and its
// storage `radar.filter.v1` (versioned JSON, tolerant: unknown keys and values are dropped, garbage is an empty filter; the v1 `categories` of the
// first radar become Zugarten where they are one).

public extension RadarFilter {
    /// Every criterion, for a vehicle whose delay state is known (live: `RadarDelay.state`; Zeitreise: the pin's state at its time).
    func matches(_ vehicle: RadarVehicle, delay: RadarDelayState) -> Bool {
        if !categories.isEmpty, !categories.contains(RadarLine.category(of: vehicle.line)) { return false }
        if !trainClasses.isEmpty, let kind = RadarTrainClass.of(vehicle.line), !trainClasses.contains(kind) { return false }
        if !lines.isEmpty, !RadarLine.matches(vehicle.line, any: lines) { return false }
        if !operators.isEmpty, !operators.contains(RadarOperator.name(of: vehicle.line)) { return false }
        if !delays.isEmpty, !delays.contains(delay) { return false }
        if onlyLate, delay != .late { return false }
        if onlyRealtime, delay == .unknown { return false }
        if let state, AustrianState.guess(for: vehicle) != state { return false }
        return true
    }

    /// What is active, for the row on the map: „RJX, RJ · 13A · nur verspätet“.
    var summary: String {
        var parts: [String] = []
        if !trainClasses.isEmpty { parts.append(RadarTrainClass.allCases.filter(trainClasses.contains).map(\.title).joined(separator: ", ")) }
        if !categories.isEmpty { parts.append(categories.sorted().joined(separator: ", ")) }
        if !lines.isEmpty { parts.append(lines.sorted(by: LinePlateOrder.naturalLess).joined(separator: ", ")) }
        if !operators.isEmpty { parts.append(operators.sorted().joined(separator: ", ")) }
        if onlyLate { parts.append("nur verspätet") }
        let states = RadarDelayState.allCases.filter(delays.contains).map { state -> String in
            switch state {
            case .onTime: "pünktlich"
            case .late: "verspätet"
            case .cancelled: "fällt aus"
            case .unknown: "ohne Echtzeit"
            }
        }
        if !states.isEmpty { parts.append(states.joined(separator: ", ")) }
        if onlyRealtime { parts.append("mit Echtzeit") }
        if let state { parts.append(state.title) }
        return parts.joined(separator: " · ")
    }

    // MARK: Storage

    static let storageKey = "radar.filter.v1"

    /// The JSON of `radar.filter.v1` (version 2).
    var storageValue: String {
        var object: [String: Any] = ["version": 2]
        if !trainClasses.isEmpty { object["trainClasses"] = trainClasses.map(\.rawValue).sorted() }
        if !lines.isEmpty { object["lines"] = lines.sorted() }
        if !operators.isEmpty { object["operators"] = operators.sorted() }
        if !delays.isEmpty { object["delays"] = delays.map(\.rawValue).sorted() }
        if onlyLate { object["onlyLate"] = true }
        if onlyRealtime { object["onlyRealtime"] = true }
        if let state { object["state"] = state.rawValue }
        if !categories.isEmpty { object["categories"] = categories.sorted() }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// From the stored JSON: unknown keys and values are dropped, anything unreadable is the empty filter. A v1 filter's `categories` that are a
    /// Zugart become one (the old sheet's „RJX“ is the new chip „RJX“); bus categories are dropped (a mode chip covers them now).
    init(storage: String) {
        self.init()
        guard let data = storage.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        func strings(_ key: String) -> [String] { (object[key] as? [Any])?.compactMap { $0 as? String } ?? [] }
        let version = object["version"] as? Int ?? 1
        trainClasses = Set(strings("trainClasses").compactMap(RadarTrainClass.init(rawValue:)))
        lines = Set(strings("lines").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        operators = Set(strings("operators").filter { !$0.isEmpty })
        delays = Set(strings("delays").compactMap(RadarDelayState.init(rawValue:)))
        onlyLate = object["onlyLate"] as? Bool ?? false
        onlyRealtime = object["onlyRealtime"] as? Bool ?? false
        state = (object["state"] as? String).flatMap(AustrianState.init(rawValue:))
        if onlyLate { delays = [] }   // „Nur verspätet“ replaces the delay states
        let old = strings("categories")
        if version < 2 {
            for category in old {
                let kind = RadarTrainClass.of(category: category)
                if kind != .other { trainClasses.insert(kind) }
            }
        } else {
            categories = Set(old.filter { !$0.isEmpty })
        }
    }
}

public extension RadarLine {
    /// The forms a line can be typed in, without spaces, upper case: title, name, number, plate („BUS13A“, „13A“; „U6“; „S45“; „RJX66“, „RJX“).
    static func keys(of line: Line) -> Set<String> {
        var keys: Set<String> = [compact(LinePresentation.title(line)), compact(line.name), compact(LinePresentation.plate(line))]
        if let number = line.lineNumber { keys.insert(compact(number)) }
        if let fullName = line.fullName { keys.insert(compact(fullName)) }
        keys.remove("")
        return keys
    }

    /// The line is one of `entries` (typed or chosen, compared without spaces and case).
    static func matches(_ line: Line?, any entries: Set<String>) -> Bool {
        guard let line else { return false }
        let keys = keys(of: line)
        return entries.contains { keys.contains(compact($0)) }
    }
}
