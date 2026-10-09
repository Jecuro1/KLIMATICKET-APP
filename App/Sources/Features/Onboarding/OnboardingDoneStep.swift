import SwiftUI
import KlimaCore

/// Step 6 – celebration: brand mark with a check that pops in, the ticket as companion card (tilt sheen) and a summary
/// of price, cost per day and validity. "Los geht’s" lives in the flow footer.
///
/// Motion (docs/MOTION.md §11): a short, on-system celebration instead of a long confetti rain – the brand mark pops and
/// lifts, a ring and a burst of dots leave the check (≈ 0.7 s, no haptic of its own: the page change already tapped and
/// "Los geht’s" ends with the toast's success). The ticket is dealt in, "Pro Tag" counts in. First visit only;
/// Reduce Motion: fades only.
struct OnbDoneStep: View {
    var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.onbFirstVisit) private var firstVisit
    @State private var appeared = MotionPolicy.isStatic
    @State private var celebration = 0
    @State private var tilt = MotionTilt()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                hero
                ticketPreview
                summaryCard
                    .onbReveal(order: 4)
                if let trips = model.commuteBreakEvenTrips,
                   let from = model.homeStation, let to = model.commuteDestination {
                    commuteNote(trips: trips, from: from, to: to)
                        .onbReveal(order: 5)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .revealScope()
        .onAppear {
            if !reduceMotion { tilt.start() }
            guard !appeared else { return }
            guard firstVisit else {
                appeared = true
                return
            }
            withMotion(Motion.bouncy) { appeared = true }
            guard !reduceMotion else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))   // the check has popped in
                celebration += 1
            }
        }
        .onDisappear {
            if !reduceMotion { tilt.stop() }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack(alignment: .bottomTrailing) {
                OnbBrandMark(size: 84)
                    .celebrate(trigger: celebration, haptic: nil)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Theme.positive)
                    .symbolEffect(.bounce, value: celebration)
                    .celebrationRing(trigger: celebration, color: Theme.positive)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.2)
                    .opacity(appeared ? 1 : 0)
                    .offset(x: 10, y: 10)
            }
            .celebrationBurst(trigger: celebration)
            .padding(.bottom, Theme.Spacing.xs)
            .accessibilityHidden(true)

            Text("Alles bereit!")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .onbReveal(.focus, order: 1)
            Text("Dein Weg zum Gipfel beginnt jetzt. Erfasse deine Fahrten – wir zeigen dir, wann sich dein Ticket rentiert.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onbReveal(order: 2)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    // MARK: Ticket

    private var ticketPreview: some View {
        TicketCard(title: model.ticketName,
                   subtitle: model.ticketSubtitle,
                   holder: model.holderName.trimmingCharacters(in: .whitespaces),
                   validFrom: model.startDate,
                   validUntil: model.endDate,
                   ticketNumber: model.ticketNumber.trimmingCharacters(in: .whitespaces),
                   theme: .twilight, // = the theme the new TicketEntity gets (themeRaw default "twilight")
                   roll: tilt.roll,
                   pitch: tilt.pitch)
            // Dealt onto the table: tips up out of a slight tilt and settles (Reduce Motion: fades in).
            .rotation3DEffect(.degrees(appeared || reduceMotion ? 0 : 16), axis: (x: 1, y: 0, z: 0))
            .offset(y: appeared || reduceMotion ? 0 : 36)
            .opacity(appeared ? 1 : 0)
            .motionAnimation(Motion.gentle.delay(0.12), value: appeared)
            .padding(.horizontal, Theme.Spacing.xxs)
    }

    // MARK: Summary

    private var summaryCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    priceStat
                    perDayStat
                    validUntilStat
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    priceStat
                    perDayStat
                    validUntilStat
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var priceStat: some View {
        stat(label: "Ticketpreis", value: Format.euro(model.price), symbol: "eurosign.circle.fill", tint: Theme.summit)
    }

    /// The page's one count-in: what the ticket costs per day of validity. The final figure reserves the width, so the
    /// summary never flips between its row and stacked layouts while counting.
    private var perDayStat: some View {
        stat(label: "Pro Tag", value: Format.euroPrecise(model.costPerDay), symbol: "calendar", tint: Theme.accent) { final in
            Text(final)
                .hidden()
                .overlay(alignment: .leading) {
                    CountUpText(value: model.costPerDay, delay: 0.35) { Format.euroPrecise($0) }
                }
        }
    }

    private var validUntilStat: some View {
        stat(label: "Gültig bis", value: Format.date(model.endDate), symbol: "flag.fill", tint: Theme.positive)
    }

    private func stat(label: String, value: String, symbol: String, tint: Color) -> some View {
        stat(label: label, value: value, symbol: symbol, tint: tint) { Text($0) }
    }

    private func stat<Value: View>(label: String, value: String, symbol: String, tint: Color,
                                   @ViewBuilder figure: (String) -> Value) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            figure(value)
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commuteNote(trips: Int, from: Station, to: Station) -> some View {
        GlassCard(padding: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                OnbIconTile(symbol: "star.fill", tint: Theme.gold, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Favorit „Pendeln“ wird angelegt")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(TripRow.short(from.name)) → \(TripRow.short(to.name)) · rentiert nach ca. \(trips) \(model.commuteRoundTrip ? "Hin- & Rückfahrten" : "Fahrten")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
