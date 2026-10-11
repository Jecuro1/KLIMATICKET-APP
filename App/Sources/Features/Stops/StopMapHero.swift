import KlimaCore
import MapKit
import SwiftUI

/// Map header of the stop detail (ENRICH_SPEC §3.2): muted standard map, about 1,2 km across, the stop as a tile pin
/// with halo (Schneehaube in ski areas) and neighbours within 600 m as named dots.
struct StopMapHero: View {
    let place: Place
    let neighbours: [(place: Place, distanceMeters: Double)]
    var snowcap: Bool

    var body: some View {
        let center = place.coordinate.coordinate
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 1_200, longitudinalMeters: 1_200)),
            interactionModes: []) {
            ForEach(Array(neighbours.enumerated()), id: \.element.place.id) { i, n in
                Annotation(PlaceTitle.display(name: n.place.name, stateShown: true, state: n.place.state), coordinate: n.place.coordinate.coordinate, anchor: .center) {
                    Circle().fill(Theme.modeColor(n.place.products.primaryMode))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                }
                .annotationTitles(i < 2 ? .visible : .hidden)   // a few names, not a wall of text
            }
            Annotation(place.title, coordinate: center, anchor: .bottom) {
                StopPin(place: place, snowcap: snowcap)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .background(Theme.background)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The selected stop on the map: tile with a halo and a tail.
struct StopPin: View {
    let place: Place
    var snowcap: Bool
    var size: CGFloat = 40

    var body: some View {
        VStack(spacing: -3) {
            StopTile(mode: place.products.primaryMode, size: size, snowcap: snowcap)
                .padding(3)
                .background(.white, in: .rect(cornerRadius: size * 0.31 + 3, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
        }
    }
}
