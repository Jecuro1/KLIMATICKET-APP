import Foundation
import WidgetKit
import KlimaCore

/// MARK: smartwidgets – the two lock-screen privacy switches of the widget gallery (docs/WIDGETS_SMARTSTACK.md §1):
/// "Strecken auf dem Sperrbildschirm verbergen" (on by default) and "Beträge verbergen" (off by default).
///
/// The choice is stored under `widgets.privacy.v1` in the App Group (so it also reaches the live widgets of a user without
/// a ticket) and copied into the ticket snapshot (`WidgetSnapshot.hidesRoutesWhenLocked` / `hidesAmountsWhenLocked`).
/// A change reloads every widget once – it touches all of them – and costs no network. Screenshot and perf runs keep the
/// choice in memory only.
@MainActor
enum WidgetPrivacyStore {
    /// The choice of screenshot and perf runs (they never write the App Group).
    private static var sandboxed: WidgetPrivacy?

    /// The switches as the gallery shows them (the defaults until the user changes one).
    static var current: WidgetPrivacy {
        if LaunchMode.isSandboxed { return (sandboxed ?? .standard).resolved }
        return WidgetPrivacy.current().resolved
    }

    /// What the snapshot builder copies into the snapshot: only what the user has set (nil fields read as the defaults).
    static var stored: WidgetPrivacy {
        LaunchMode.isSandboxed ? (sandboxed ?? .standard) : (WidgetCache.privacy ?? .standard)
    }

    /// Stores a changed choice, copies it into the stored snapshot and reloads the widgets. No-op when nothing changed.
    static func set(_ privacy: WidgetPrivacy) {
        let value = privacy.resolved
        if LaunchMode.isSandboxed {
            sandboxed = value
            return
        }
        guard WidgetCache.setPrivacy(value) else { return }
        if var snapshot = WidgetSnapshot.load(),
           snapshot.hidesRoutesWhenLocked != value.hidesRoutesWhenLocked
            || snapshot.hidesAmountsWhenLocked != value.hidesAmountsWhenLocked {
            snapshot.hidesRoutesWhenLocked = value.hidesRoutesWhenLocked
            snapshot.hidesAmountsWhenLocked = value.hidesAmountsWhenLocked
            snapshot.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
