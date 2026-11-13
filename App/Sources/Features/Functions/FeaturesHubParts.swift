import SwiftUI
import KlimaCore

// MARK: funktionen – the parts of Einstellungen › Funktionen: the hero with the feature mosaic, the Offline-Modus card, one row per
// feature and the „Was wird gesendet?“ popover. Liquid Glass only on controls, the rows sit on the list's calm surface.

// MARK: - Hero

/// „13 von 15 an“ over a mosaic of every feature: a lit tile is on, a tinted outline is hidden by what it needs or the Offline-Modus,
/// a grey one is switched off. The count rolls and the tiles change colour when a switch moves.
struct FeatureHubHero: View {
    var statuses: [FeatureStatus]
    var offlineMode: Bool
    var hiddenCount: Int

    @Environment(\.dynamicTypeSize) private var typeSize

    private var onCount: Int { statuses.filter(\.isOn).count }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Image(systemName: "switch.2")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.ctaGradient, in: .rect(cornerRadius: 16, style: .continuous))
                    .symbolBounce(on: onCount)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Was die App kann")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .accessibilityAddTraits(.isHeader)
                    Text("Jede Funktion mit eigenem Schalter")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CountUpText(value: Double(onCount)) { "\(Int($0.rounded()))" }
                    .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text("von \(statuses.count) an")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(onCount) von \(statuses.count) Funktionen an")
            FeatureMosaic(statuses: statuses)
            pills
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var pills: some View {
        if offlineMode || hiddenCount > 0 {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
            layout {
                if offlineMode {
                    SetPill(text: "Offline-Modus an", symbol: "wifi.slash", tint: Theme.summitText)
                        .motionTransition(.pop)
                }
                if hiddenCount > 0 {
                    SetPill(text: hiddenCount == 1 ? "1 Einstieg ausgeblendet" : "\(hiddenCount) Einstiege ausgeblendet",
                            symbol: "eye.slash", tint: Theme.summitText)
                        .motionTransition(.pop)
                }
            }
        }
    }
}

/// Every feature as a small tile, in registry order (decorative: the count and the rows carry the meaning for VoiceOver).
struct FeatureMosaic: View {
    var statuses: [FeatureStatus]

    private let columns = [GridItem(.adaptive(minimum: 30, maximum: 40), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(statuses, id: \.id) { status in
                FeatureMosaicTile(status: status)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FeatureMosaicTile: View {
    var status: FeatureStatus

    var body: some View {
        let tone = FeatureStatusTone(status)
        let tint = status.id.tint
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Image(systemName: status.id.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tone == .on || tone == .waiting ? Color.white : (tone == .hidden ? tint : Theme.textTertiary))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background {
                switch tone {
                case .on, .waiting:
                    // The saturated light variant in both appearances, so the white symbol keeps its contrast (like SetIconTile).
                    shape.fill(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.18)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .environment(\.colorScheme, .light)
                case .hidden:
                    shape.fill(tint.opacity(0.14)).overlay { shape.strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])) }
                case .off:
                    shape.fill(Theme.surfaceSecondary)
                }
            }
            .overlay(alignment: .topTrailing) {
                if tone == .waiting {
                    Circle().fill(Theme.summit).frame(width: 7, height: 7).offset(x: 2, y: -2)
                        .motionTransition(.pop)
                }
            }
            .scaleEffect(tone == .off ? 0.92 : 1)
            .motionAnimation(Motion.snappy, value: tone)
    }
}

// MARK: - Offline-Modus

/// One switch for every live request and the automatic update check, with exactly what it stops and what it does not.
struct FeatureOfflineCard: View {
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Toggle(isOn: $isOn) {
                SetRowLabel(title: "Offline-Modus",
                            subtitle: isOn ? "An – KlimaBilanz fragt nichts live ab" : "Keine Live-Daten, keine automatische Update-Prüfung",
                            symbol: isOn ? "wifi.slash" : "wifi", tint: isOn ? Theme.dawn : Theme.glacier)
                    .setSymbolOnEnable(isOn)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Kicker(text: isOn ? "Gestoppt" : "Stoppt")
                    .contentTransition(.opacity)
                ForEach(FeaturePrivacy.offlineStops, id: \.self) { line in
                    Label {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: isOn ? "xmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(isOn ? Theme.summitText : Theme.textTertiary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                Label {
                    Text(FeaturePrivacy.offlineKeeps)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.positiveText)
                }
                .padding(.top, 2)
            }
            .padding(.leading, Theme.Spacing.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
        .haptic(.snap, trigger: isOn)
    }

