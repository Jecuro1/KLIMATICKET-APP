import SwiftUI
import KlimaCore

/// Saved scenarios (at most five, kept on this device) and the plain-text share of the current result.
struct WhatIfScenariosCard: View {
    @Bindable var model: WhatIfModel
    let result: WhatIfResult

    @State private var isNaming = false
    @State private var draftName = ""

    private var headline: String { WhatIfText.scenarioHeadline(result) }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    StatsCardHeader(kicker: "Szenarien", title: nil)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text("\(model.scenarios.count) von \(WhatIfLimits.maxScenarios)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                if model.scenarios.isEmpty {
                    Text("Speichere eine Rechnung, um sie später wieder aufzurufen. Gespeichert wird nur auf diesem Gerät.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.scenarios.enumerated()), id: \.element.id) { index, scenario in
                            if index > 0 { Divider().overlay(Theme.separator) }
                            row(scenario)
                        }
                    }
                }
                actions
                if let notice = model.scenarioNotice {
                    Text(notice)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(model.canSaveScenario ? Theme.positiveText : Theme.summitText)
                        .fixedSize(horizontal: false, vertical: true)
                        .motionTransition(.rise)
                }
            }
        }
        .motionAnimation(Motion.smooth, value: model.scenarios.map(\.id))
        .alert("Szenario speichern", isPresented: $isNaming) {
            TextField("Name", text: $draftName)
            Button("Speichern") {
                withMotion(Motion.smooth) { model.saveScenario(named: draftName, headline: headline) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Gespeichert werden deine Eingaben, nicht die Zahlen – beim Öffnen wird mit den aktuellen Tarifen neu gerechnet.")
        }
    }

    // MARK: Rows

    private func row(_ scenario: WhatIfScenario) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button {
                withMotion(Motion.smooth) { model.load(scenario) }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: scenario.usesHistory ? "clock.arrow.circlepath" : "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent.opacity(0.14), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scenario.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if !scenario.savedHeadline.isEmpty {
                            Text(scenario.savedHeadline)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet das Szenario")
            Button {
                withMotion(Motion.smooth) { model.delete(scenario) }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(Theme.negativeText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(scenario.name) löschen")
        }
    }

    // MARK: Actions

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { actionButtons }
            VStack(spacing: Theme.Spacing.xs) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            draftName = ""
            if model.canSaveScenario {
                isNaming = true
            } else {
                withMotion(Motion.smooth) { model.saveScenario(named: "", headline: "") }
            }
        } label: {
            Label("Szenario speichern", systemImage: "square.and.arrow.down")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(result.state == .needsRoutes)
        ShareLink(item: WhatIfText.share(result, title: model.mode == .history ? "Meine Fahrten" : "Eigene Annahmen",
                                         usesHistory: model.mode == .history)) {
            Label("Teilen", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(result.state == .needsRoutes)
    }
}
