import SwiftUI
import KlimaCore

// MARK: radarheat – the summary panel of the Pünktlichkeit layer (docs/RADAR_HEATMAP.md §4): a glass card at the bottom of the radar.
// Closed it holds the headline figure, the stacked bar and the number of trains it rests on; open it adds the legend, the largest
// delays right now and the three hot spots. Every number comes from `RadarHeat` (KlimaCore, tested); this view only lays it out.
// VoiceOver reads the card as one summary; the rows of the largest delays and of the hot spots are buttons of their own, which is
// how a VoiceOver user reaches the trains behind the cells (the map's cells are not focusable one by one).

struct RadarHeatPanel: View {
    var model: RadarModel
    var onTrain: (String) -> Void
    var onHotspot: (HeatHotspot) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var contentHeight: CGFloat = 0

    private var heat: RadarHeatModel { model.heat }

    /// The card is as tall as its content, at most this much of the map: closed 40 %, open 62 % (80 % at the accessibility text sizes,
    /// where even the headline is several lines). Beyond that the content scrolls inside
    /// the card. A card of any height would do on a small text size; at the largest ones the content is several screens tall, and a
    /// glass shape that tall is not drawn at all (CI screenshot radarHeatAX5, run 1: the text lay straight on the map).
    private var maxHeight: CGFloat {
        let open = typeSize.isAccessibilitySize ? 0.8 : 0.62
        return CGFloat(max(Double(model.mapSize.height), 560) * (heat.isExpanded ? open : 0.4))
    }

