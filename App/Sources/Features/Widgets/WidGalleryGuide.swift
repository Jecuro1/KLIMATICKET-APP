import SwiftUI
import WidgetKit
import KlimaCore

// MARK: - Control Center

/// Control Center preview with both real controls (`KlimaControlWidget`, `KlimaFavoriteControl` in the extension):
/// "Fahrt erfassen" opens the editor here as it does there; the favourite control logs for show ("Erfasst"),
/// nothing is saved.
struct WidControlCenterSection: View {
    /// The favourite the preview control stands for (the first one; a sample without favourites).
    var favorite: WidgetSnapshot.Favorite?
    var onTry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var addTaps = 0
    @State private var favoriteTaps = 0
    @State private var showsLogged = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "Kontrollzentrum & Aktionstaste",
                          caption: "Ein Druck – und du bist mitten im Erfassen. Oder die Lieblingsfahrt ist schon gespeichert.")
            GlassCard(padding: Theme.Spacing.m) {
                layout {
                    panel
                    copy
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
        }
        .haptic(.tap, trigger: addTaps)
        .haptic(.success, trigger: favoriteTaps)
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
    }

    private func tryAdd() {
        addTaps += 1
        onTry()
    }

    /// The preview of "Lieblingsfahrt erfassen": checkmark + "Erfasst" for a moment, like the real control.
    private func tryFavorite() {
        favoriteTaps += 1
        let tap = favoriteTaps
        withMotion(Motion.bouncy) { showsLogged = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard favoriteTaps == tap else { return }
            withMotion(Motion.smooth) { showsLogged = false }
        }
    }

    /// Mini Control Center: two generic system controls, "Fahrt erfassen" and the wide favourite control.
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.formGroup, style: .continuous)
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                genericControl("flashlight.off.fill")
                genericControl("camera.fill")
            }
            GridRow {
                genericControl("timer")
                addControl
            }
            GridRow {
                favoriteControl
                    .gridCellColumns(2)
            }
        }
        .padding(12)
        .background {
            shape.fill(Theme.background)
                .overlay {
                    RadialGradient(colors: [Theme.dusk.opacity(0.45), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 120)
                        .clipShape(shape)
                }
        }
        .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6) }
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private func genericControl(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(width: 46, height: 46)
            .background(Circle().fill(Color.white.opacity(0.14)))
            .accessibilityHidden(true)
    }

    private var addControl: some View {
        Button(action: tryAdd) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .symbolBounce(on: addTaps)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.ctaGradient))
        }
        .buttonStyle(.pressable(scale: 0.9))
        .accessibilityLabel("Fahrt erfassen")
        .accessibilityHint("Öffnet das Erfassen einer neuen Fahrt")
    }

    /// 2 × 1 like the real wide control: gold disc + favourite name + value / "Erfasst".
    private var favoriteControl: some View {
        let title = favorite?.title ?? "Pendeln"
        let symbol = favorite?.modeSymbol ?? "train.side.front.car"
        return Button(action: tryFavorite) {
            HStack(spacing: 6) {
                Image(systemName: showsLogged ? "checkmark" : symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .symbolReplaceTransition()
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(showsLogged ? AnyShapeStyle(Theme.positive.gradient) : AnyShapeStyle(Theme.gold.gradient)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(showsLogged ? "Erfasst" : WidFormat.euroPrecise(favorite?.value ?? 22.8))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(width: 102, height: 46)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable(scale: 0.95))
        .accessibilityLabel("\(title) erfassen")
        .accessibilityValue(showsLogged ? "Erfasst" : "")
        .accessibilityHint("Vorschau – es wird nichts gespeichert")
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            controlRow(symbol: "plus.circle.fill", tint: Theme.accent, title: "Fahrt erfassen",
                       text: "Öffnet KlimaBilanz direkt beim Erfassen einer neuen Fahrt.")
            controlRow(symbol: "star.circle.fill", tint: Theme.gold, title: "Lieblingsfahrt erfassen",
                       text: "Speichert deine gewählte Lieblingsfahrt sofort – ohne die App zu öffnen.")
            Button(action: tryAdd) {
                Label("Ausprobieren", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Footnote like the other descriptions here: at subheadline size the narrow column split compounds
    // ("Kontroll-", "Sperrbild-", "Akti-").
    private func controlRow(symbol: String, tint: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - How to add

enum WidGuideTopic: String, CaseIterable, Identifiable {
    case home, lock, control

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home-Bildschirm"
        case .lock: "Sperrbildschirm"
        case .control: "Kontrollzentrum"
        }
    }

    var symbol: String {
        switch self {
        case .home: "apps.iphone"
        case .lock: "lock.fill"
        case .control: "switch.2"
        }
    }
}

/// Step-by-step instructions per place, plus notes on the iOS 26 tinted/clear styles and live updates.
struct WidGuideSection: View {
    @Binding var topic: WidGuideTopic
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "So fügst du sie hinzu", caption: "In wenigen Sekunden eingerichtet – ganz ohne Konto.")
            topicChips
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    steps
                        .id(topic)
                        .motionTransition(.rise)
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                    notes
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
        }
        .haptic(.selection, trigger: topic)
    }

    private var topicChips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(WidGuideTopic.allCases) { item in
                        Chip(title: item.title, symbol: item.symbol, isSelected: topic == item) {
                            withMotion(Motion.smooth) { topic = item }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.Spacing.cardGutter, for: .scrollContent)
    }

    private var steps: some View {
        let items = stepTexts
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(items.indices, id: \.self) { index in
                stepRow(number: index + 1, text: items[index])
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Text(verbatim: String(number))
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.onAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.ctaGradient))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritt \(number): \(text)")
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            note(symbol: "paintpalette.fill", tint: Theme.dusk,
                 text: "Passt zu den iOS-Stilen „Getönt“ und „Klar“ – Zahl, Route und Fahne übernehmen deine Akzentfarbe.")
            note(symbol: "arrow.triangle.2.circlepath", tint: Theme.pine,
                 text: "Nach jeder erfassten Fahrt aktualisieren sich alle Widgets automatisch.")
            note(symbol: "clock.fill", tint: Theme.gold,
                 text: "Auch im StandBy: Lädt dein iPhone quer, zeigt das kleine Widget dein Ticket groß neben der Uhr.")
        }
    }

    private func note(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Copy

    private var percentText: String { WidFormat.percent(snapshot.amortizedFraction) }

    private var rectangularText: String {
        if WidInsight.isPaidOff(snapshot) { return "\(percentText) · + \(WidFormat.euroWhole(WidFigures.profit(snapshot)))" }
        return "\(percentText) · noch \(WidFormat.euroWhole(WidFigures.remaining(snapshot)))"
    }

    private var stepTexts: [String] {
        switch topic {
        case .home:
            return [
                "Halte eine freie Stelle auf dem Home-Bildschirm gedrückt, bis die Apps wackeln.",
                "Tippe oben links auf „Bearbeiten“ und dann auf „Widget hinzufügen“.",
                "Suche nach „KlimaBilanz“ und wähle „Amortisation“ oder „Schnellerfassung“ in deiner Lieblingsgröße.",
                "Tippe auf „Widget hinzufügen“ – fertig. Favoriten erfasst du ab jetzt direkt im Widget.",
            ]
        case .lock:
            return [
                "Halte den entsperrten Sperrbildschirm gedrückt und tippe auf „Anpassen“.",
                "Wähle „Sperrbildschirm“ und tippe auf das Feld unter der Uhrzeit.",
                "Füge unter „KlimaBilanz“ den Ring oder die Zeile „\(rectangularText)“ hinzu.",
                "Für die Zeile über der Uhrzeit tippst du auf das Datum und wählst „\(percentText) rentiert“.",
            ]
        case .control:
            return [
                "Streiche vom rechten oberen Rand nach unten, um das Kontrollzentrum zu öffnen.",
                "Tippe oben links auf „+“ und dann auf „Steuerelement hinzufügen“.",
                "Suche nach „KlimaBilanz“ und wähle „Fahrt erfassen“ oder „Lieblingsfahrt erfassen“ – dann die Fahrt dazu.",
                "Tipp: Beide kannst du auch der Aktionstaste oder dem Sperrbildschirm zuweisen.",
            ]
        }
    }
}
