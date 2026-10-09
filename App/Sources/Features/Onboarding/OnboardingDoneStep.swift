import SwiftUI
import KlimaCore

/// Step 6 – celebration: brand mark with a bouncing check, confetti, the ticket as companion card
/// (tilt sheen) and a summary of price, cost per day and validity. "Los geht’s" lives in the flow footer.
struct OnbDoneStep: View {
    var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = LaunchMode.isScreenshot
    @State private var showsConfetti = false
    @State private var tilt = MotionTilt()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                hero
                ticketPreview
                summaryCard
                if let trips = model.commuteBreakEvenTrips,
                   let from = model.homeStation, let to = model.commuteDestination {
                    commuteNote(trips: trips, from: from, to: to)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .overlay {
            if showsConfetti {
                ConfettiView(colors: Theme.celebrationColors, count: 70)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            if !reduceMotion { tilt.start() }
            guard !appeared else { return }
            withAnimation(.spring(duration: 0.8, bounce: 0.28)) { appeared = true }
            if !reduceMotion { showsConfetti = true }
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Theme.positive)
                    .symbolEffect(.bounce, value: appeared)
                    .scaleEffect(appeared ? 1 : 0.2)
                    .opacity(appeared ? 1 : 0)
                    .offset(x: 10, y: 10)
            }
            .padding(.bottom, Theme.Spacing.xs)
            .accessibilityHidden(true)

            Text("Alles bereit!")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Dein Weg zum Gipfel beginnt jetzt. Erfasse deine Fahrten – wir zeigen dir, wann sich dein Ticket rentiert.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
                   theme: .aurora,
                   roll: tilt.roll,
                   pitch: tilt.pitch)
            .rotation3DEffect(.degrees(appeared ? 0 : 16), axis: (x: 1, y: 0, z: 0))
            .offset(y: appeared ? 0 : 36)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.9, bounce: 0.25).delay(0.1), value: appeared)
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

    private var perDayStat: some View {
        stat(label: "Pro Tag", value: Format.euroPrecise(model.costPerDay), symbol: "calendar", tint: Theme.accent)
    }

    private var validUntilStat: some View {
        stat(label: "Gültig bis", value: Format.date(model.endDate), symbol: "flag.fill", tint: Theme.positive)
    }

    private func stat(label: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            Text(value)
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
