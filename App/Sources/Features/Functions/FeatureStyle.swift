import SwiftUI
import KlimaCore

// MARK: funktionen – how the hub draws a feature: symbol, group colour, the colour of its state (Theme tokens only; small text
// uses the text-safe variants).

extension FeatureID {
    var symbol: String {
        switch self {
        case .liveTimetable: "tram.fill"
        case .livePrices: "eurosign.circle.fill"
        case .followNotices: "bell.and.waves.left.and.right.fill"
        case .radar: "dot.radiowaves.left.and.right"
        case .trainSearch: "magnifyingglass"
        case .disruptions: "exclamationmark.triangle.fill"
        case .tripDetection: "location.circle.fill"
        case .assistant: "sparkles"
        case .perksCard: "gift.fill"
        case .achievementsTeaser: "book.closed.fill"
        case .weekInsight: "calendar"
        case .renewalReminders: "bell.badge.fill"
        case .weeklySummary: "calendar.badge.clock"
        case .haptics: "iphone.radiowaves.left.and.right"
        case .officialLogos: "mountain.2.fill"
        }
    }

    var tint: Color { descriptor.group.tint }
}

extension FeatureGroup {
    var tint: Color {
        switch self {
        case .liveData: Theme.glacier
        case .mapRadar: Theme.dusk
        case .capture: Theme.pine
        case .overview: Theme.dawn
        case .notices: Theme.gold
        case .appearance: Theme.alpenglow
        }
    }

    var symbol: String {
        switch self {
        case .liveData: "antenna.radiowaves.left.and.right"
        case .mapRadar: "map.fill"
        case .capture: "plus.circle.fill"
        case .overview: "mountain.2.fill"
        case .notices: "bell.fill"
        case .appearance: "paintpalette.fill"
        }
    }
}

extension FeatureRecipient {
    var symbol: String {
        switch self {
        case .oebbTimetable: "tram.fill"
        case .oebbShop: "ticket.fill"
        case .vao: "bus.fill"
        case .cloud: "icloud.fill"
        case .github: "arrow.down.circle.fill"
        case .appleMaps: "map.fill"
        case .device: "iphone"
        }
    }

    var tint: Color {
        switch self {
        case .oebbTimetable: Theme.glacier
        case .oebbShop: Theme.dawn
        case .vao: Theme.modeColor(.bus)
        case .cloud: Theme.dusk
        case .github: Theme.pine
        case .appleMaps: Theme.modeColor(.sBahn)
        case .device: Theme.pine
        }
    }
}

/// The colour of a status line (text-safe).
enum FeatureStatusTone {
    case on, waiting, hidden, off

    init(_ status: FeatureStatus) {
        if status.isOn {
            self = status.waiting == nil ? .on : .waiting
        } else {
            self = status.offReason == .switchedOff ? .off : .hidden
        }
    }

    var color: Color {
        switch self {
        case .on: Theme.positiveText
        case .waiting, .hidden: Theme.summitText
        case .off: Theme.textSecondary
        }
    }

    var symbol: String {
        switch self {
        case .on: "checkmark.circle.fill"
        case .waiting: "clock.fill"
        case .hidden: "eye.slash.fill"
        case .off: "circle.slash"
        }
    }
}
