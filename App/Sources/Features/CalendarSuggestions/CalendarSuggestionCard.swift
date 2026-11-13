import SwiftUI
import KlimaCore

// MARK: calendarsuggestions – one „Termine mit Zugfahrt?“ card (docs/CALENDAR_SUGGESTIONS.md §2): a calendar tile with the day, the
// event's title and time, the place the location was matched to (never more than the data says: „Ort erkannt“ for a named station,
// „(ungefähr)“ for a town), the arrival as a small timeline („an 19:10 · 20 min · Termin 19:30“) with the buffer chips, and the three
// choices. VoiceOver: one element with the whole sentence and the three choices as actions; the buttons stay reachable too.

struct CalendarSuggestionCard: View {
    let suggestion: CalendarSuggestion
    let now: Date

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    /// This card's buffer (starts at the one from Einstellungen).
    @State private var buffer: Int

    init(suggestion: CalendarSuggestion, now: Date) {
        self.suggestion = suggestion
        self.now = now
        _buffer = State(initialValue: suggestion.bufferMinutes)
    }

    /// The suggestion with this card's buffer.
    private var current: CalendarSuggestion {
        var s = suggestion
        s.bufferMinutes = buffer
        return s
    }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                summary
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(CalendarText.spoken(current, now: now))
                    .accessibilityActions {
                        Button("Verbindung suchen") { CalendarActions(app: app).searchConnection(current) }
                        Button("Kein Zug") { CalendarActions(app: app).dismiss(suggestion) }
                        Button("Später") { CalendarActions(app: app).snooze(suggestion) }
                    }
                CalendarArrivalStrip(arrival: current.arrival, start: suggestion.start, bufferMinutes: buffer,
                                     station: CalendarText.station(suggestion.match.station.name))
                bufferChips
                actions
            }
        }
    }

    // MARK: Parts

    private var summary: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        return layout {
            CalendarDayTile(date: suggestion.start)
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title.isEmpty ? "Termin ohne Titel" : suggestion.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CalendarText.eventLine(suggestion, now: now))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                CalendarPlaceBadge(match: suggestion.match)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bufferChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Puffer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                chips
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Puffer vor dem Termin")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                chips
            }
        }
    }

    private var chips: some View {
        GlassSegmentedPicker(selection: $buffer, options: CalendarBuffer.options, tint: Theme.dawn) { minutes in
            Text("\(minutes) min")
                .monospacedDigit()
                .accessibilityLabel("\(minutes) Minuten Puffer")
        }
    }

    /// „Verbindung suchen“ on its own line, „Kein Zug“ and „Später“ side by side below it (stacked when they do not fit, AX5).
    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                CalendarActions(app: app).searchConnection(current)
            } label: {
                Label("Verbindung suchen", systemImage: "tram.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentTint)
            .accessibilityLabel("Verbindung nach \(CalendarText.station(suggestion.match.station.name)) suchen, Ankunft \(Format.time(current.arrival))")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) { secondaryButtons }
                VStack(spacing: Theme.Spacing.xs) { secondaryButtons }
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button {
            CalendarActions(app: app).dismiss(suggestion)
        } label: {
            Label("Kein Zug", systemImage: "xmark")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Kein Zug zu \(suggestion.title)")
        .accessibilityHint("Blendet den Vorschlag für diesen Termin aus")
        Button {
            CalendarActions(app: app).snooze(suggestion)
        } label: {
            Label("Später", systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Später erinnern an \(suggestion.title)")
    }
}

// MARK: - Day tile

/// A small calendar sheet: weekday band, the day in big rounded figures, the month.
struct CalendarDayTile: View {
    let date: Date

    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = 58

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.weekday(date))
                .font(.system(size: side * 0.19, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Theme.summitText)
                .padding(.top, side * 0.1)
            Text(Self.day(date))
                .font(.system(size: side * 0.44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.7)
            Text(Self.month(date))
                .font(.system(size: side * 0.16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, side * 0.1)
        }
        .lineLimit(1)
        .frame(width: side, height: side * 1.1)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.modeTile + 2, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.modeTile + 2, topTrailingRadius: Theme.Radius.modeTile + 2, style: .continuous)
                .fill(Theme.dawn.opacity(0.85))
                .frame(height: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.modeTile + 2, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private static let weekdayStyle = viennaStyle(Date.FormatStyle.dateTime.weekday(.abbreviated))
    private static let monthStyle = viennaStyle(Date.FormatStyle.dateTime.month(.abbreviated))

    private static func viennaStyle(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var s = style
        s.locale = Format.locale
        s.timeZone = Calendar.vienna.timeZone
        s.calendar = Calendar.vienna
        return s
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(weekdayStyle).replacingOccurrences(of: ".", with: "").uppercased(with: Format.locale)
    }

    static func day(_ date: Date) -> String { String(Calendar.vienna.component(.day, from: date)) }

    static func month(_ date: Date) -> String { date.formatted(monthStyle) }
}

// MARK: - Place badge

/// „✓ Ort erkannt: Linz Hbf“ (pine) or „⌖ Ort: Salzburg (ungefähr)“ (dawn) – symbol and words, never colour alone.
struct CalendarPlaceBadge: View {
    let match: CalendarPlaceMatch

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: match.precision == .station ? "checkmark.seal.fill" : "scope")
                .font(.caption.weight(.bold))
            Text(CalendarText.placeLine(match))
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(match.precision == .station ? Theme.positiveText : Theme.summitText)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background((match.precision == .station ? Theme.positive : Theme.dawn).opacity(0.13), in: .capsule)
    }
}

// MARK: - Arrival strip

/// „🚆 an 19:10 · Salzburg Hbf ───[20 min]─── ⚑ 19:30“: the train arrives, the buffer runs to the event. The buffer segment grows
/// from the flag towards the train when a chip changes (a scale, not a layout change).
struct CalendarArrivalStrip: View {
    let arrival: Date
    let start: Date
    let bufferMinutes: Int
    let station: String

    @Environment(\.dynamicTypeSize) private var typeSize

    /// 45 min fill the whole segment area; 10 min still show.
    private var fraction: CGFloat { CGFloat(bufferMinutes) / 45 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            rail
                .frame(height: 22)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { arrivalLabel; Spacer(minLength: Theme.Spacing.xs); eventLabel }
                VStack(alignment: .leading, spacing: 2) { arrivalLabel; eventLabel }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var rail: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let segmentArea = width * 0.42
            ZStack(alignment: .leading) {
                // The ride: dashed glacier line from the train to the arrival.
                Path { p in
                    p.move(to: CGPoint(x: 14, y: 11))
                    p.addLine(to: CGPoint(x: width - 12, y: 11))
                }
                .stroke(Theme.glacier.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                // The buffer: from the arrival dot to the flag, dawn, scaled by the chosen minutes.
                Capsule()
                    .fill(LinearGradient(colors: [Theme.dawn.opacity(0.55), Theme.dawn], startPoint: .leading, endPoint: .trailing))
                    .frame(width: segmentArea, height: 6)
                    .scaleEffect(x: max(fraction, 0.12), y: 1, anchor: .trailing)
                    .offset(x: width - 12 - segmentArea)
                    .motionAnimation(Motion.snappy, value: bufferMinutes)
                Image(systemName: "tram.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.modeColor(.train), in: .circle)
                Circle()
                    .fill(Theme.dawn)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Theme.snow, lineWidth: 2))
                    .offset(x: width - 12 - segmentArea * max(fraction, 0.12) - 5)
                    .motionAnimation(Motion.snappy, value: bufferMinutes)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.summitText)
                    .offset(x: width - 14)
            }
        }
    }

    private var arrivalLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("an")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Text(Format.time(arrival))
                .font(DashStyle.smallNumber)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
                .motionAnimation(Motion.number, value: bufferMinutes)
            Text(station)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ankunft \(station) um \(Format.time(arrival))")
    }

    private var eventLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(bufferMinutes) min")
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.summitText)
                .contentTransition(.numericText())
                .motionAnimation(Motion.number, value: bufferMinutes)
            Text("· Termin \(Format.time(start))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bufferMinutes) Minuten vor dem Termin um \(Format.time(start))")
    }
}

