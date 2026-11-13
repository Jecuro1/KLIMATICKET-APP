#if DEBUG
import SwiftUI
import WidgetKit
import KlimaCore

// MARK: smartwidgets – CI scenes of the Smart Stack track (`-KBScreenshot <screen> -KBDemo YES`, docs/WIDGETS_SMARTSTACK.md
// §7). The simulator cannot capture widgets, Live Activities or a paired watch, so these scenes draw the same SwiftUI views
// with demo data, no network and no system prompt. DEBUG builds only.
// - `widgetsPrivacy`: the gallery at "Gesperrt & privat" (switches and the locked preview, the defaults) ·
//   `widgetsPrivacyAmounts`: the section alone with amounts hidden too · `widgetsPrivacyAX5`: at the largest text size, `widgetsPrivacyAX5Bottom` scrolled to the switches
// - `widgetsAccessory`: every lock-screen family of every widget · `widgetsAccessoryLocked`: the same while locked
// - `liveActivitySmall`: the small Live Activity family as the Apple Watch Smart Stack shows it
// - `widgetsRelevance`: the Smart Stack scores of the demo timelines

struct SmartWidgetsScreenshotHost: View {
    static let screens: Set<String> = [
        "widgetsPrivacy", "widgetsPrivacyAmounts", "widgetsPrivacyAX5", "widgetsPrivacyAX5Bottom", "widgetsAccessory", "widgetsAccessoryLocked",
        "liveActivitySmall", "widgetsRelevance",
    ]

    let screen: String

    var body: some View {
        switch screen {
        case "widgetsAccessory", "widgetsAccessoryLocked":
            WidAccessoryCatalog(showsLocked: screen == "widgetsAccessoryLocked")
        case "liveActivitySmall":
            WidWatchActivityShowcase()
        case "widgetsRelevance":
            WidRelevanceList()
        case "widgetsPrivacy":
            // The real gallery (Einstellungen › Widgets), scrolled to the section.
            NavigationStack { WidgetGalleryView(screenshotSection: .privacy) }
        default:
            NavigationStack {
                ScrollView {
                    WidPrivacySection(snapshot: .sample,
                                      initialPrivacy: screen == "widgetsPrivacyAmounts"
                                          ? WidgetPrivacy(hidesRoutesWhenLocked: true, hidesAmountsWhenLocked: true) : nil)
                        .padding(.vertical, Theme.Spacing.m)
                }
                .scrollIndicators(.hidden)
                .background { AmbientBackground() }
                .navigationTitle("Widgets")
                .navigationBarTitleDisplayMode(.inline)
            }
            .defaultScrollAnchor(screen.hasSuffix("Bottom") ? .bottom : nil)
            .dynamicTypeSize(screen.hasPrefix("widgetsPrivacyAX5") ? .accessibility5 : .large)
        }
    }
}

// MARK: - Lock-screen families

/// Every widget in every lock-screen family it offers, on a night stage in the vibrant style. "neu" marks the variants
/// of this track. Locked: the marked texts as placeholders (routes hidden, amounts hidden as well, to show both).
private struct WidAccessoryCatalog: View {
    let showsLocked: Bool

    private let now = Date()
    private var snapshot: WidgetSnapshot { .sample }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: showsLocked ? "Sperrbildschirm · gesperrt" : "Sperrbildschirm")
                        .font(.title2.weight(.bold))
                    Text(verbatim: showsLocked ? "Strecken und Beträge verborgen" : "Alle Widgets in allen Größen · „neu“ aus diesem Update")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
                row("Nächste Verbindung") {
                    tile(.accessoryCircular, new: true) { NextConnectionWidgetView(title: "Pendeln", state: .fresh(now), items: connections, family: .accessoryCircular) }
                    tile(.accessoryRectangular) { NextConnectionWidgetView(title: "Pendeln", state: .fresh(now), items: connections, family: .accessoryRectangular) }
                }
                inline { NextConnectionWidgetView(title: "Pendeln", state: .fresh(now), items: connections, family: .accessoryInline) }
                row("Abfahrten") {
                    tile(.accessoryCircular, new: true) { DeparturesWidgetView(stationName: "Landeck-Zams", state: .fresh(now), items: departures, family: .accessoryCircular) }
                    tile(.accessoryRectangular) { DeparturesWidgetView(stationName: "Landeck-Zams", state: .fresh(now), items: departures, family: .accessoryRectangular) }
                }
                inline { DeparturesWidgetView(stationName: "Landeck-Zams", state: .fresh(now), items: departures, family: .accessoryInline) }
                row("Ticket-Restzeit") {
                    tile(.accessoryCircular) { TicketRemainingWidgetView(snapshot: snapshot, family: .accessoryCircular, now: now) }
                    tile(.accessoryRectangular, new: true) { TicketRemainingWidgetView(snapshot: snapshot, family: .accessoryRectangular, now: now) }
                }
                inline { TicketRemainingWidgetView(snapshot: snapshot, family: .accessoryInline, now: now) }
                row("Amortisation") {
                    tile(.accessoryCircular) { AmortizationWidgetView(snapshot: snapshot, family: .accessoryCircular) }
                    tile(.accessoryRectangular) { AmortizationWidgetView(snapshot: snapshot, family: .accessoryRectangular) }
                }
                inline(new: true) { AmortizationWidgetView(snapshot: snapshot, family: .accessoryInline) }
                inline(new: true) { AmortizationWidgetView(snapshot: paidSnapshot, family: .accessoryInline) }
                row("Break-even") {
                    tile(.accessoryCircular) { BreakEvenWidgetView(snapshot: snapshot, family: .accessoryCircular, now: now) }
                    tile(.accessoryRectangular) { BreakEvenWidgetView(snapshot: snapshot, family: .accessoryRectangular, now: now) }
                }
                inline { BreakEvenWidgetView(snapshot: snapshot, family: .accessoryInline, now: now) }
                row("Störungen · Gipfel") {
                    tile(.accessoryRectangular) { DisruptionsWidgetView(state: .fresh(now), items: WidSamples.disruptions, followedLines: ["S 4"], family: .accessoryRectangular) }
                    tile(.accessoryRectangular) { SummitWidgetView(snapshot: snapshot, family: .accessoryRectangular, now: now) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.white)
        .tint(Color.white)
        .environment(\.widNow, now)
        .environment(\.widPrivacy, WidgetPrivacy(hidesRoutesWhenLocked: true, hidesAmountsWhenLocked: true))
        .redacted(reason: showsLocked ? .privacy : [])
        .background {
            LinearGradient(colors: [Color(hex: "#1B2A4A"), Color(hex: "#0B1222")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
    }

    private var connections: [WidgetConnection] { WidSamples.connections(now: now) }
    private var departures: [WidgetDeparture] { WidSamples.departures(now: now) }

    /// The sample after the break-even (for the "Lohnt sich" line).
    private var paidSnapshot: WidgetSnapshot {
        var paid = WidgetSnapshot.sample
        paid.totalValue = 1_337
        paid.amortizedFraction = 1_337 / paid.ticketPrice
        paid.isPaidOff = true
        return paid
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .top, spacing: 14) { content() }
        }
    }

    private func tile<Content: View>(_ family: WidgetFamily, new: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
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
            .overlay(alignment: .topTrailing) { if new { newBadge.offset(x: 6, y: -6) } }
    }

    private func inline<Content: View>(new: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            if new { newBadge }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var newBadge: some View {
        Text(verbatim: "neu")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.gold))
            .environment(\.colorScheme, .light)
            .unredacted()
            .accessibilityLabel("Neu")
    }
}

