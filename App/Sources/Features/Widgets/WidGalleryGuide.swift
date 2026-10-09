import SwiftUI
import WidgetKit
import KlimaCore

// MARK: - Control Center

/// Control Center preview (the real control is `KlimaControlWidget` in the extension) – tapping it here
/// opens "Fahrt erfassen", exactly like the control does.
struct WidControlCenterSection: View {
    var onTry: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var taps = 0

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "Kontrollzentrum", caption: "Ein Tipp – und du bist mitten im Erfassen.")
            GlassCard(padding: Theme.Spacing.m) {
                layout {
                    panel
                    copy
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps) { _, _ in haptics }
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
    }

    private func tryIt() {
        taps += 1
        onTry()
    }

    /// Mini Control Center: three generic system controls and the KlimaBilanz button.
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.formGroup, style: .continuous)
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                genericControl("flashlight.off.fill")
                genericControl("timer")
            }
            GridRow {
                genericControl("camera.fill")
                klimaControl
            }
        }
        .padding(12)
        .background {
            shape.fill(Theme.background)
                .overlay {
                    RadialGradient(colors: [Theme.dusk.opacity(0.45), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 110)
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

    private var klimaControl: some View {
        Button(action: tryIt) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .symbolEffect(.bounce, value: taps)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.ctaGradient))
                .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fahrt erfassen")
        .accessibilityHint("Öffnet das Erfassen einer neuen Fahrt")
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Fahrt erfassen")
            } icon: {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            }
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            // Footnote like the other descriptions here: at subheadline size the narrow column split three
            // compounds in a row ("Kontroll-", "Sperrbild-", "Akti-").
            Text("Öffnet KlimaBilanz direkt beim Erfassen einer neuen Fahrt – aus dem Kontrollzentrum, vom Sperrbildschirm oder über die Aktionstaste.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: tryIt) {
                Label("Ausprobieren", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .tint(Theme.accent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @Environment(AppState.self) private var app

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidStageTitle(title: "So fügst du sie hinzu", caption: "In wenigen Sekunden eingerichtet – ganz ohne Konto.")
            topicChips
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    steps
                        .id(topic)
                        .transition(.opacity)
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                    notes
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
        }
        .sensoryFeedback(.selection, trigger: topic) { _, _ in haptics }
    }

    private var topicChips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(WidGuideTopic.allCases) { item in
                        Chip(title: item.title, symbol: item.symbol, isSelected: topic == item) {
                            withAnimation(.smooth(duration: 0.3)) { topic = item }
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
        if WidInsight.isPaidOff(snapshot) { return "\(percentText) · + \(WidFormat.euroWhole(snapshot.net))" }
        return "\(percentText) · noch \(WidFormat.euroWhole(snapshot.remaining))"
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
                "Suche nach „KlimaBilanz“ und wähle „Fahrt erfassen“.",
                "Tipp: „Fahrt erfassen“ kannst du auch der Aktionstaste oder dem Sperrbildschirm zuweisen.",
            ]
        }
    }
}
