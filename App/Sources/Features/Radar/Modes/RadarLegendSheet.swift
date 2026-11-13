import SwiftUI
import KlimaCore

// MARK: radarmodes – „Legende“: what the markers of the radar mean (docs/RADAR_MODES.md §5). The same plates as on the map (`RadarModePlate`), the
// rings, the dashed estimate, the arrow and the group bubble; one VoiceOver element per row; the footer says where the positions come from.

struct RadarLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RadarMode.allCases) { mode in
                        row(text: RadarModesText.legendLabel(mode), spoken: RadarModesText.legendSpoken(mode)) {
                            RadarModePlate(badge: .radar(RadarLegendSamples.line(mode), size: .s), delay: .onTime, isEstimate: false)
                        }
                    }
                } header: {
                    Text("Verkehrsmittel")
                } footer: {
                    Text(RadarModesText.legendModesFooter)
                }

                Section {
                    ForEach(RadarLegendSamples.rings, id: \.text) { sample in
                        row(text: sample.text, spoken: sample.text) {
                            RadarModePlate(badge: .radar(RadarLegendSamples.line(.bus), size: .s), delay: sample.delay,
                                           isEstimate: sample.estimate)
                        }
                    }
                } header: {
                    Text("Ring")
                }

                Section {
                    row(text: RadarModesText.legendArrow, spoken: RadarModesText.legendArrow) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RadarMode.bus.color)
                            .rotationEffect(.degrees(45))
                    }
                    row(text: RadarModesText.legendGroup, spoken: RadarModesText.legendGroup) {
                        Text("12")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(Theme.accent, in: .circle)
                            .overlay(Circle().strokeBorder(Theme.positive, lineWidth: 3))
                    }
                } header: {
                    Text("Zeichen")
                } footer: {
                    Text(RadarModesText.legendFooter)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sheetBackground)
            .navigationTitle(RadarModesText.legendTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    /// One legend row: the sample on the left in a fixed column, the words on the right; one VoiceOver element.
    private func row<Sample: View>(text: String, spoken: String, @ViewBuilder sample: () -> Sample) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                sample().frame(minWidth: 64)
                Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                sample()
                Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// Invented sample lines of the legend: the plates come out of the same code as on the map.
enum RadarLegendSamples {
    static func line(_ mode: RadarMode) -> Line {
        switch mode {
        case .rail: DemoScotty.rjx("RJX 66", number: "66")
        case .suburban: DemoScotty.suburban("S 45", number: "45")
        case .bus: RadarCityDemoFleet.line("13A", cls: 64, seed: 0)
        case .tram: RadarCityDemoFleet.line("D", cls: 512, seed: 0)
        case .subway: RadarCityDemoFleet.line("U6", cls: 256, seed: 0)
        }
    }

    struct Ring {
        var text: String
        var delay: RadarDelayState
        var estimate = false
    }

    static let rings: [Ring] = [
        Ring(text: RadarModesText.legendOnTime, delay: .onTime),
        Ring(text: RadarModesText.legendLate, delay: .late),
        Ring(text: RadarModesText.legendCancelled, delay: .cancelled),
        Ring(text: RadarModesText.legendUnknown, delay: .unknown),
        Ring(text: RadarModesText.legendEstimate, delay: .onTime, estimate: true),
    ]
}