    var body: some View {
        let snapshot = heat.snapshot
        let summary = snapshot.summary
        ScrollViewReader { reader in
            ScrollView {
                content(snapshot, summary)
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        contentHeight = height
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .task(id: heat.isExpanded) {
                // Screenshot scenes `radarHeatLists` and `radarHeatTrend`: the open card shows its lists, or its trend line.
                guard heat.scrollsToLists || heat.scrollsToTrend, heat.isExpanded else { return }
                try? await Task.sleep(for: .milliseconds(2500))   // the first answers are in
                if heat.scrollsToTrend { reader.scrollTo("heat.trend", anchor: .center) } else { reader.scrollTo("heat.lists", anchor: .top) }
            }
        }
        .frame(maxHeight: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
        .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
        .motionAnimation(Motion.smooth, value: heat.isExpanded)
        .haptic(.tap, trigger: heat.isExpanded)
    }

    private func content(_ snapshot: HeatSnapshot, _ summary: HeatSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button { toggle() } label: { header(summary) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .modifier(HeatSummaryLabel(model: model, summary: summary))
                .accessibilityValue(heat.isExpanded ? "Details sichtbar" : "Details ausgeblendet")
                .accessibilityHint(heat.isExpanded ? "Details ausblenden" : "Details einblenden")
                .accessibilityAddTraits(.updatesFrequently)
            HeatStackedBar(summary: summary)
                .accessibilityHidden(true)   // the summary above reads the same numbers
            Text(RadarHeatText.realtimeLine(summary))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            if heat.isExpanded {
                details(snapshot)
                    .transition(.opacity)
            }
            RadarHeatAge(model: model)
        }
    }

    private func toggle() {
        withMotion(Motion.smooth) { heat.isExpanded.toggle() }
    }

    // MARK: Header

    private func header(_ summary: HeatSummary) -> some View {
        let percent = summary.punctualPercent
        let number = Text(percent.map { "\($0) %" } ?? "–")
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .numericValue(Double(percent ?? 0))
        let chevron = Image(systemName: "chevron.up")
            .font(.footnote.weight(.bold))
            .foregroundStyle(Theme.textSecondary)
            .rotationEffect(.degrees(heat.isExpanded ? 0 : 180))
            .frame(width: 28, height: 28)
        let title = VStack(alignment: .leading, spacing: 2) {
            Kicker(text: RadarHeatText.layerTitle)
            Text(RadarHeatText.punctualLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack { title; Spacer(minLength: 0); chevron }
                    number
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                    title
                    Spacer(minLength: Theme.Spacing.xs)
                    number
                    chevron
                }
            }
        }
        .contentShape(.rect)
    }

    // MARK: Details

    @ViewBuilder private func details(_ snapshot: HeatSnapshot) -> some View {
        let summary = snapshot.summary
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HeatLegend(summary: summary)
            let average = RadarHeatText.averageLine(summary)
            if !average.isEmpty {
                Text(average)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                topDelays(snapshot)
                hotspots(snapshot)
            }
            .id("heat.lists")
            HeatCellLegend(snapshot: snapshot)
            if heat.history.hasTrend, let caption = heat.history.caption {
                HeatSparkline(history: heat.history, caption: caption)
                    .id("heat.trend")
            }
            if !snapshot.isEmpty {
                // The map of the delay as an image (docs/RADAR_HEATMAP.md §6): the cells on a night-blue ground, no base map, no person.
                ShareLink(item: RadarHeatShare(cells: heat.drawnCells, summary: summary, date: Date()),
                          preview: SharePreview("Pünktlichkeit der Züge in Österreich",
                                                image: Image(systemName: "gauge.with.dots.needle.67percent"))) {
                    Label("Pünktlichkeitskarte teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            HeatNotes(model: model)
        }
    }

    private func topDelays(_ snapshot: HeatSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Größte Verspätungen jetzt")
                .accessibilityAddTraits(.isHeader)
            if snapshot.topDelays.isEmpty {
                Text(snapshot.summary.withRealtime > 0 ? "Gerade ist kein Zug 5 Minuten oder mehr verspätet." : "Noch keine Echtzeit-Daten.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            ForEach(snapshot.topDelays) { sample in
                HeatTrainRow(sample: sample, line: model.vehicle(id: sample.tripID)?.line, isEnabled: model.vehicle(id: sample.tripID) != nil) {
                    onTrain(sample.tripID)
                }
            }
        }
    }

    private func hotspots(_ snapshot: HeatSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Brennpunkte")
                .accessibilityAddTraits(.isHeader)
            if snapshot.hotspots.isEmpty {
                Text("Gerade kein Gebiet, in dem mindestens \(RadarHeat.minimumSample) Züge im Mittel 5 Minuten oder mehr verspätet sind.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            ForEach(snapshot.hotspots) { spot in
                HeatHotspotRow(spot: spot, isSelected: heat.selectedCell == spot.cellID) { onHotspot(spot) }
            }
        }
    }
}

/// "Stand vor 12 s": a view of its own, because the age ticks every second and only this line should be re-evaluated for it.
struct RadarHeatAge: View {
    var model: RadarModel

    var body: some View {
        let text: String
        if let age = model.status.oldestAnswerAge {
            text = "Stand \(RadarStatusText.age(age))"
        } else {
            text = model.load == .loading ? "Lade Züge …" : "Noch keine Daten"
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)   // the panel's summary carries the age
    }
}

// MARK: - Parts

/// The spoken summary with its age. A modifier of its own: the age changes every second, and only this node is re-evaluated for it,
/// not the whole panel.
private struct HeatSummaryLabel: ViewModifier {
    var model: RadarModel
    var summary: HeatSummary

    func body(content: Content) -> some View {
        content.accessibilityLabel(RadarHeatText.spokenSummary(summary, ageSeconds: model.status.oldestAnswerAge))
    }
}

/// What the numbers rest on and what is missing. A view of its own: it reads the radar's status, which changes every second.
struct HeatNotes: View {
    var model: RadarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.heatHasNoRail {
                Text(RadarHeatText.noRailNote).foregroundStyle(Theme.summitText)
            }
            if let incomplete = RadarHeatText.completenessNote(model.status) {
                Text(incomplete).foregroundStyle(Theme.summitText)
            }
            if model.filter.isActive {
                Text("Der Filter gilt für die Zugpunkte, nicht für die Pünktlichkeit: Sie rechnet mit allen geladenen Zügen.")
            }
            Text(RadarHeatText.methodNote)
            Text(RadarHeatText.areaNote)
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// How the cells of the map are coloured: a grey hatched cell has too few trains for a colour, and how many cells have one.
struct HeatCellLegend: View {
    var snapshot: HeatSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                HeatCellSwatch(blend: nil, isNeutral: true)
                    .frame(width: 18, height: 18)
                Text(RadarHeatText.neutralLegend)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let coverage = RadarHeatText.coverageLine(snapshot) {
                Text(coverage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The stacked bar: punctual, 5 to 15 minutes, more than 15, cancelled, each a share of the trains with realtime data.
struct HeatStackedBar: View {
    var summary: HeatSummary

    var body: some View {
        GeometryReader { proxy in
            let segments = summary.segments.filter { $0.count > 0 }
            let gap: CGFloat = 2
            let usable = max(0, proxy.size.width - gap * CGFloat(max(segments.count - 1, 0)))
            HStack(spacing: gap) {
                ForEach(segments) { segment in
                    Capsule()
                        .fill(segment.bucket.tint)
                        .frame(width: max(6, usable * segment.share))
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipShape(.capsule)
        }
        .frame(height: 10)
        .background(Capsule().fill(Theme.surfaceSecondary))
        .motionAnimation(Motion.smooth, value: summary)
    }
}

/// The four parts of the bar with their counts. Wraps; at the largest text sizes one per line.
struct HeatLegend: View {
    var summary: HeatSummary

    var body: some View {
        let buckets: [HeatBucket] = [.onTime, .delayed, .severe, .cancelled]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: Theme.Spacing.xs, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(buckets, id: \.self) { bucket in
                HStack(spacing: 6) {
                    Circle().fill(bucket.tint).frame(width: 9, height: 9)
                    Text(RadarHeatText.legend(bucket))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(count(bucket))")
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .numericValue(Double(count(bucket)))
                }
                .font(.footnote)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHidden(true)   // the panel's summary reads the same counts
    }

    private func count(_ bucket: HeatBucket) -> Int {
        switch bucket {
        case .onTime: summary.onTime
        case .delayed: summary.delayed
        case .severe: summary.severe
        case .cancelled: summary.cancelled
        case .noRealtime: summary.noRealtime
        }
    }
}

/// A train in a list: line plate, direction, delay. The delay is a number as well as a colour.
struct HeatTrainRow: View {
    var sample: HeatSample
    var line: Line?
    var isEnabled = true
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let row = RadarHeatText.trainRow(sample)
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) { plate(row.title); Spacer(minLength: 0); value(row.value) }
                        if !row.detail.isEmpty { detail(row.detail) }
                    }
                } else {
                    HStack(spacing: Theme.Spacing.xs) {
                        plate(row.title)
                        if !row.detail.isEmpty { detail(row.detail) }
                        Spacer(minLength: Theme.Spacing.xxs)
                        value(row.value)
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RadarHeatText.spokenTrain(sample))
        .accessibilityHint(isEnabled ? "Fahrt öffnen" : "")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private func plate(_ title: String) -> some View {
        if let line {
            PlannerLinePlate(line: line, size: .s)
        } else {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(sample.bucket.textTint)
            .lineLimit(1)
    }
}

/// A hot spot in the list: its number as on the map, the place, what its trains say. A tap opens its cell.
struct HeatHotspotRow: View {
    var spot: HeatHotspot
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                HeatHotspotBadge(spot: spot, isSelected: isSelected)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(RadarHeatText.place(spot.placeName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(RadarHeatText.hotspotDetail(spot))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brennpunkt \(spot.rank), \(RadarHeatText.place(spot.placeName)). \(RadarHeatText.hotspotDetail(spot))")
        .accessibilityHint("Züge dieses Gebiets anzeigen")
        .accessibilityAddTraits(.isButton)
    }
}

/// The trend of this session: national punctuality at the moments the radar had an answer (in memory, gone with the screen).
struct HeatSparkline: View {
    var history: HeatHistory
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let points = history.points
                let low = max(0, (points.map(\.share).min() ?? 0) - 0.03)
                let high = min(1, max((points.map(\.share).max() ?? 1) + 0.03, low + 0.1))
                let start = points.first?.at ?? Date()
                let span = max(history.span, 1)
                let coordinates = points.map { point in
                    CGPoint(x: proxy.size.width * point.at.timeIntervalSince(start) / span,
                            y: proxy.size.height * (1 - (point.share - low) / (high - low)))
                }
                ZStack {
                    Path { path in
                        guard let first = coordinates.first else { return }
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        for point in coordinates { path.addLine(to: point) }
                        if let last = coordinates.last { path.addLine(to: CGPoint(x: last.x, y: proxy.size.height)) }
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        guard let first = coordinates.first else { return }
                        path.move(to: first)
                        for point in coordinates.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = coordinates.last {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7).position(last)
                    }
                }
            }
            .frame(height: 34)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verlauf der Pünktlichkeit. \(caption)")
    }
}
