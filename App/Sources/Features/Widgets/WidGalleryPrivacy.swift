import SwiftUI
import WidgetKit
import KlimaCore

// MARK: smartwidgets – "Gesperrt & privat" in the widget gallery (docs/WIDGETS_SMARTSTACK.md §1): the two switches and a
// lock screen that shows, with the widgets' own views, what stays visible while the iPhone is locked. The preview uses the
// same mechanism as the system: the marked texts are `privacySensitive`, and `.redacted(reason: .privacy)` draws the
// placeholders. A flip changes the preview at once and reloads the real widgets (WidgetPrivacyStore).

struct WidPrivacySection: View {
    let snapshot: WidgetSnapshot

    @State private var privacy: WidgetPrivacy
    /// The preview shows the locked device (where the switches act) until the user looks at the unlocked one.
    @State private var showsLocked = true
    @State private var changes = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `initialPrivacy`: CI scenes start from a given choice instead of the stored one.
    init(snapshot: WidgetSnapshot, initialPrivacy: WidgetPrivacy? = nil) {
        self.snapshot = snapshot
        _privacy = State(initialValue: (initialPrivacy ?? WidgetPrivacyStore.current).resolved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "Gesperrt & privat",
                          caption: "Was deine Widgets zeigen, solange dein iPhone gesperrt ist.")
            WidPrivacyStage(snapshot: snapshot, privacy: privacy, showsLocked: showsLocked)
                .padding(.horizontal, Theme.Spacing.cardGutter)
            lockPicker
                .padding(.horizontal, Theme.Spacing.cardGutter)
            switches
                .padding(.horizontal, Theme.Spacing.cardGutter)
            footnote
                .padding(.horizontal, Theme.Spacing.screen)
        }
        .haptic(.selection, trigger: changes)
    }

    // MARK: Controls

    private var lockPicker: some View {
        Picker("Vorschau", selection: lockedBinding) {
            Label("Gesperrt", systemImage: "lock.fill").tag(true)
            Label("Entsperrt", systemImage: "lock.open.fill").tag(false)
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Zeigt die Widgets gesperrt oder entsperrt")
    }

    private var lockedBinding: Binding<Bool> {
        Binding(get: { showsLocked }, set: { value in
            withMotion(Motion.smooth) { showsLocked = value }
        })
    }

    private var switches: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                switchRow(binding(\.hidesRoutesWhenLocked, default: WidgetPrivacy.defaultHidesRoutes),
                          title: "Strecken auf dem Sperrbildschirm verbergen",
                          detail: "Stationen, Ziele und die Namen deiner Fahrten erscheinen erst nach dem Entsperren.",
                          symbol: "point.topleft.down.to.point.bottomright.curvepath.fill")
                Divider()
                switchRow(binding(\.hidesAmountsWhenLocked, default: WidgetPrivacy.defaultHidesAmounts),
                          title: "Beträge verbergen",
                          detail: "Euro-Beträge erscheinen erst nach dem Entsperren. Prozent, Tage und Abfahrtszeiten bleiben sichtbar.",
                          symbol: "eurosign.circle.fill")
            }
            .tint(Theme.accent)
        }
    }

    /// Side by side with the switch; at accessibility sizes the words take the full width and the switch sits below
    /// them, so no word is split.
    @ViewBuilder
    private func switchRow(_ isOn: Binding<Bool>, title: String, detail: String, symbol: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                switchLabel(title: title, detail: detail, symbol: nil)
                    .accessibilityHidden(true)
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .accessibilityHint(detail)
            }
        } else {
            Toggle(isOn: isOn) {
                switchLabel(title: title, detail: detail, symbol: symbol)
            }
        }
    }

    private func switchLabel(title: String, detail: String, symbol: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A switch: the preview follows at once (and turns to the locked view, where the switch acts); the store writes
    /// the choice and reloads the widgets.
    private func binding(_ field: WritableKeyPath<WidgetPrivacy, Bool?>, default fallback: Bool) -> Binding<Bool> {
        Binding(get: { privacy[keyPath: field] ?? fallback }, set: { value in
            var next = privacy.resolved
            next[keyPath: field] = value
            withMotion(Motion.smooth) {
                privacy = next
                showsLocked = true
            }
            changes += 1
            WidgetPrivacyStore.set(next)
        })
    }

    private var footnote: some View {
        Label {
            Text("Gilt für den Sperrbildschirm und StandBy, solange dein iPhone gesperrt ist – iOS blendet die markierten Stellen aus. Live-Aktivitäten („Unterwegs“, „Live verfolgen“) zeigen deine Fahrt weiterhin vollständig.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Stage

/// A lock screen in miniature: the inline line above the clock, the round countdown and the rectangular widgets, drawn
/// with the widgets' own views. Locked, the marked texts turn into placeholders of the same size.
struct WidPrivacyStage: View {
    let snapshot: WidgetSnapshot
    let privacy: WidgetPrivacy
    let showsLocked: Bool

    @Environment(\.widNow) private var pinnedNow

    private var now: Date { pinnedNow ?? Date() }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
        VStack(spacing: Theme.Spacing.s) {
            lockBadge
            HStack(spacing: 6) {
                Text(Format.weekdayDayMonth(now))
                AmortizationWidgetView(snapshot: snapshot, family: .accessoryInline)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // The real time: the example departures below count from it.
            Text(verbatim: now.formatted(.dateTime.hour().minute().locale(WidFormat.locale)))
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(colors: [Color.white, Color.white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 12) {
                tile(.accessoryCircular) {
                    NextConnectionWidgetView(title: favoriteTitle, state: .fresh(now), items: connections, family: .accessoryCircular)
                }
                tile(.accessoryRectangular) {
                    NextConnectionWidgetView(title: favoriteTitle, state: .fresh(now), items: connections, family: .accessoryRectangular)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                tile(.accessoryRectangular) {
                    DeparturesWidgetView(stationName: stationName, state: .fresh(now), items: departures,
                                         family: .accessoryRectangular)
                }
                tile(.accessoryCircular) {
                    TicketRemainingWidgetView(snapshot: snapshot, family: .accessoryCircular, now: now)
                }
            }
            Text("Vorschau mit Beispielzeiten")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .unredacted()
        }
        .padding(.vertical, Theme.Spacing.l)
        .padding(.horizontal, Theme.Spacing.s)
        .frame(maxWidth: .infinity)
        .environment(\.widPrivacy, privacy)
        .environment(\.widNow, now)
        .redacted(reason: showsLocked ? .privacy : [])
        .background { WidPrivacyWallpaper() }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6) }
        .background { shape.fill(Theme.background).shadow(color: Color.black.opacity(0.25), radius: 18, y: 10) }
        .foregroundStyle(Color.white)
        .tint(Color.white)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(showsLocked ? "Vorschau: Sperrbildschirm, gesperrt" : "Vorschau: Sperrbildschirm, entsperrt")
    }

    private var lockBadge: some View {
        Image(systemName: showsLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .symbolReplaceTransition()
            .frame(height: 22)
            .accessibilityHidden(true)
    }

    private func tile<Content: View>(_ family: WidgetFamily, @ViewBuilder _ content: () -> Content) -> some View {
        let size = WidLayout.size(for: family)
        return content()
            .frame(width: size.width, height: size.height, alignment: family == .accessoryCircular ? .center : .leading)
            .padding(family == .accessoryCircular ? 0 : 6)
            .background {
                if family == .accessoryCircular {
                    Circle().fill(Color.white.opacity(0.1))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08))
                }
            }
    }

    /// The user's first favourite and its start (the preview's times are examples); demo names without favourites.
    private var favoriteTitle: String { snapshot.favorites.first?.title ?? "Pendeln" }
    private var stationName: String {
        let from = snapshot.favorites.first?.fromName ?? ""
        return from.isEmpty ? "Landeck-Zams" : RideNames.short(from)
    }

    private var connections: [WidgetConnection] {
        let destination = snapshot.favorites.first.map(\.toName).flatMap { $0.isEmpty ? nil : RideNames.short($0) }
        return WidSamples.connections(now: now).map { connection in
            var copy = connection
            if let destination { copy.toName = destination }
            return copy
        }
    }

    private var departures: [WidgetDeparture] { WidSamples.departures(now: now) }
}

/// Night sky behind the preview (always dark, like the lock-screen stage above it).
private struct WidPrivacyWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.background, Theme.dusk.mix(with: Theme.background, by: 0.55)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.glacier.opacity(0.32), .clear],
                           center: UnitPoint(x: 0.2, y: 0.9), startRadius: 0, endRadius: 240)
            RadialGradient(colors: [Theme.alpenglow.opacity(0.28), .clear],
                           center: UnitPoint(x: 0.86, y: 0.12), startRadius: 0, endRadius: 200)
        }
        .accessibilityHidden(true)
    }
}
