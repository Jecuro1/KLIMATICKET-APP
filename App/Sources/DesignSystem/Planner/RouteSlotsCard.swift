import SwiftUI
import KlimaCore

/// The Von / Nach card of the Fahrplan (UX §4.1, mock 10): two slots on a dotted route glyph, optional „Über“ stops, a
/// glass swap button and the time row. Geometry follows `TripEdRouteCard` (copied constants, not shared code).
struct RouteSlotsCard<Footer: View>: View {
    struct Slot: Identifiable, Equatable {
        var id: String
        var caption: String
        var title: String
        var subtitle: String?
        var isPlaceholder: Bool
        var showsLocationArrow = false
    }

    var origin: Slot
    var vias: [Slot] = []
    var destination: Slot
    var onTap: (String) -> Void
    var onSwap: () -> Void
    var onRemoveVia: (String) -> Void = { _ in }
    var onAddVia: (() -> Void)? = nil
    @ViewBuilder var footer: Footer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swapTurns = 0

    @ScaledMetric(relativeTo: .title2) private var nodeY: CGFloat = 38
    @ScaledMetric(relativeTo: .body) private var viaNodeY: CGFloat = 19

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    slot(origin).railed(.first, nodeY: nodeY)
                    ForEach(vias) { via in
                        viaRow(via).railed(.middle, nodeY: viaNodeY).motionTransition(.rise)
                    }
                    slot(destination).railed(.last, nodeY: nodeY, extendsBelow: addViaVisible)
                    if addViaVisible, let onAddVia {
                        Button(action: onAddVia) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 15))
                                Text("Über …").font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Theme.accentText)
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 28)
                        .accessibilityLabel("Zwischenhalt hinzufügen")
                        .accessibilityHint("Bis zu zwei Halte, über die die Verbindung führen soll")
                    }
                }
                swapButton
            }
            .padding(.vertical, Theme.Spacing.s)
            .padding(.leading, Theme.Spacing.m)
            .padding(.trailing, Theme.Spacing.s)
            Divider().overlay(Theme.separator)
            footer
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
        }
        .frostedCard(cornerRadius: Theme.Radius.card)
        .haptic(.tap, trigger: swapTurns)
        .motionAnimation(Motion.smooth, value: vias.map(\.id))
    }

    private var addViaVisible: Bool { onAddVia != nil && vias.count < JourneyQuery.maxViaStops }

    private func slot(_ slot: Slot) -> some View {
        Button { onTap(slot.id) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.caption).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Text(slot.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(slot.isPlaceholder ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle = slot.subtitle {
                    HStack(spacing: 5) {
                        if slot.showsLocationArrow {
                            Image(systemName: "location.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                        }
                        Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.leading, 28)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable(scale: Motion.Distance.pressScaleCard))
        .accessibilityLabel(slot.caption + ": " + slot.title + (slot.subtitle.map { ", " + $0 } ?? ""))
        .accessibilityHint("Öffnet die Suche")
    }

    private func viaRow(_ via: Slot) -> some View {
        HStack(spacing: 8) {
            Button { onTap(via.id) } label: {
                HStack(spacing: 8) {
                    Text("über").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Text(via.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.leading, 28)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button { onRemoveVia(via.id) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.textTertiary).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(via.title) als Zwischenhalt entfernen")
        }
        .accessibilityElement(children: .contain)
    }

    private var swapButton: some View {
        Button {
            withMotion(Motion.bouncy) {
                swapTurns += 1
                onSwap()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(swapTurns) * 180))
                .frame(width: 46, height: 46)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Start und Ziel tauschen")
    }
}

private enum SlotPosition { case first, middle, last }

private extension View {
    /// The dotted route line and the node of a slot, drawn in its left gutter (the node sits at the middle of the title).
    func railed(_ position: SlotPosition, nodeY: CGFloat, extendsBelow: Bool = false) -> some View {
        overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                let top: CGFloat = position == .first ? nodeY : 0
                let bottom: CGFloat = position == .last && !extendsBelow ? nodeY : proxy.size.height
                Path { p in
                    p.move(to: CGPoint(x: 8, y: top))
                    p.addLine(to: CGPoint(x: 8, y: bottom))
                }
                .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 5]))
                node(position).position(x: 8, y: nodeY)
            }
            .frame(width: 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func node(_ position: SlotPosition) -> some View {
        switch position {
        case .first: Circle().strokeBorder(Theme.accent, lineWidth: 3).background(Circle().fill(Theme.sheetBackground)).frame(width: 14, height: 14)
        case .middle: Circle().fill(Theme.textSecondary).frame(width: 8, height: 8)
        case .last: Circle().fill(Theme.dawn).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.dawn.opacity(0.28), lineWidth: 5))
        }
    }
}
