import SwiftUI
import WidgetKit
import KlimaCore

// MARK: tripdetect – "Aufzeichnung läuft": Lock Screen and Dynamic Island of a recording (Fahrt aufzeichnen). Shared by the widget
// extension (Widgets/Sources/RecordingLiveActivity.swift) and the app's CI scenes. Fixed point sizes like the other activities.

enum RecordingCopy {
    /// "12,4 km · 86 km/h"
    static func figures(_ state: RecordingActivityAttributes.ContentState) -> String {
        "\(WidFormat.number(state.distanceKm, decimals: state.distanceKm < 10 ? 1 : 0)) km · \(Int(state.speedKmh.rounded())) km/h"
    }

    /// "Am Bahnhof Feldkirch" / "Zuletzt Feldkirch" / "Suche Haltestelle …"
    static func station(_ state: RecordingActivityAttributes.ContentState) -> String {
        guard let name = state.stationName, !name.isEmpty else { return "Standort wird bestimmt" }
        return state.isAtStation ? "Bei \(name)" : "Zuletzt \(name)"
    }

    static func spoken(_ state: RecordingActivityAttributes.ContentState) -> String {
        if state.isStopped { return "Aufzeichnung gestoppt" }
        return "Aufzeichnung läuft. \(figures(state)). \(station(state))"
    }
}

struct RecordingLockScreenView: View {
    let attributes: RecordingActivityAttributes
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: state.isStopped ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(state.isStopped ? Theme.textSecondary : Theme.pine)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.isStopped ? "Aufzeichnung gestoppt" : "Aufzeichnung läuft")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                Text(timerInterval: attributes.timerRange, pauseTime: state.stoppedAt, countsDown: false)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(RecordingCopy.station(state))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(WidFormat.number(state.distanceKm, decimals: state.distanceKm < 10 ? 1 : 0))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("km").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Text("\(Int(state.speedKmh.rounded())) km/h").font(.caption).monospacedDigit().foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecordingCopy.spoken(state))
    }
}

struct RecordingIslandLeading: View {
    var body: some View {
        Image(systemName: "record.circle").font(.title3.weight(.semibold)).foregroundStyle(Theme.pine)
    }
}

struct RecordingIslandTimer: View {
    let attributes: RecordingActivityAttributes
    /// Set once the recording was stopped: the timer stands still there.
    var pausedAt: Date? = nil
    var body: some View {
        Text(timerInterval: attributes.timerRange, pauseTime: pausedAt, countsDown: false)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: 56)
    }
}

struct RecordingIslandBottom: View {
    let state: RecordingActivityAttributes.ContentState
    var body: some View {
        HStack {
            Text(RecordingCopy.station(state)).lineLimit(1)
            Spacer(minLength: 8)
            Text(RecordingCopy.figures(state)).monospacedDigit().lineLimit(1)
        }
        .font(.footnote.weight(.medium))
    }
}
