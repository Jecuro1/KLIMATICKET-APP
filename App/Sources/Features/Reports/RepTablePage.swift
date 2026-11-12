import SwiftUI
import KlimaCore

// Pages 3+ of "Dein KlimaTicket-Jahr": the trip table (split from RepReportPages.swift).

// MARK: - Pages 3+: trip table

struct RepTablePage: View {
    let data: RepReportData
    let lines: [ReportPagination.Line]
    var isFirst: Bool
    var isLast: Bool
    var number: Int
    var count: Int

    static let monthHeight: Double = 25
    static let tripHeight: Double = 15.5
    static let columnHeaderHeight: Double = 20
    static let firstHeaderHeight: Double = 64
    static let totalHeight: Double = 30
    static let kmColumn: CGFloat = 36
    static let valueColumn: CGFloat = 60

    /// Usable table height (below the column header) on the first and the following table pages.
    static var firstCapacity: Double { bodyHeight - firstHeaderHeight - columnHeaderHeight }
    static var pageCapacity: Double { bodyHeight - columnHeaderHeight }
    static var bodyHeight: Double {
        Double(RepPrint.pageSize.height - RepPrint.top - RepPrint.bottom - RepPrint.footerHeight) - 8
    }

    private var summary: SavingsSummary { data.summary }

    var body: some View {
        RepPrintPage(number: number, count: count) {
            VStack(alignment: .leading, spacing: 0) {
                if isFirst {
                    RepPrintSectionTitle(kicker: "Fahrtenbuch · \(data.yearLabel)", title: "Alle Fahrten",
                                         subtitle: "\(RepText.trips(summary.tripCount)) · \(Format.km(summary.distanceKm)) · \(Format.euroPrecise(summary.totalValue)) Fahrtenwert")
                        .frame(height: Self.firstHeaderHeight, alignment: .topLeading)
                }
                columnHeader
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    switch line {
                    case .month(let start, let trips, let value, let km, let continued):
                        monthRow(start: start, trips: trips, value: value, km: km, continued: continued)
                    case .trip(let trip):
                        tripRow(trip, zebra: index % 2 == 0)
                    }
                }
                if isLast {
                    totalRow
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Datum").frame(width: 38, alignment: .leading)
            Text("Strecke").frame(maxWidth: .infinity, alignment: .leading)
            Text("Verkehrsmittel").frame(width: 78, alignment: .leading)
            Text("km").frame(width: Self.kmColumn, alignment: .trailing)
            Text("Wert").frame(width: Self.valueColumn, alignment: .trailing)
        }
        .font(RepPrint.font(6.5, .semibold))
        .tracking(0.4)
        .lineLimit(1)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: Self.columnHeaderHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.textPrimary.opacity(0.5)).frame(height: 0.6) }
    }

    private func monthRow(start: Date, trips: Int, value: Double, km: Double, continued: Bool) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(StatsNames.wideMonth(start)) \(String(Calendar.vienna.component(.year, from: start)))\(continued ? " (Fortsetzung)" : "")")
                .font(RepPrint.font(9, .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            if !continued {
                Text("\(RepText.trips(trips)) · \(Format.km(km)) · \(Format.euroPrecise(value))")
                    .font(RepPrint.font(7.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(Theme.glacier.opacity(0.09), in: .rect(cornerRadius: 5, style: .continuous))
        .frame(height: Self.monthHeight, alignment: .bottom)
        .padding(.bottom, 0)
    }

    private func tripRow(_ trip: TripRecord, zebra: Bool) -> some View {
        HStack(spacing: 8) {
            Text(RepText.shortNumericDate(trip.date))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 38, alignment: .leading)
            HStack(spacing: 4) {
                Text("\(trip.fromName) → \(trip.toName)")
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let via = ViaText.subtitle(trip.via) {   // MARK: via – "über Feldkirch" after the route, first to shrink
                    Text(via)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
                if trip.isRoundTrip {
                    Text("H+R")
                        .font(RepPrint.font(6, .bold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Theme.glacier.opacity(0.12), in: .capsule)
                }
                if trip.isInduced {
                    Image(systemName: "sparkle")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Theme.alpenglow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Circle().fill(Theme.modeColor(trip.mode)).frame(width: 5, height: 5)
                Text(trip.mode.displayName)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 78, alignment: .leading)
            Text(trip.totalDistanceKm > 0 ? Format.number(trip.totalDistanceKm, decimals: trip.totalDistanceKm < 10 ? 1 : 0) : "–")
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Self.kmColumn, alignment: .trailing)
            Text(Format.euroPrecise(trip.totalValue))
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Self.valueColumn, alignment: .trailing)
        }
        .font(RepPrint.font(8))
        .padding(.horizontal, 8)
        .frame(height: Self.tripHeight)
        .background(zebra ? RepPrint.zebra : Color.white)
    }

    private var totalRow: some View {
        HStack(spacing: 8) {
            Text("Summe · \(RepText.trips(summary.tripCount))")
                .frame(maxWidth: .infinity, alignment: .leading)
            // Same column widths as the trip rows, so km and value line up with the columns above.
            Text(Format.number(summary.distanceKm))
                .frame(width: Self.kmColumn, alignment: .trailing)
            Text(Format.euroPrecise(summary.totalValue))
                .frame(width: Self.valueColumn, alignment: .trailing)
        }
        .font(RepPrint.font(9, .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .monospacedDigit()
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .overlay(alignment: .top) { Rectangle().fill(Theme.textPrimary.opacity(0.5)).frame(height: 0.6) }
        .padding(.top, 8)
    }
}
