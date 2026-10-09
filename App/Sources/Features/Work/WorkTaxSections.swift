import SwiftUI
import KlimaCore

// Cards of the "Arbeit & Steuer" screen. Copy: warm, precise, Du-Form; rules see KlimaCore/WorkTax.swift.

// MARK: - Jobticket & Arbeitgeberzuschuss

struct WorkJobticketCard: View {
    let data: WorkTaxData
    var onEditContribution: () -> Void

    @ScaledMetric(relativeTo: .title) private var percentSize: CGFloat = 34

    private var job: WorkTaxJobticket { data.job }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Jobticket & Zuschuss",
                                title: job.hasContribution ? "Dein Arbeitgeber zahlt \(Format.euro(job.employerContribution, decimals: 0)) mit"
                                                           : "Zahlt dein Arbeitgeber mit?") {
                    StatsInfoButton(title: "Jobticket", text: explanation)
                }
                if job.hasContribution {
                    contributionContent
                } else {
                    noContributionContent
                }
            }
        }
    }

    private var explanation: String {
        "Arbeitgeber dürfen dir das KlimaTicket ganz oder teilweise steuerfrei zur Verfügung stellen (§ 26 Z 5 lit. b EStG) – auch wenn du es privat nutzt. Der Zuschuss wird nicht versteuert. KlimaBilanz misst deine Bilanz dann an dem Teil, den du selbst bezahlst."
    }

    private var contributionContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            WorkSplitBar(parts: [
                .init(label: "Arbeitgeber", value: job.employerContribution,
                      detail: "\(Format.euro(job.employerContribution, decimals: 0)) · \(Format.percent(job.employerFraction))", color: Theme.glacier),
                .init(label: "Dein Eigenanteil", value: job.ownShare, detail: Format.euro(job.ownShare, decimals: 0), color: Theme.dawn),
            ])
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                payoffTile(value: job.amortizationOwnShare, caption: "rentiert, gemessen an deinem Eigenanteil", emphasized: true)
                payoffTile(value: job.amortizationFullPrice, caption: "wären es am vollen Ticketpreis", emphasized: false)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(job.ownShare > 0
                 ? "Überall in KlimaBilanz zählt, was du selbst bezahlt hast (\(Format.euro(job.ownShare, decimals: 0))) – deshalb rentiert sich dein Ticket schneller."
                 : "Dein Arbeitgeber übernimmt das ganze Ticket – jede Fahrt ist für dich reiner Gewinn.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onEditContribution) {
                Label("Zuschuss ändern", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .accessibilityHint("Öffnet die Eingabe des Arbeitgeberzuschusses")
        }
    }

    private func payoffTile(value: Double?, caption: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { Format.percent($0) } ?? "∞")
                .font(.system(size: percentSize, weight: emphasized ? .regular : .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(emphasized ? Theme.positive : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background((emphasized ? Theme.positive : Theme.textTertiary).opacity(emphasized ? 0.10 : 0.08),
                    in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var noContributionContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Viele Arbeitgeber übernehmen das KlimaTicket ganz oder teilweise – steuerfrei. Trag den Zuschuss ein: Dann misst KlimaBilanz die Bilanz an deinem Eigenanteil, und die Obergrenze für Dienstreisen passt automatisch.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onEditContribution) {
                Label("Zuschuss eintragen", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .accessibilityHint("Öffnet die Eingabe des Arbeitgeberzuschusses")
        }
    }
}

// MARK: - Dienstreisen

struct WorkBusinessTripsCard: View {
    let data: WorkTaxData
    let exports: WorkTaxExports
    var onAssign: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 46
    @State private var showsAll = false

    private var business: WorkTaxBusinessTrips { data.business }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Dienstreisen",
                                title: business.trips.isEmpty ? nil : WorkFormat.count(business.trips.count, "Dienstreise", "Dienstreisen")
                                    + " · \(Format.km(business.totalKm))") {
                    StatsInfoButton(title: "Dienstreisen mit eigenem Ticket", text: explanation)
                }
                if business.trips.isEmpty {
                    emptyContent
                } else {
                    amountHeader
                    capRail
                    if business.spansSeveralYears { yearChips }
                    WorkTripList(trips: Array(business.trips.reversed()), showsAll: $showsAll, valueTitle: "Einzelfahrschein")
                    WorkExportButtons(pdf: exports.businessPDF, csv: exports.businessCSV,
                                      pdfTitle: "Nachweis als PDF", previewTitle: "Dienstreise-Nachweis")
                    footnote
                }
            }
        }
    }

    private var explanation: String {
        "Nutzt du dein selbst bezahltes KlimaTicket für Dienstreisen, kannst du pro Fahrt die Kosten eines entsprechenden Einzelfahrscheins (2. Klasse, keine Sparschiene) geltend machen – insgesamt aber höchstens, was du selbst für das Ticket bezahlt hast. Ein steuerfreier Arbeitgeberzuschuss senkt diese Obergrenze (Beispiel der AK: €\u{00A0}1.400 − €\u{00A0}800 = €\u{00A0}600). Das gilt nur, soweit dein Arbeitgeber die Fahrten nicht ersetzt."
    }

    private var amountHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                WorkEuroNumeral(value: business.claimable, size: numeralSize, color: business.claimable > 0 ? Theme.positive : Theme.textPrimary)
                Text("absetzbar")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                if business.isCapped {
                    StatsBadge(text: "gedeckelt", symbol: "arrow.down.to.line", foreground: Theme.summitText, fill: Theme.summit.opacity(0.16))
                }
            }
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        if business.cap <= 0 {
            return "Dein Arbeitgeber zahlt das ganze Ticket – für Dienstreisen bleibt steuerlich nichts geltend zu machen."
        }
        if business.isCapped {
            return "Deine Einzelfahrscheine (\(Format.euro(business.total, decimals: 0))) übersteigen, was du selbst bezahlt hast – absetzbar sind höchstens \(Format.euro(business.cap, decimals: 0))."
        }
        return "Noch \(Format.euro(business.remainingCap, decimals: 0)) Spielraum bis zur Obergrenze – das ist dein selbst bezahlter Ticketpreis."
    }

    private var capRail: some View {
        ProgressRail(progress: business.capUsage,
                     leadingLabel: "\(Format.euro(business.total, decimals: 0)) Einzelfahrscheine",
                     trailingLabel: "max. \(Format.euro(business.cap, decimals: 0))",
                     height: 10,
                     fill: business.isCapped ? AnyShapeStyle(Theme.summit) : AnyShapeStyle(Theme.positive))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Obergrenze")
            .accessibilityValue("\(Format.euro(business.total, decimals: 0)) von höchstens \(Format.euro(business.cap, decimals: 0))")
    }

    private var yearChips: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(business.years) { year in
                HStack(spacing: 4) {
                    Text(String(year.year)).font(.caption.weight(.bold))
                    Text(Format.euro(year.claimable, decimals: 0)).font(.caption).monospacedDigit()
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.textTertiary.opacity(0.12), in: .capsule)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
    }

    private var footnote: some View {
        var text = "Bewertet mit dem Einzelfahrschein 2. Klasse je Richtung."
        if data.firstClassBusinessTrips > 0 { text += " 1.-Klasse-Fahrten zählen zum 2.-Klasse-Preis." }
        if business.spansSeveralYears { text += " Dein Ticketjahr reicht über den Jahreswechsel: Die Obergrenze ist chronologisch auf die Kalenderjahre verteilt." }
        return Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "suitcase.rolling.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent.gradient)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent.opacity(0.12), in: .circle)
                Text("Noch keine Dienstreisen")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Markiere Fahrten als „Dienstreise“ – beim Erfassen oder gleich hier. Daraus entsteht dein Nachweis fürs Finanzamt, gedeckelt auf deinen Eigenanteil von \(Format.euro(business.cap, decimals: 0)).")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAssign) {
                Label("Fahrten zuordnen", systemImage: "tag.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Pendlerpauschale

struct WorkPendlerCard: View {
    let data: WorkTaxData

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Pendlerpauschale",
                                title: data.job.hasContribution
                                    ? "Dein Pendlerpauschale sinkt um \(Format.euro(data.job.pendlerpauschaleReduction, decimals: 0))"
                                    : "Dein Pendlerpauschale bleibt ungekürzt")
                if data.commuteCount > 0 {
                    WorkFactRow(symbol: TripCategory.commute.symbolName, tint: Theme.glacier,
                                title: WorkFormat.count(data.commuteCount, "Arbeitsweg", "Arbeitswege") + " erfasst",
                                value: Format.euro(data.commuteValue, decimals: 0),
                                detail: "Normalpreis deiner Fahrten zur Arbeit in diesem Ticketjahr")
                }
                Text(data.job.hasContribution ? withContribution : withoutContribution)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: "https://pendlerrechner.bmf.gv.at/pendlerrechner/") {
                    Link(destination: url) {
                        Label("Anspruch prüfen: BMF-Pendlerrechner", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .accessibilityHint("Öffnet den Pendlerrechner des Finanzministeriums")
                }
            }
        }
    }

    private var withContribution: String {
        "Stellt dir dein Arbeitgeber das Ticket ganz oder teilweise steuerfrei zur Verfügung, wird ein allfälliges Pendlerpauschale um genau diesen Betrag gekürzt – der Pendlereuro bleibt. Beispiel des BMF: €\u{00A0}2.016 Pendlerpauschale − €\u{00A0}1.000 Zuschuss = €\u{00A0}1.016. Die tatsächlichen Fahrtkosten kannst du nicht zusätzlich absetzen."
    }

    private var withoutContribution: String {
        "Du zahlst dein Ticket selbst – ein allfälliges Pendlerpauschale und der Pendlereuro stehen dir ungekürzt zu. Die tatsächlichen Ticketkosten kannst du als Arbeitnehmer:in aber nicht zusätzlich absetzen. Ob und wie viel dir zusteht, rechnet der Pendlerrechner des BMF aus."
    }
}

