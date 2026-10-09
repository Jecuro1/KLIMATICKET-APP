import SwiftUI
import KlimaCore

// "Reise mit Etappen" in the trip editor (docs/JOURNEYS.md §5). The route card becomes the journey's chain: Von · leg ·
// Umstieg · leg · … · Nach. Each leg is a chip on the route line (mode, km, price) – tapping it selects the leg the mode strip
// and the price card edit; transfers are stops on the line (tap → picker, ✕ → the two legs merge). "⊕ Etappe anhängen"
// under the destination picks where the next leg goes.

/// A leg on the route line: mode plate · "Zug" / "456 km" · price. Selected: tinted in the mode colour.
struct TripEdLegChip: View {
    let model: TripEditorModel
    let index: Int
    var onSelect: () -> Void
    var onRemove: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var plate: CGFloat = 30

    /// Guarded: a chip that is sliding out after its leg was removed may render once more with its old index.
    private var leg: TripEdLeg { model.legs.indices.contains(index) ? model.legs[index] : TripEdLeg(mode: .other) }
    private var isSelected: Bool { model.selectedLeg == index }

    var body: some View {
        let tint = Theme.modeColor(leg.mode)
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: leg.mode.symbolName)
                    .font(.system(size: plate * 0.46, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: plate, height: plate)
                    .background(tint.gradient, in: .rect(cornerRadius: plate * 0.31, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(leg.mode.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge = TripEdFormat.badge(for: leg.mode), badge != leg.mode.displayName {
                            TripEdModeBadge(text: badge)
                        }
                    }
                    Text(meta)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(leg.fare > 0 || leg.estimate != nil ? Theme.textSecondary : Theme.summitText)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text(leg.fare > 0 ? Format.euroPrecise(leg.fare) : "–")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(leg.fare > 0 ? Theme.textPrimary : Theme.textTertiary)
                    .numericValue(leg.fare)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, Theme.Spacing.s)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.14) : Theme.surfaceSecondary.opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.55) : .clear, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(TripEdPressStyle())
        .padding(.vertical, 6)
        .contextMenu {
            Button("Verkehrsmittel & Preis", systemImage: "slider.horizontal.3", action: onSelect)
            Button("Etappe entfernen", systemImage: "minus.circle", role: .destructive, action: onRemove)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(leg.fare > 0 ? Format.euroPrecise(leg.fare) : "noch kein Preis")
        .accessibilityHint(isSelected ? "Verkehrsmittel und Preis darunter gelten für diese Etappe" : "Wählt die Etappe zum Bearbeiten")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Etappe entfernen", onRemove)
    }

    /// "456 km · über Feldkirch" / "Preis fehlt"
    private var meta: String {
        var parts: [String] = []
        if leg.distanceKm > 0 { parts.append(Format.km(leg.distanceKm)) }
        let vias = leg.vias.map(\.name)
        if !vias.isEmpty { parts.append("über " + FareEstimator.viaList(vias.map { TripRow.short($0) })) }
        if leg.fare <= 0 && leg.estimate == nil { parts.append("Preis eingeben") }
        return parts.isEmpty ? "Etappe \(index + 1)" : parts.joined(separator: " · ")
    }

    private var spokenLabel: String {
        let ends = model.legEnds(index)
        let route = ends.from.isEmpty || ends.to.isEmpty ? "" : ", \(ends.from) nach \(ends.to)"
        return "Etappe \(index + 1) von \(model.legs.count): \(leg.mode.displayName)\(route)"
    }
}

/// "◯ Umstieg / Langen am Arlberg / Bahnhof · Vorarlberg ✕" – a transfer stop on the route line (ring in the colour of the
/// leg that starts there).
struct TripEdTransferRow: View {
    let model: TripEditorModel
    /// Index into the model's stops (1 … legs − 1).
    let stop: Int
    let lineOffset: CGFloat
    var onTap: () -> Void
    var onRemove: () -> Void

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 11

