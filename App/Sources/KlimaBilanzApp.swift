import SwiftUI
import KlimaCore

@main
struct KlimaBilanzApp: App {
    var body: some Scene {
        WindowGroup {
            InfraCheckView()
        }
    }
}

struct InfraCheckView: View {
    var body: some View {
        ZStack {
            MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                         colors: [.teal, .green, .blue, .indigo])
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("KlimaBilanz")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(FareEstimator.euro(FareModel.fallback.fare(railKm: 120)))
                    .font(.title.monospacedDigit())
            }
            .padding(32)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
        }
    }
}