    private var accessibilityText: String {
        (isOn ? "Gestoppt: " : "Stoppt: ") + FeaturePrivacy.offlineStops.joined(separator: "; ") + ". " + FeaturePrivacy.offlineKeeps
    }
}

// MARK: - Row

/// One feature: icon, name, one line, its state as text, what is different while it is off, „Was wird gesendet?“ and its switch
/// (or the way to its own page). For VoiceOver the whole row is one switch with name, state and explanation.
struct FeatureHubRow: View {
    var descriptor: FeatureDescriptor
    var status: FeatureStatus
    var statusLine: String
    /// A feature it needs that one tap would switch on („Fahrplan & Echtzeit einschalten“).
    var dependency: FeatureID?
    var onToggle: (Bool) -> Void
    var onEnableDependency: (FeatureID) -> Void
    var onOpenPage: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsFlows = false

    private var tone: FeatureStatusTone { FeatureStatusTone(status) }
    private var isToggle: Bool { descriptor.control == .toggle }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack {
                        icon
                        Spacer(minLength: Theme.Spacing.xs)
                        control
                    }
                    texts
                }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    icon
                    texts
                    Spacer(minLength: Theme.Spacing.xs)
                    control
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descriptor.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isToggle ? .isToggle : .isButton)
        .accessibilityAction { isToggle ? onToggle(!status.switchIsOn) : onOpenPage() }
        .accessibilityAction(named: "Was wird gesendet?") { showsFlows = true }
        .modifier(FeatureDependencyAction(dependency: dependency, onEnable: onEnableDependency))
    }

    private var icon: some View {
        SetIconTile(symbol: descriptor.id.symbol, tint: tone == .off ? Theme.modeColor(.other) : descriptor.id.tint)
            .symbolReplaceTransition()
            .setSymbolOnEnable(status.isOn)
            .padding(.top, 1)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(descriptor.title)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Text(descriptor.line)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: tone.symbol)
                    .font(.caption2.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(statusLine)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tone.color)
            .padding(.top, 1)
            if !status.isOn {
                Text(descriptor.offEffect)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .motionTransition(.rise)
            }
            if let dependency {
                Button { onEnableDependency(dependency) } label: {
                    Label("\(dependency.title) einschalten", systemImage: "power")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.top, 2)
                .motionTransition(.pop)
            }
            Button { showsFlows = true } label: {
                Label("Was wird gesendet?", systemImage: "info.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accentText)
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
            .popover(isPresented: $showsFlows, arrowEdge: .top) {
                FeatureFlowPopover(descriptor: descriptor)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        if isToggle {
            Toggle(descriptor.title, isOn: Binding(get: { status.switchIsOn }, set: onToggle))
                .labelsHidden()
        } else {
            Button(action: onOpenPage) {
                HStack(spacing: 4) {
                    Text(status.switchIsOn ? "An" : "Einrichten")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.accentText)
            }
            .buttonStyle(.borderless)
        }
    }

    private var accessibilityValue: String {
        let state = isToggle ? (status.switchIsOn ? "Schalter an" : "Schalter aus") : (status.switchIsOn ? "an" : "aus")
        return "\(state), \(statusLine). \(descriptor.line)"
    }

    private var accessibilityHint: String {
        var parts: [String] = []
        if !status.isOn { parts.append(descriptor.offEffect) }
        if !isToggle, let place = descriptor.place { parts.append("Wird auf der eigenen Seite eingeschaltet: \(place).") }
        return parts.joined(separator: " ")
    }
}

/// „Fahrplan & Echtzeit einschalten“ as a VoiceOver action of the row, when it applies.
private struct FeatureDependencyAction: ViewModifier {
    var dependency: FeatureID?
    var onEnable: (FeatureID) -> Void

    func body(content: Content) -> some View {
        if let dependency {
            content.accessibilityAction(named: "\(dependency.title) einschalten") { onEnable(dependency) }
        } else {
            content
        }
    }
}

// MARK: - Popover

/// „Was wird gesendet?“: every recipient of the feature, what it gets and when.
struct FeatureFlowPopover: View {
    var descriptor: FeatureDescriptor

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(idealWidth: 320, maxWidth: 360)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Kicker(text: "Was wird gesendet?")
            Text(descriptor.title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            ForEach(descriptor.dataFlows, id: \.self) { flow in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    SetIconTile(symbol: flow.recipient.symbol, tint: flow.recipient.tint, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flow.recipient.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(flow.sends)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                        if flow.recipient.isRemote {
                            Text("Wann: \(flow.when)")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.Spacing.m)
    }
}
