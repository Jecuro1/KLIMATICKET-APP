import SwiftUI
import KlimaCore

// MARK: radarheat – CI screenshots of the Pünktlichkeit layer (`-KBScreenshot <name> -KBDemo YES`, RootView › ScreenshotRouter).
// Demo trains only (`RadarHeatDemo.swift`: a delay cluster over Tirol, a quiet rest of the country), no network.
//
//   radarHeat       the layer over Austria, the panel closed
//   radarHeatPanel  the panel open: legend, the largest delays, the hot spots, the notes
//   radarHeatLists  the open panel scrolled to the largest delays and the hot spots
//   radarHeatTrend  the open panel scrolled to the trend line of this session (made-up points: a real trend needs minutes)
//   radarHeatCell   the map close to Tirol, the cell of the largest hot spot open with its trains
//   radarHeatAX5    the open panel at the largest text size
//   radarHeatShare  the image "Pünktlichkeitskarte teilen" (`RadarHeatShareCard`, 360 × 500 pt) on the app's night blue
struct RadarHeatScreenshotHost: View {
    static let screens: Set<String> = ["radarHeat", "radarHeatPanel", "radarHeatLists", "radarHeatTrend", "radarHeatCell", "radarHeatAX5", "radarHeatShare"]

    let screen: String

    private var preset: RadarPreset {
        switch screen {
        case "radarHeatPanel": .heatPanel
        case "radarHeatLists": .heatLists
        case "radarHeatTrend": .heatTrend
        case "radarHeatCell": .heatCell
        case "radarHeatAX5": .heatAX5
        default: .heat
        }
    }

    var body: some View {
        if screen == "radarHeatShare" {
            shareCard
        } else {
            RadarView(preset: preset)
                .dynamicTypeSize(screen == "radarHeatAX5" ? .accessibility5 : .large)
        }
    }

    /// The share image as the share sheet would export it, from the demo trains (no network).
    private var shareCard: some View {
        let now = Date()
        let samples = HeatDemo.vehicles(now: now).map { HeatSample(vehicle: $0, coordinate: $0.coordinate, now: now) }
        let snapshot = RadarHeat.snapshot(samples)
        return ZStack {
            Color.black.ignoresSafeArea()
            RadarHeatShareCard(cells: HeatLayer.drawCells(from: snapshot), summary: snapshot.summary, date: now)
                .scaleEffect(1.05)
        }
    }
}
