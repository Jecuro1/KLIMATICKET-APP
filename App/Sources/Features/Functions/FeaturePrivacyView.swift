import SwiftUI
import KlimaCore

// MARK: funktionen – Funktionen › Datenschutz (docs/FUNCTIONS_HUB.md §5): the live counters of this session (ÖBB-Auskunft,
// Ticketshop, VAO – in memory, from the launch, never a request's content), then every recipient outside the iPhone with what it
// gets, when, and whether that happens right now; at the end what never leaves the iPhone.

struct FeaturePrivacyView: View {
    /// CI scenes: fixed counters and the clock they were read at (the live session's counters otherwise).
    var demo: FeatureDemoCounters? = nil
    /// CI scene `featuresPrivacyBottom`: scrolled to the end.
    var screenshotScrollsToEnd = false

    @Environment(AppState.self) private var app
    @State private var counters: [LiveProvider: RequestCounters] = [:]

    private static let liveRecipients: [FeatureRecipient] = [.oebbTimetable, .oebbShop, .vao]
    private static let secondsStyle = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        .second(.twoDigits).locale(Locale(identifier: "de_AT"))

    var body: some View {
        ScrollViewReader { proxy in
            list
                .task {
                    guard screenshotScrollsToEnd else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo("local", anchor: .bottom)
                }
        }
    }

