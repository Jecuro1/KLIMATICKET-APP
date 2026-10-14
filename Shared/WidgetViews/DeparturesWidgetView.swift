import SwiftUI
import WidgetKit
import KlimaCore

/// "Abfahrten": the next departures of one station from the app's cache. systemMedium (five), systemLarge (eight, with the
/// station's equipment), and the lock-screen rectangular family (the next two).
struct DeparturesWidgetView: View {
    /// The station's name; nil while none is available.
    var stationName: String?
    var facilities: [WidgetFacility] = []
    var state: WidgetLiveState
    var items: [WidgetDeparture]
    var family: WidgetFamily
    var margins: EdgeInsets = WidLayout.defaultMargins

    var body: some View {
        if stationName == nil {
            WidLiveEmpty(status: state, family: family, choice: "Station wählen")
        } else if !state.hasTimes {
            WidLiveEmpty(status: state, family: family)
        } else if items.isEmpty {
            WidLiveEmpty(status: state, family: family,
                         message: ("Keine Abfahrt mehr", "App öffnen für die nächsten Abfahrten"))
        } else {
            content
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemLarge:
            large
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(verbatim: "\(stationName ?? "") · \(inlineText)")
                .lineLimit(1)
        default:
            medium
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            WidEyebrow(text: "Abfahrten", symbol: "signpost.right.fill")
            Spacer(minLength: 4)
            Text(verbatim: stationName ?? "")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            ForEach(items.prefix(dynamicTypeSize.isAccessibilitySize ? 3 : 5)) { departure in
                WidDepartureLine(time: departure.departureTime, delay: departure.delayMinutes,
                                 lineName: departure.lineName, modeSymbol: departure.modeSymbol,
                                 destination: departure.direction, platform: departure.platform,
                                 platformChanged: departure.platformChanged, isCancelled: departure.isCancelled,
                                 showsDelay: state.showsDelays)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WidStandLine(status: state)
                Spacer(minLength: 0)
                WidSourceLine()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if !facilities.isEmpty {
                facilityRow
            }
            ForEach(items.prefix(8)) { departure in
                WidDepartureLine(time: departure.departureTime, delay: departure.delayMinutes,
                                 lineName: departure.lineName, modeSymbol: departure.modeSymbol,
                                 destination: departure.direction, platform: departure.platform,
                                 platformChanged: departure.platformChanged, isCancelled: departure.isCancelled,
                                 showsDelay: state.showsDelays)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WidStandLine(status: state)
                Spacer(minLength: 0)
                WidSourceLine()
            }
            // The equipment comes from OpenStreetMap, which needs its credit where it is shown (ODbL).
            if !facilities.isEmpty {
                WidSourceLine(text: "Ausstattung: © OpenStreetMap-Mitwirkende, ODbL")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The station's equipment in one row: with words when they fit, else symbols only (the words stay for VoiceOver).
    private var facilityRow: some View {
        ViewThatFits(in: .horizontal) {
            facilityItems(iconOnly: false)
            facilityItems(iconOnly: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func facilityItems(iconOnly: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(facilities, id: \.self) { facility in
                if iconOnly {
                    Image(systemName: WidStationFacility.symbol(facility))
                        .accessibilityLabel(WidStationFacility.label(facility))
                } else {
                    Label(WidStationFacility.label(facility), systemImage: WidStationFacility.symbol(facility))
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.widSecondary)
        .lineLimit(1)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: stationName ?? "Abfahrten")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .widgetAccentable()
            ForEach(items.prefix(2)) { departure in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: WidFormat.clock(departure.departureTime))
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .strikethrough(departure.isCancelled)
                    if state.showsDelays, let delay = WidFormat.delay(departure.delayMinutes) {
                        Text(verbatim: delay)
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(verbatim: departure.isCancelled ? "\(departure.lineName) fällt aus" : departure.lineName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var inlineText: String {
        guard let next = items.first else { return "Keine Abfahrt" }
        let delay = state.showsDelays ? WidFormat.delay(next.delayMinutes).map { " \($0)" } ?? "" : ""
        return "\(WidFormat.clock(next.departureTime))\(delay) \(next.lineName)"
    }
}

/// Labels and symbols of the station equipment the data delivers (Bike+Ride, Park+Ride, barrier-free access).
enum WidStationFacility {
    static func label(_ facility: WidgetFacility) -> String {
        switch facility {
        case .bikeRide: "B+R"
        case .parkRide: "P+R"
        case .barrierFree: "barrierefrei"
        case .barrierFreePartial: "teilweise barrierefrei"
        case .elevator: "Aufzug"
        case .toilets: "WC"
        case .bicycleParking: "Fahrradständer"
        }
    }

    static func symbol(_ facility: WidgetFacility) -> String {
        switch facility {
        case .bikeRide, .bicycleParking: "bicycle"
        case .parkRide: "car.fill"
        case .barrierFree, .barrierFreePartial: "figure.roll"
        case .elevator: "arrow.up.arrow.down.square"
        case .toilets: "toilet"
        }
    }
}