    private var value: TripEdStop { model.stops.indices.contains(stop) ? model.stops[stop] : TripEdStop() }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Umstieg")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(value.resolvedName.isEmpty ? "Haltestelle wählen" : TripEdFormat.displayName(value.resolvedName))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(value.resolvedName.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .overlay(alignment: .leading) { ring }
                        .id(value.resolvedName)
                        .motionTransition(AnyTransition(.blurReplace))
                    if let station = value.station {
                        Text(TripEdFormat.stationSubtitle(station))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    } else if !value.resolvedName.isEmpty {
                        Text("Eigener Ort")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .contentShape(.rect)
            }
            .buttonStyle(TripEdPressStyle())
            .accessibilityLabel("Umstieg in \(value.resolvedName.isEmpty ? "noch keiner Haltestelle" : value.resolvedName)")
            .accessibilityHint("Öffnet die Suche für diesen Umstieg")
            .accessibilityAction(named: "Umstieg entfernen", onRemove)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.pressable(scale: 0.85))
            .accessibilityLabel("Umstieg in \(value.resolvedName) entfernen")
        }
        .contextMenu {
            Button("Ändern", systemImage: "magnifyingglass", action: onTap)
            Button("Umstieg entfernen", systemImage: "xmark", role: .destructive, action: onRemove)
        }
    }

    /// Hollow ring like the start's, in the colour of the leg that starts here; knocks the dashed line out around it.
    private var ring: some View {
        let next = model.legs.indices.contains(stop) ? model.legs[stop].mode : .train
        return Circle()
            .strokeBorder(Theme.modeColor(next), lineWidth: 2.5)
            .frame(width: ringSize, height: ringSize)
            .padding(2.5)
            .background(TripEdViaAddMark.cardColor, in: .circle)
            .offset(x: lineOffset - ringSize / 2 - 2.5)
            .accessibilityHidden(true)
    }
}

/// "⊕ Umsteigen? Etappe anhängen" under the destination – the ⊕ in the route line's column.
struct TripEdAddLegButton: View {
    let isJourney: Bool
    /// Centre of the route line relative to the text column and the column's leading inset (as TripEdViaRows).
    var lineOffset: CGFloat = -17.5
    var leadingInset: CGFloat = 26
    var action: () -> Void

    private var markColumn: CGFloat { 2 * (leadingInset + lineOffset) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                TripEdViaAddMark()
                    .frame(width: markColumn)
                Spacer().frame(width: leadingInset - markColumn)
                Text(isJourney ? "Weitere Etappe anhängen" : "Umsteigen? Etappe anhängen")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .padding(.leading, -leadingInset)
        .padding(.top, 4)
        .accessibilityLabel(isJourney ? "Weitere Etappe anhängen" : "Etappe anhängen")
        .accessibilityHint("Öffnet die Suche für das Ziel der nächsten Etappe – Bus, Zug, Bim, jede mit eigenem Preis.")
    }
}

/// Above the mode strip while the form is a journey: "ETAPPE 2 VON 3 · Langen → Wien Hbf" with ‹ › to step through the
/// legs – it says which leg the mode strip and the price card edit.
struct TripEdLegFocusBar: View {
    let model: TripEditorModel
    var onSelect: (Int) -> Void

    var body: some View {
        let index = model.selectedLeg
        let ends = model.legEnds(index)
        HStack(spacing: Theme.Spacing.xs) {
            VStack(alignment: .leading, spacing: 1) {
                Kicker(text: "Etappe \(index + 1) von \(model.legs.count)")
                    .contentTransition(.numericText(value: Double(index)))
                Text(ends.from.isEmpty || ends.to.isEmpty ? "Ziel wählen"
                     : TripEdFormat.routeTitle(from: ends.from, to: ends.to, roundTrip: false))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Theme.Spacing.xs)
            stepButton("chevron.left", label: "Vorherige Etappe", target: index - 1)
            stepButton("chevron.right", label: "Nächste Etappe", target: index + 1)
        }
        .padding(.horizontal, Theme.Spacing.xxs)
    }

    private func stepButton(_ symbol: String, label: String, target: Int) -> some View {
        let enabled = model.legs.indices.contains(target)
        return Button {
            onSelect(target)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(enabled ? Theme.accentText : Theme.textTertiary)
                .frame(width: 34, height: 34)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
