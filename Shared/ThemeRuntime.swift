import SwiftUI
import KlimaCore

// MARK: themes – which palette `Theme.accent` and its five related tokens read (docs/THEMES.md §2). App and widgets.
//
// Every palette is built once (`ThemeColorSet`) and kept: reading a token hands out the cached instance, so two reads compare
// equal and nothing re-renders because of a fresh Color. The app switches the palette in one place – when the Settings sheet
// closes (AppearanceStore) – and re-identifies the tab interface, so every screen reads the new set. Widgets and Live
// Activities draw in their own process and follow the stored choice (theme.v1 in the App Group) the next time they draw.

enum ThemeRuntime {
    /// The palette the tokens read right now.
    static var active: ThemePaletteID { storage.withLock { $0.active.palette } }

    /// The colour set of the active palette.
    static var colors: ThemeColorSet {
        if isExtension { followStoredChoice() }
        return storage.withLock { $0.active }
    }

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

    // MARK: Widgets

    /// The widget extension: no AppearanceStore runs there, so the palette comes from theme.v1.
    private static let isExtension = Bundle.main.bundleURL.pathExtension == "appex"

    /// Reads theme.v1 at most every two seconds: an extension process lives on between timeline reloads, so a palette changed
    /// in the app reaches the next render without a check on every token read.
    private static func followStoredChoice() {
        let now = Date()
        let isDue = storage.withLock { state -> Bool in
            guard now.timeIntervalSince(state.checkedStore) > 2 else { return false }
            state.checkedStore = now
            return true
        }
        guard isDue else { return }
        let stored = AppearancePrefs.decode(AppGroup.defaults.data(forKey: AppearancePrefs.storageKey))?.palette ?? .standard
        activate(stored)
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
        /// Last read of theme.v1 (widget extension only).
        var checkedStore: Date = .distantPast

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
