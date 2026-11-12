import SwiftUI
import KlimaCore

// MARK: radarheat – CI screenshots of the Pünktlichkeit layer (`-KBScreenshot <name> -KBDemo YES`, RootView › ScreenshotRouter).
// Demo trains only (`RadarHeatDemo.swift`: a delay cluster over Tirol, a quiet rest of the country), no network.
//
//   radarHeat       the layer over Austria, the panel closed
//   radarHeatPanel  the panel open: legend, the largest delays, the hot spots, the notes
//   radarHeatCell   the map close to Tirol, the cell of the largest hot spot open with its trains
//   radarHeatAX5    the open panel at the largest text size
struct RadarHeatScreenshotHost: View {
    static let screens: Set<String> = ["radarHeat", "radarHeatPanel", "radarHeatCell", "radarHeatAX5"]

    let screen: String

    private var preset: RadarPreset {
        switch screen {
        case "radarHeatPanel": .heatPanel
        case "radarHeatCell": .heatCell
        case "radarHeatAX5": .heatAX5
        default: .heat
        }
    }

    var body: some View {
        RadarView(preset: preset)
            .dynamicTypeSize(screen == "radarHeatAX5" ? .accessibility5 : .large)
    }
}