    private var list: some View {
        List {
            heroSection
            countersSection
            ForEach(Array(FeaturePrivacy.recipients().enumerated()), id: \.element.id) { index, entry in
                recipientSection(entry, header: index == 0 ? "Wer was bekommt" : nil)
            }
            localSection.id("local")
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Datenschutz")
        .navigationBarTitleDisplayMode(.large)
        .revealScope()
        .task { await poll() }
    }

    /// Reads the throttle's counters every second while the page is open (an actor read, no request).
    private func poll() async {
        if let demo {
            counters = demo.counters
            return
        }
        while !Task.isCancelled {
            let next = await app.live.requestCounters()
            if next != counters { withMotion(Motion.number) { counters = next } }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func counter(_ recipient: FeatureRecipient) -> RequestCounters {
        recipient.liveProvider.flatMap { counters[$0] } ?? .zero
    }

    // MARK: Hero

    private var heroSection: some View {
        let total = Self.liveRecipients.reduce(0) { $0 + counter($1).total }
        let minute = Self.liveRecipients.reduce(0) { $0 + counter($1).lastMinute }
        return Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Live-Anfragen seit dem Start")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: Double(total)) { "\(Int($0.rounded()))" }
                        .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text(minute == 1 ? "· 1 in der letzten Minute" : "· \(minute) in der letzten Minute")
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                        .numericValue(Double(minute))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(total) Live-Anfragen seit dem Start, \(minute) in der letzten Minute")
                Text("Gezählt wird, was wirklich rausging – an die ÖBB-Auskunft, den ÖBB-Ticketshop und die VAO.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .reveal(.focus, order: 0)
            .listRowBackground(Theme.surface)
        }
    }

    // MARK: Counters

    private var countersSection: some View {
        Section {
            ForEach(Self.liveRecipients) { recipient in
                FeatureCounterRow(recipient: recipient, counters: counter(recipient), lastText: counter(recipient).last.map { $0.formatted(Self.secondsStyle) },
                                  perMinute: recipient.liveProvider.map { RequestThrottle.budget(for: $0).perMinute } ?? 0)
                    .listRowBackground(Theme.surface)
            }
        } header: {
            SetSectionHeader(title: "Live-Zähler dieser Sitzung")
        } footer: {
            SetFooter(text: FeaturePrivacy.counterHonesty + " " + FeaturePrivacy.counterLifetime)
        }
    }

    // MARK: Recipients

    private func recipientSection(_ entry: FeaturePrivacyRecipient, header: String?) -> some View {
        let state = recipientState(entry.recipient)
        return Section {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                SetIconTile(symbol: entry.recipient.symbol, tint: entry.recipient.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.recipient.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: state.tone.symbol).font(.caption2.weight(.bold))
                        Text("Jetzt: \(state.text)").fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(state.tone.color)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .listRowBackground(Theme.surface)
            ForEach(entry.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(item.flow.sends)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Wann: \(item.flow.when)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .listRowBackground(Theme.surface)
            }
        } header: {
            if let header { SetSectionHeader(title: header) }
        }
    }

    /// Whether the recipient gets anything right now, from the switches as they are.
    private func recipientState(_ recipient: FeatureRecipient) -> (text: String, tone: FeatureStatusTone) {
        let center = FeatureCenter.shared
        let s = app.settings
        switch recipient {
        case .oebbTimetable, .oebbShop, .vao:
            let switchOn = recipient == .oebbTimetable ? s.liveTimetableEnabled : s.livePricesEnabled
            if center.offlineMode { return ("aus – Offline-Modus", .hidden) }
            if app.live.isDemo { return switchOn ? ("Beispieldaten – nichts wird gesendet", .on) : ("aus", .off) }
            switch app.live.consent {
            case .undecided: return ("wartet auf deine Zustimmung", .waiting)
            case .declined: return ("aus – Live-Daten abgelehnt", .off)
            case .granted: break
            }
            guard switchOn else { return ("aus", .off) }
            if app.live.config.killSwitch { return ("gerade abgeschaltet", .waiting) }
            return ("an – nur wenn du Live-Daten nutzt", .on)
        case .cloud:
            if app.auth.isSignedIn { return ("angemeldet – Sync an", .on) }
            return LogoPackStore.shared.userEnabled ? ("ohne Konto – nur Logo-Pakete", .on) : ("nichts", .off)
        case .github:
            if !s.autoUpdateCheck { return ("nur nach deinem Tipp", .off) }
            return center.offlineMode ? ("Tarife automatisch, Updates nur nach deinem Tipp", .waiting) : ("automatisch, höchstens alle paar Stunden", .on)
        case .appleMaps:
            return ("wenn eine Karte zu sehen ist", .on)
        case .device:
            return ("bleibt auf dem iPhone", .on)
        }
    }

    // MARK: Local

    private var localSection: some View {
        Section {
            AutoFlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                ForEach(FeaturePrivacy.localFeatures) { id in
                    HStack(spacing: 5) {
                        Image(systemName: id.symbol).font(.caption.weight(.semibold)).foregroundStyle(id.tint)
                        Text(id.title).font(.footnote.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSecondary, in: .capsule)
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nur auf dem iPhone: " + FeaturePrivacy.localFeatures.map(\.title).joined(separator: ", "))
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Bleibt auf dem iPhone")
        } footer: {
            SetFooter(text: FeaturePrivacy.networkLine + " " + FeaturePrivacy.consentLine)
        }
    }
}

/// One live provider: its counters as a sentence and the last minute against the app's limit per minute.
struct FeatureCounterRow: View {
    var recipient: FeatureRecipient
    var counters: RequestCounters
    var lastText: String?
    var perMinute: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                SetIconTile(symbol: recipient.symbol, tint: recipient.tint)
                Text(recipient.title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.xs)
                Text("\(counters.total)")
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(Double(counters.total))
            }
            Text(FeaturePrivacy.counterLine(counters, lastText: lastText))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
            if perMinute > 0 {
                FeatureMinuteMeter(used: counters.lastMinute, limit: perMinute, tint: recipient.tint)
                Text("Grenze der App: \(perMinute) pro Minute")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recipient.title)
        .accessibilityValue(FeaturePrivacy.counterLine(counters, lastText: lastText) + ". Grenze der App: \(perMinute) pro Minute")
    }
}

/// The last minute as a filled share of the app's limit (decorative; the sentence carries the number).
private struct FeatureMinuteMeter: View {
    var used: Int
    var limit: Int
    var tint: Color

    var body: some View {
        let fraction = limit > 0 ? min(1, Double(used) / Double(limit)) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceSecondary)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: used > 0 ? max(6, proxy.size.width * fraction) : 0)
            }
        }
        .frame(height: 6)
        .motionAnimation(Motion.smooth, value: used)
        .accessibilityHidden(true)
    }
}

/// Fixed counters for the CI scene (`featuresPrivacy`), made by a real `RequestThrottle` on a pinned clock.
struct FeatureDemoCounters {
    var counters: [LiveProvider: RequestCounters]
}