// MARK: - Relevance

/// The Smart Stack scores of the demo timelines: when each entry starts, what it shows, and its score. The pinned clock
/// is today 07:00 (Vienna), the demo connections leave from 07:08 on.
private struct WidRelevanceList: View {
    private var now: Date { WidInsight.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(connectionRows, id: \.date) { row in
                        scoreRow(time: row.date, detail: row.detail, score: row.score)
                    }
                } header: {
                    Text("Nächste Verbindung")
                } footer: {
                    Text("100 ab 45 Minuten vor der nächsten Abfahrt, danach in fünf Minuten auf 0. Einträge nur aus dem Cache der App.")
                }
                Section {
                    ForEach(ticketRows, id: \.date) { row in
                        scoreRow(time: row.date, detail: row.detail, score: row.score, dayOnly: true)
                    }
                } header: {
                    Text("Ticket-Restzeit · Break-even")
                } footer: {
                    Text("Ticket-Restzeit 30 in den letzten 14 Tagen der Gültigkeit, Break-even 60 am Tag der Prognose. Die Reihung entscheidet iOS.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground() }
            .navigationTitle("Smart-Stack-Relevanz")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct Row { var date: Date; var detail: String; var score: Double }

    private var connectionRows: [Row] {
        let items = WidSamples.connections(now: now)
        let base = WidgetTimeline.entryDates(for: items, fetchedAt: now, now: now)
        let dates = WidgetRelevance.merged(base, WidgetRelevance.departureChangeDates(items.map(\.departureTime), now: now), limit: 16)
        return dates.map { date in
            let next = WidgetFilter.upcoming(items, now: date, limit: 1).first
            let detail = next.map { "\($0.lineName) \(WidFormat.clock($0.departureTime))" } ?? "keine Abfahrt mehr"
            return Row(date: date, detail: detail, score: WidgetRelevance.departure(now: date, nextDeparture: next?.departureTime))
        }
    }

    private var ticketRows: [Row] {
        let calendar = WidInsight.calendar
        let today = calendar.startOfDay(for: now)
        let validUntil = calendar.date(byAdding: DateComponents(day: 16, second: -1), to: today) ?? today
        let breakEven = calendar.date(byAdding: .day, value: 3, to: today)
        return (0..<18).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let ticket = WidgetRelevance.ticketRemaining(now: day, validUntil: validUntil, calendar: calendar)
            let flag = WidgetRelevance.breakEven(now: day, breakEvenDate: breakEven, calendar: calendar)
            let left = WidInsight.dayCount(from: day, to: validUntil)
            let validity = day > validUntil ? "abgelaufen" : (left > 0 ? "noch \(WidFormat.days(left))" : "letzter Tag")
            let detail = flag > 0 ? "\(validity) · Break-even" : validity
            return Row(date: day, detail: detail, score: max(ticket, flag))
        }
    }

    private func scoreRow(time: Date, detail: String, score: Double, dayOnly: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: dayOnly ? WidFormat.dayMonth(time) : WidFormat.clock(time))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .leading)
            Text(verbatim: detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Capsule()
                .fill(Theme.accent.opacity(0.18))
                .frame(width: 60, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.accent).frame(width: 60 * score / 100, height: 6)
                }
                .accessibilityHidden(true)
            Text(verbatim: String(Int(score.rounded())))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
