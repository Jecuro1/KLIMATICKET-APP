import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Favourite chips

/// Star chips on top of the sheet ("★ St. Anton ⇄ Innsbruck Hbf"): one tap fills route, mode and direction.
/// Liquid Glass capsules in a GlassEffectContainer; the chip matching the current form is highlighted.
struct TripEdFavoritesRow: View {
    let model: TripEditorModel
    let favorites: [FavoriteRouteEntity]
    var onApply: (FavoriteRouteEntity) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(favorites) { favorite in
                        chip(favorite)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.Spacing.cardGutter, for: .scrollContent)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Favoriten")
    }

    private func chip(_ favorite: FavoriteRouteEntity) -> some View {
        let isSelected = model.tripEdMatches(favorite)
        let title = TripEdFormat.routeTitle(from: favorite.fromName, to: favorite.toName, roundTrip: favorite.isRoundTrip)
        return Button {
            onApply(favorite)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "star.fill" : "star")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(Theme.accent.opacity(0.2)).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityLabel(favorite.title.isEmpty ? title : "\(favorite.title), \(title)")
        .accessibilityValue(favorite.mode.displayName)
        .accessibilityHint("Übernimmt Strecke und Verkehrsmittel")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Date & time

/// "Datum" row with compact date and time picker pills (de-AT, 24 h).
struct TripEdDateCard: View {
    let model: TripEditorModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        label
                        pickers
                    }
                } else {
                    HStack(spacing: Theme.Spacing.s) {
                        label
                        Spacer(minLength: Theme.Spacing.xxs)
                        pickers
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 9)
        }
    }

    private var label: some View {
        TripEdRowLabel(symbol: "calendar", tint: Theme.alpenglow, title: "Datum", subtitle: dayHint)
    }

    /// Austrian time like everything else (list, ticket period, Format.time) – also when the iPhone is set elsewhere.
    /// Up to the end of today: a future trip would count towards the balance before it happened (an already saved later
    /// date stays selectable).
    private var pickers: some View {
        let latest = max(Self.endOfToday(), model.date)
        return HStack(spacing: 6) {
            DatePicker("Datum", selection: dateBinding, in: ...latest, displayedComponents: .date)
            DatePicker("Uhrzeit", selection: dateBinding, in: ...latest, displayedComponents: .hourAndMinute)
        }
        .labelsHidden()
        .datePickerStyle(.compact)
        .environment(\.locale, Format.locale)
        .environment(\.timeZone, Format.timeZone)
        .environment(\.calendar, TripListFormat.calendar)
        .tint(Theme.accent)
    }

    private static func endOfToday() -> Date {
        TripListFormat.calendar.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { model.date },
            set: { newValue in model.setDate(newValue) }
        )
    }

    /// "Heute", "Gestern" or the weekday ("Mittwoch").
    private var dayHint: String {
        let calendar = TripListFormat.calendar
        if calendar.isDateInToday(model.date) { return "Heute" }
        if calendar.isDateInYesterday(model.date) { return "Gestern" }
        var style = Date.FormatStyle.dateTime.weekday(.wide).locale(Format.locale)
        style.timeZone = Format.timeZone
        style.calendar = calendar
        return model.date.formatted(style)
    }
}

// MARK: - Tariff & details

/// Below the impact preview: class and Vorteilscard (both update the estimate), companions (KlimaTicket
/// Familie only), a note and "Als Favorit speichern" (hidden when editing).
struct TripEdDetailsCard: View {
    let model: TripEditorModel
    var showsCompanions: Bool
    var isExistingFavorite: Bool
    var focus: FocusState<TripEdField?>.Binding

    var body: some View {
        SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            VStack(spacing: 0) {
                classRow
                TripEdRowDivider()
                discountRow
                if showsCompanions {
                    TripEdRowDivider()
                    companionsRow
                }
                TripEdRowDivider()
                noteRow
                if !model.isEditing {
                    TripEdRowDivider()
                    favoriteRow
                }
            }
        }
    }

    // MARK: Rows

    private var classRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            TripEdRowLabel(symbol: "sofa.fill", tint: Theme.glacier, title: "Klasse")
            Spacer(minLength: Theme.Spacing.xs)
            Picker("Klasse", selection: classBinding) {
                Text("2. Kl.").tag(TravelClass.second)
                Text("1. Kl.").tag(TravelClass.first)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
    }

    private var discountRow: some View {
        Toggle(isOn: discountBinding) {
            TripEdRowLabel(symbol: "percent", tint: Theme.dusk, title: "Vorteilscard",
                           subtitle: model.isFareManual ? "Gilt nur für die Schätzung" : "Ermäßigter Normalpreis")
        }
        .tint(Theme.accent)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
    }

    private var companionsRow: some View {
        Stepper(value: companionsBinding, in: 0...8) {
            TripEdRowLabel(symbol: "figure.2.and.child.holdinghands", tint: Theme.pine,
                           title: model.companions == 0 ? "Mitfahrende" : "Mitfahrende: \(model.companions)",
                           subtitle: "Zählen nicht zum Wert der Fahrt")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
        .accessibilityValue("\(model.companions)")
    }

    private var noteRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            TripEdIconTile(symbol: "text.alignleft", tint: Theme.gold)
            TextField("Notiz hinzufügen", text: noteBinding, axis: .vertical)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...4)
                .focused(focus, equals: .note)
                .padding(.top, 5)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var favoriteRow: some View {
        if isExistingFavorite {
            HStack {
                TripEdRowLabel(symbol: "star.fill", tint: Theme.gold, title: "Schon ein Favorit",
                               subtitle: "Mit einem Tap auf der Übersicht erfassbar")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        } else {
            Toggle(isOn: favoriteBinding) {
                TripEdRowLabel(symbol: "star.fill", tint: Theme.gold, title: "Als Favorit speichern",
                               subtitle: "Für die Schnellerfassung auf der Übersicht")
            }
            .tint(Theme.accent)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 10)
        }
    }

    // MARK: Bindings (changes that affect the price re-run the estimate)

    private var classBinding: Binding<TravelClass> {
        Binding(
            get: { model.travelClass },
            set: { newValue in
                withAnimation(.snappy(duration: 0.3)) { model.setTravelClass(newValue) }
            }
        )
    }

    private var discountBinding: Binding<Bool> {
        Binding(
            get: { model.discount == .vorteilscard },
            set: { isOn in
                withAnimation(.snappy(duration: 0.3)) { model.setDiscount(isOn ? .vorteilscard : .none) }
            }
        )
    }

    private var companionsBinding: Binding<Int> {
        Binding(get: { model.companions }, set: { model.companions = $0 })
    }

    private var noteBinding: Binding<String> {
        Binding(get: { model.note }, set: { model.note = $0 })
    }

    private var favoriteBinding: Binding<Bool> {
        Binding(get: { model.saveAsFavorite }, set: { model.saveAsFavorite = $0 })
    }
}
