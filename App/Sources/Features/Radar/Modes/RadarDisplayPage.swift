import SwiftUI
import KlimaCore

// MARK: radarmodes – the page „Darstellung“ of „Filter & Darstellung“ (docs/RADAR_MODES.md §6): a live preview of three markers, labels, size, groups,
// arrow, the city refresh, then the sections of the other radar2 parts (`Radar2SettingsSections`, radartrail's „Spuren“).

struct RadarDisplayPage: View {
    @Binding var display: RadarDisplay
    var parts: Radar2Parts?

    var body: some View {
        Form {
            Section {
                RadarDisplayPreview(display: display)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text(RadarModesText.previewHeader)
            }

            Section {
                Picker(RadarModesText.labelHeader, selection: $display.label) {
                    ForEach(RadarDisplay.Label.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(RadarModesText.labelHeader)
            } footer: {
                Text(RadarModesText.labelFooter)
            }

            Section {
                Picker(RadarModesText.sizeHeader, selection: $display.size) {
                    ForEach(RadarDisplay.Size.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(RadarModesText.sizeHeader)
            }

            Section {
                Toggle(RadarModesText.groupsToggle, isOn: $display.groups)
            } footer: {
                Text(RadarModesText.groupsFooter)
            }

            Section {
                Toggle(RadarModesText.arrowsToggle, isOn: $display.arrows)
            }

            Section {
                Picker(RadarModesText.cityRefreshHeader, selection: $display.cityRefresh) {
                    ForEach(RadarDisplay.CityRefresh.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(RadarModesText.cityRefreshHeader)
            } footer: {
                Text(RadarModesText.cityRefreshFooter)
            }

            Radar2SettingsSections(parts: parts)   // MARK: radar2

            Section {
                Button(RadarModesText.resetDisplay, role: .destructive) {
                    withMotion(Motion.smooth) { display = .standard }
                }
                .disabled(display == .standard)
            }
        }
        .scrollContentBackground(.hidden)
        .haptic(.selection, trigger: display)
    }
}

/// Three markers on a tile of the surface, as the map would draw them with these options: a late bus, an S-Bahn on time, a Bim without realtime.
/// Each change glides (`Motion.smooth` through `motionAnimation`, which follows Reduce Motion).
struct RadarDisplayPreview: View {
    var display: RadarDisplay

    private struct Sample: Identifiable {
        var id: String
        var line: Line
        var delay: RadarDelayState
        var bearing: Double
        var destination: String
    }

    private let samples = [
        Sample(id: "bus", line: RadarCityDemoFleet.line("13A", cls: 64, seed: 0), delay: .late, bearing: 70, destination: "Hauptbahnhof"),
        Sample(id: "s", line: RadarLegendSamples.line(.suburban), delay: .onTime, bearing: 200, destination: "Hütteldorf"),
        Sample(id: "tram", line: RadarCityDemoFleet.line("D", cls: 512, seed: 0), delay: .unknown, bearing: 330, destination: "Nußdorf"),
    ]

    var body: some View {
        let style = RadarMarkerStyle(size: display.size, dots: display.label == .dots, arrows: display.arrows,
                                     destination: nil)
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            ForEach(samples) { sample in
                VStack(spacing: 1) {
                    if style.dots {
                        RadarModeDot(badge: .radar(sample.line, size: .xs), delay: sample.delay, isEstimate: false, height: style.dotHeight)
                    } else {
                        RadarModePlate(badge: .radar(sample.line, size: style.plateSize), delay: sample.delay, isEstimate: false, size: style.plateSize)
                        if display.label == .lineAndDestination { RadarDestinationLabel(text: sample.destination) }
                    }
                    if style.arrows {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.modeColor(sample.line.mode))
                            .rotationEffect(.degrees(sample.bearing))
                            .frame(height: 8)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.surface)
        .motionAnimation(Motion.smooth, value: display)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RadarModesText.previewHeader): \(display.label.title), \(display.size.title)")
    }
}