// MARK: - Follow-up card

/// „Warst du gefahren? Salzburg Hbf“ – the day after a suggested event without a logged trip there.
struct CalendarFollowUpCard: View {
    let followUp: CalendarFollowUpPlanner.FollowUp
    let now: Date

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    private var station: String { CalendarText.station(followUp.entry.stationName) }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.ctaGradient, in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Warst du gefahren?")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(station) · \(CalendarText.day(followUp.entry.arrival, now: now)), an \(Format.time(followUp.entry.arrival))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Warst du gefahren? \(station), \(CalendarText.day(followUp.entry.arrival, now: now))")
                .accessibilityActions {
                    Button("Fahrt erfassen") { CalendarActions(app: app).logTrip(followUp) }
                    Button("Nein") { CalendarActions(app: app).answerNo(followUp) }
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
                                                          : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
                layout {
                    Button {
                        CalendarActions(app: app).logTrip(followUp)
                    } label: {
                        Label("Fahrt erfassen", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.prominentTint)
                    .accessibilityLabel("Fahrt nach \(station) erfassen")
                    Button {
                        CalendarActions(app: app).answerNo(followUp)
                    } label: {
                        Text("Nein")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Nein, nicht nach \(station) gefahren")
                }
                .controlSize(.large)
            }
        }
    }
}
