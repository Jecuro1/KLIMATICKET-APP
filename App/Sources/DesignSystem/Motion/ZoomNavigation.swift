import SwiftUI

/// Zoom navigation (docs/MOTION.md §9): a detail grows out of the card or row that opened it and shrinks back into
/// it on the way back (interactive, the system zoom transition). Three steps:
///
///     NavigationStack { TripsList() }
///         .zoomTransitionScope()                         // 1. one namespace for the stack and its sheets
///
///     NavigationLink(value: trip) { TripRow(trip: trip) }
///         .zoomSource(id: trip.id, cornerRadius: 20)     // 2. the card/row the detail zooms out of
///
///     .navigationDestination(for: TripEntity.self) { trip in
///         TripDetailView(trip: trip).zoomDestination(id: trip.id)   // 3. the pushed (or presented) view
///     }
///
/// Without a scope both modifiers do nothing, so a component can offer zooming without requiring it.
/// Reduce Motion: the system's standard push / sheet transition.
extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID? = nil
}

extension View {
    /// Provides the namespace that `zoomSource` / `zoomDestination` share. Put it on the `NavigationStack` (outside, so
    /// pushed views and sheets inherit it) or on the view that presents a sheet / full-screen cover.
    func zoomTransitionScope() -> some View {
        modifier(ZoomScopeModifier())
    }

    /// The view a detail zooms out of. `cornerRadius` matches the source's shape so the zoom starts from it exactly.
    func zoomSource<ID: Hashable>(id: ID, cornerRadius: CGFloat = Theme.Radius.card, in namespace: Namespace.ID? = nil) -> some View {
        modifier(ZoomSourceModifier(id: id, cornerRadius: cornerRadius, explicitNamespace: namespace))
    }

    /// On the root of the pushed or presented view: zooms out of the `zoomSource` with the same `id`.
    func zoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID? = nil) -> some View {
        modifier(ZoomDestinationModifier(id: id, explicitNamespace: namespace))
    }
}

private struct ZoomScopeModifier: ViewModifier {
    @Namespace private var namespace

    func body(content: Content) -> some View {
        content.environment(\.zoomNamespace, namespace)
    }
}

private struct ZoomSourceModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let cornerRadius: CGFloat
    let explicitNamespace: Namespace.ID?
    @Environment(\.zoomNamespace) private var scopeNamespace

    func body(content: Content) -> some View {
        if let namespace = explicitNamespace ?? scopeNamespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct ZoomDestinationModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let explicitNamespace: Namespace.ID?
    @Environment(\.zoomNamespace) private var scopeNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let namespace = explicitNamespace ?? scopeNamespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
