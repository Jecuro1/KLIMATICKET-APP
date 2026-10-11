import KlimaCore
import SwiftUI

/// Push route of a stop inside an existing `NavigationStack`.
struct StopRoute: Hashable, Identifiable {
    let placeID: String
    var id: String { placeID }
}

extension View {
    /// Opens the stop detail as a large sheet while `placeID` is set. No edit of `RootView` needed: any screen can attach it.
    func stopDetail(placeID: Binding<String?>) -> some View {
        sheet(item: Binding(get: { placeID.wrappedValue.map(StopRoute.init) }, set: { placeID.wrappedValue = $0?.placeID })) { route in
            NavigationStack {
                StopDetailView(placeID: route.placeID)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }
}