// MARK: - Selbständige: Pauschale vs. Fahrtenbuch

struct WorkSelfEmployedCard: View {
    let data: WorkTaxData

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var amountSize: CGFloat = 30

    private var s: WorkTaxSelfEmployed { data.selfEmployed }

    var body: some View {
        @Bindable var settings = WorkSettings.shared
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Ticket als Betriebsausgabe", title: headline) {
                    StatsInfoButton(title: "Öffi-Ticket als Betriebsausgabe", text: explanation)
                }
                methodTiles
                    .fixedSize(horizontal: false, vertical: true)
                WorkSplitBar(parts: [
                    .init(label: "Betrieblich", value: s.businessKm, detail: Format.km(s.businessKm), color: Theme.glacier),
                    .init(label: "Privat", value: s.privateKm, detail: Format.km(s.privateKm), color: Theme.textTertiary.opacity(0.55)),
                ], height: 10)
                Toggle(isOn: $settings.countsCommuteAsBusiness.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wege zum Betrieb zählen betrieblich")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Fahrten mit dem Zweck „Arbeitsweg“")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                Text(basisText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headline: String {
        s.recommended == .logbook
            ? "Mit Fahrtenbuch absetzbar: \(Format.euro(s.logbookAmount, decimals: 0))"
            : "50 % pauschal absetzbar: \(Format.euro(s.flatRateAmount, decimals: 0))"
    }

    private var explanation: String {
        "Seit 2022 kannst du 50 % einer nicht übertragbaren Jahreskarte pauschal als Betriebsausgabe absetzen – ohne Aufzeichnungen, auch wenn du sie privat nutzt. 1.-Klasse-Tickets sind erfasst, der Familienaufschlag nicht (er ist privat). Nutzt du das Ticket zu mehr als 50 % betrieblich, kannst du stattdessen den betrieblichen Anteil laut Öffi-Fahrtenbuch ansetzen (WKO). Ob Wege zur Betriebsstätte betrieblich zählen, klärst du im Zweifel mit deiner Steuerberatung."
    }

    private var methodTiles: some View {
        let layout = typeSize >= .xxLarge ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
                                          : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        return layout {
            methodTile(title: "50 % pauschal", amount: s.flatRateAmount, detail: "ohne Aufzeichnungen",
                       isRecommended: s.recommended == .flatRate, isAvailable: true, symbol: "percent")
            methodTile(title: "Öffi-Fahrtenbuch", amount: s.logbookAmount,
                       detail: s.logbookApplies ? "\(Format.percent(s.businessShare)) betrieblich"
                                                : "erst ab über 50 % · derzeit \(Format.percent(s.businessShare))",
                       isRecommended: s.recommended == .logbook, isAvailable: s.logbookApplies, symbol: "book.closed.fill")
        }
    }

    private func methodTile(title: String, amount: Double, detail: String, isRecommended: Bool, isAvailable: Bool, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isRecommended ? Theme.positive : Theme.textSecondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(isAvailable ? Format.euro(amount, decimals: 0) : "–")
                .font(.system(size: amountSize, weight: isRecommended ? .regular : .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isRecommended ? Theme.positive : (isAvailable ? Theme.textPrimary : Theme.textTertiary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isRecommended {
                StatsBadge(text: "Mehr für dich", symbol: "checkmark", foreground: Theme.positiveText, fill: Theme.positive.opacity(0.16))
            }
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background((isRecommended ? Theme.positive : Theme.textTertiary).opacity(isRecommended ? 0.10 : 0.08),
                    in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous)
                .strokeBorder(isRecommended ? Theme.positive.opacity(0.45) : Color.clear, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isRecommended ? .isSelected : [])
    }

    private var basisText: String {
        var text = "Basis \(Format.euro(s.basis, decimals: 0)): Ticketpreis \(Format.euro(s.ticketPrice, decimals: 0))"
        if s.firstClassUpgrade > 0 { text += " + 1.-Klasse-Upgrade \(Format.euro(s.firstClassUpgrade, decimals: 0))" }
        if s.familySurcharge > 0 { text += " − Familienaufschlag \(Format.euro(s.familySurcharge, decimals: 0)) (privat)" }
        text += "."
        if data.isFamilyTicket, s.familySurcharge == 0 {
            text += " Den Familienaufschlag deines Tickets konnte KlimaBilanz nicht ermitteln – zieh ihn selbst ab."
        }
        if data.hasMixedExtras {
            text += " Deine Extras enthalten mehr als das 1.-Klasse-Upgrade – nur dieses zählt zur Pauschale, setz es bei Bedarf selbst an."
        }
        if data.uncategorisedCount > 0 {
            text += " \(WorkFormat.count(data.uncategorisedCount, "Fahrt hat", "Fahrten haben")) noch keinen Zweck und zählen als privat."
        }
        return text
    }
}

// MARK: - Öffi-Fahrtenbuch (self-employed)

struct WorkLogbookCard: View {
    let data: WorkTaxData
    let exports: WorkTaxExports
    var onAssign: () -> Void

    @State private var showsAll = false

    var body: some View {
        let countsCommute = WorkSettings.shared.countsCommuteAsBusiness
        let business = data.businessUse(countsCommute: countsCommute)
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Öffi-Fahrtenbuch",
                                title: "\(WorkFormat.count(data.trips.count, "Fahrt", "Fahrten")) · \(business.count) betrieblich")
                Text("Alle Fahrten des Ticketjahres mit Datum, Strecke, Kilometern und Zweck – als Nachweis für den betrieblichen Anteil.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if business.isEmpty {
                    Button(action: onAssign) {
                        Label("Betriebliche Fahrten zuordnen", systemImage: "tag.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    WorkTripList(trips: Array(business.reversed()), showsAll: $showsAll, valueTitle: "Normalpreis")
                }
                WorkExportButtons(pdf: exports.logbookPDF, csv: exports.logbookCSV,
                                  pdfTitle: "Fahrtenbuch als PDF", previewTitle: "Öffi-Fahrtenbuch")
            }
        }
    }
}

// MARK: - Shared rows & buttons

/// Compact trip lines (date · route · value), 4 visible, expandable.
struct WorkTripList: View {
    let trips: [WorkTaxTrip]
    @Binding var showsAll: Bool
    var valueTitle: String
    var collapsedCount = 4

    var body: some View {
        let visible = showsAll ? trips : Array(trips.prefix(collapsedCount))
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, trip in
                if index > 0 { Divider().overlay(Theme.separator).padding(.leading, 52) }
                WorkTripLine(trip: trip, valueTitle: valueTitle)
            }
            if trips.count > collapsedCount {
                Button {
                    withAnimation(.snappy) { showsAll.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showsAll ? "Weniger anzeigen" : "Alle \(trips.count) anzeigen")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showsAll ? 180 : 0))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct WorkTripLine: View {
    let trip: WorkTaxTrip
    var valueTitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            VStack(spacing: 0) {
                Text(StatsNames.shortMonth(trip.date).uppercased(with: Format.locale))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.summitText)
                Text(String(Calendar.vienna.component(.day, from: trip.date)))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 40, height: 42)
            .background(Theme.textTertiary.opacity(0.10), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(TripRow.short(trip.fromName)) \(trip.isRoundTrip ? "↔" : "→") \(TripRow.short(trip.toName))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.euroPrecise(trip.totalValue))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.date(trip.date, .long)), \(trip.fromName) nach \(trip.toName)\(trip.isRoundTrip ? ", hin und retour" : "")")
        .accessibilityValue("\(valueTitle) \(Format.euroPrecise(trip.totalValue))\(trip.note.isEmpty ? "" : ", \(trip.note)")")
    }

    /// "Zug · Projektbesprechung Landhaus" or "Zug · 202 km" (↔ in the route line marks hin & retour).
    private var caption: String {
        [trip.mode.displayName, trip.note.isEmpty ? Format.km(trip.totalKm) : trip.note].joined(separator: " · ")
    }
}

/// "Nachweis als PDF" + "CSV" share buttons (disabled while the files are being prepared).
struct WorkExportButtons: View {
    let pdf: URL?
    let csv: URL?
    var pdfTitle: String
    var previewTitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            shareButton(url: pdf, title: pdfTitle, symbol: "doc.richtext.fill", prominent: true)
            shareButton(url: csv, title: "CSV", symbol: "tablecells.fill", prominent: false)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func shareButton(url: URL?, title: String, symbol: String, prominent: Bool) -> some View {
        let label = Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: prominent ? .infinity : nil)
        if let url {
            if prominent {
                ShareLink(item: url, preview: SharePreview(previewTitle, image: Image(systemName: symbol))) { label }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            } else {
                ShareLink(item: url, preview: SharePreview("\(previewTitle) (CSV)", image: Image(systemName: symbol))) { label }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        } else {
            Button {} label: { label }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(true)
        }
    }
}
