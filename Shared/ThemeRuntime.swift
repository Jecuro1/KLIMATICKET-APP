import SwiftUI
import KlimaCore

// MARK: themes – which palette `Theme.accent` and its five related tokens read (docs/THEMES.md §2). App and widgets.
//
// Every palette is built once (`ThemeColorSet`) and kept: reading a token hands out the cached instance, so two reads compare
// equal and nothing re-renders because of a fresh Color. The app switches the palette in one place – when the Settings sheet
// closes – and re-identifies the tab interface, so every screen reads the new set (RootView, `app.themeRevision`).

enum ThemeRuntime {
    /// The palette the tokens read right now.
    static var active: ThemePaletteID { storage.withLock { $0.active.palette } }

    /// The colour set of the active palette.
    static var colors: ThemeColorSet { storage.withLock { $0.active } }

    /// The colour set of any palette (the previews in Look & Feel), built once.
    static func colors(for id: ThemePaletteID) -> ThemeColorSet {
        storage.withLock { $0.set(for: id) }
    }

    /// Makes `id` the palette every token reads. Returns whether it changed (the caller then re-renders its screens).
    @discardableResult
    static func activate(_ id: ThemePaletteID) -> Bool {
        storage.withLock { state in
            guard state.active.palette != id else { return false }
            state.active = state.set(for: id)
            return true
        }
    }

    // MARK: Storage

    /// Mutable state behind a lock: the widget extension and background renderers may read tokens off the main thread.
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var state: State

        init(_ state: State) { self.state = state }

        func withLock<T>(_ body: (inout State) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }
    }

    private struct State {
        var active: ThemeColorSet
        var built: [ThemePaletteID: ThemeColorSet]

        mutating func set(for id: ThemePaletteID) -> ThemeColorSet {
            if let set = built[id] { return set }
            let set = ThemeColorSet(ThemeCatalog.palette(id))
            built[id] = set
            return set
        }
    }

    private static let storage: Storage = {
        var state = State(active: ThemeColorSet(ThemeCatalog.palette(.standard)), built: [:])
        state.built[.standard] = state.active
        return Storage(state)
    }()
}
