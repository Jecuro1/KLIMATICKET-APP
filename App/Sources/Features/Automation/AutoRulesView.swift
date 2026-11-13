import SwiftUI
import UIKit
import UserNotifications
import KlimaCore

// MARK: automation – Einstellungen › Automatik (docs/AUTOMATION.md §5): the master switch with the active rules and the 16 places,
// the rules as sentences with their next moment, six templates to switch on, „Zuletzt ausgelöst“, and the honest promise:
// rules run only while the app is open or when iOS delivers a notice planned in advance.

struct AutoRulesView: View {
    /// Opened from a notice's „Regel ansehen“ (own sheet with a „Fertig“ button).
    var isSheet = false
    /// CI scene `automationBudget`: the list opens scrolled to nothing but the top.
    var screenshotOpensEditor: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: AutoEditorRequest?
    @State private var pendingDelete: AutoRule?
    @State private var changeTick = 0

    private var store: AutoStore { .shared }
    private var runner: AutoRunner { .shared }

    var body: some View {
        List {
            heroSection
            noticeSection
            rulesSection
            templatesSection
            logSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Automatik")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
        .revealScope()
        .motionAnimation(Motion.smooth, value: store.book.isEnabled)
        .motionAnimation(Motion.smooth, value: store.book.rules.map(\.id))
        .haptic(.selection, trigger: changeTick)
        .sheet(item: $editing) { request in
            NavigationStack {
                AutoRuleEditorView(rule: request.rule, isNew: request.isNew)
            }
        }
        .confirmationDialog("Regel löschen?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { rule in
            Button("Löschen", role: .destructive) { delete(rule) }
        } message: { rule in
            Text("„\(rule.name)“ und ihre geplanten Mitteilungen werden entfernt. Das Protokoll bleibt.")
        }
        .task { await runner.refreshForScreen() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the iOS settings: the permission may have changed.
            if phase == .active { Task { await runner.refreshForScreen() } }
        }
        .onAppear {
            if let id = screenshotOpensEditor, let rule = store.rule(id) { editing = AutoEditorRequest(rule: rule, isNew: false) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                editing = AutoEditorRequest(rule: AutoRule(name: "", trigger: AutoTriggerKind.dayWithoutTrip.defaultTrigger, createdAt: store.now()),
                                            isNew: true)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Neue Regel")
            .disabled(store.book.rules.count >= AutoRuleBook.maxRules)
        }
        if isSheet {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        Section {
            AutoHeroCard(isEnabled: Binding(get: { store.book.isEnabled }, set: setMaster),
                         activeCount: store.book.isEnabled ? store.book.rules.filter(\.isEnabled).count : 0,
                         nextText: nextText,
                         used: runner.plan.slots.count,
                         waiting: runner.plan.overflow.count)
                .reveal(order: 0)
                .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: AutoText.honestyLine + " Sie schreiben nie Fahrten und fragen nichts im Netz ab.")
        }
    }

    /// „nächste: heute 19:00 · Abendcheck“ – the soonest planned notice of all rules.
    private var nextText: String? {
        guard store.book.isEnabled, let slot = runner.plan.slots.first else { return nil }
        return "Nächste Mitteilung \(AutoText.whenShort(slot.fireAt, now: store.now(), calendar: .vienna)) · \(slot.ruleName)"
    }

    // MARK: Notices

    @ViewBuilder
    private var noticeSection: some View {
        let lines = notices
        if !lines.isEmpty {
            Section {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label {
                            Text(line.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: line.symbol).foregroundStyle(line.tint)
                        }
                        if line.opensSettings {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            } label: {
                                Label("Einstellungen öffnen", systemImage: "gear").font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Theme.surface)
                }
            }
            .motionTransition(.rise)
        }
    }

    private struct NoticeLine: Identifiable {
        let id: String
        let symbol: String
        let tint: Color
        let text: String
        var opensSettings = false
    }

    private var notices: [NoticeLine] {
        var lines: [NoticeLine] = []
        let hasActive = store.book.isEnabled && store.book.rules.contains(where: \.isEnabled)
        if !store.book.isEnabled {
            lines.append(NoticeLine(id: "off", symbol: "pause.circle.fill", tint: Theme.textSecondary,
                                    text: "Automatik ist aus. Keine Regel löst aus, und nichts ist geplant. Deine Regeln bleiben erhalten."))
        }
        if hasActive {
            switch runner.authorization {
            case .denied:
                lines.append(NoticeLine(id: "denied", symbol: "bell.slash.fill", tint: Theme.negativeText,
                                        text: "Mitteilungen sind in iOS aus. Regeln melden sich dann nur, solange die App offen ist.",
                                        opensSettings: true))
            case .notDetermined:
                lines.append(NoticeLine(id: "ask", symbol: "questionmark.circle", tint: Theme.textSecondary,
                                        text: "iOS fragt nach der Erlaubnis für Mitteilungen, sobald du eine Regel einschaltest."))
            default:
                break
            }
        }
        if store.book.isEnabled, let warning = runner.budgetWarning {
            lines.append(NoticeLine(id: "budget", symbol: "tray.full.fill", tint: Theme.summitText, text: warning))
        }
        if runner.refusedCount > 0 {
            lines.append(NoticeLine(id: "refused", symbol: "exclamationmark.triangle.fill", tint: Theme.summitText,
                                    text: "iOS hat \(runner.refusedCount) geplante Mitteilungen nicht angenommen. Andere Erinnerungen belegen vermutlich die Plätze (siehe Alle Alarme)."))
        }
        return lines
    }

    // MARK: Rules

    private var rulesSection: some View {
        Section {
            if store.book.rules.isEmpty {
                Label {
                    Text("Noch keine Regel. Schalte unten eine Vorlage ein – oder bau mit + deine eigene.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "wand.and.sparkles").foregroundStyle(Theme.dusk)
                }
                .listRowBackground(Theme.surface)
            }
            ForEach(Array(store.book.rules.enumerated()), id: \.element.id) { index, rule in
                AutoRuleRow(rule: rule, isMasterOn: store.book.isEnabled, nextLine: runner.nextLine(rule),
                            open: { editing = AutoEditorRequest(rule: rule, isNew: false) },
                            toggle: { on in setEnabled(rule, on) })
                    .reveal(order: index + 1)
                    .listRowBackground(Theme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = rule } label: { Label("Löschen", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { duplicate(rule) } label: { Label("Duplizieren", systemImage: "plus.square.on.square") }
                            .tint(Theme.glacier)
                    }
                    .contextMenu {
                        Button("Bearbeiten", systemImage: "pencil") { editing = AutoEditorRequest(rule: rule, isNew: false) }
                        Button("Duplizieren", systemImage: "plus.square.on.square") { duplicate(rule) }
                        Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = rule }
                    }
            }
        } header: {
            SetSectionHeader(title: "Deine Regeln")
        } footer: {
            if !store.book.rules.isEmpty {
                SetFooter(text: "Tippe auf eine Regel für Testlauf und Details. Wischen löscht oder dupliziert.")
            }
        }
    }

    // MARK: Templates

    private var templatesSection: some View {
        Section {
            ForEach(AutoTemplates.all) { template in
                Toggle(isOn: Binding(get: { isOn(template) }, set: { setTemplate(template, $0) })) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                            Text(template.subtitle)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        if let kind = template.kind {
                            AutoKindTile(kind: kind, isOn: true, size: 30)
                        } else {
                            SetIconTile(symbol: "moon.zzz.fill", tint: Theme.glacier)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        } header: {
            SetSectionHeader(title: "Vorlagen")
        } footer: {
            SetFooter(text: "Eine Vorlage legt eine Regel an, die du danach unter „Deine Regeln“ anpasst. „Wochenende ruhig“ gilt für alle Regeln; eine Erinnerung vor Ablauf kommt dann schon am Freitag.")
        }
    }

    private func isOn(_ template: AutoTemplate) -> Bool {
        if template.id == AutoTemplates.quietWeekendID { return store.book.quietWeekend }
        return store.rule(template: template.id)?.isEnabled ?? false
    }

    private func setTemplate(_ template: AutoTemplate, _ on: Bool) {
        changeTick += 1
        withMotion(Motion.smooth) {
            if template.id == AutoTemplates.quietWeekendID {
                store.setQuietWeekend(on)
            } else if let existing = store.rule(template: template.id) {
                store.setEnabled(existing.id, on, ticket: runner.currentTicket)
            } else if on, let rule = template.makeRule(now: store.now()) {
                store.save(rule, ticket: runner.currentTicket)
            }
        }
        runner.rulesChanged(asksPermission: on)
    }

    // MARK: Log

    private var logSection: some View {
        Section {
            NavigationLink {
                AutoLogView()
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    SetRowLabel(title: "Zuletzt ausgelöst", subtitle: logSubtitle, symbol: "clock.arrow.circlepath", tint: Theme.dusk)
                    Spacer(minLength: Theme.Spacing.xs)
                    if !store.log.entries.isEmpty {
                        Text("\(store.log.entries.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .numericValue(Double(store.log.entries.count))
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Regeln, Protokoll und was sie sich merken liegen nur auf diesem iPhone. Nichts davon wird synchronisiert.")
        }
    }

    private var logSubtitle: String {
        guard let last = store.log.entries.first else { return "Noch nichts – hier steht, was zuletzt passiert ist" }
        return "\(last.title) · \(AutoText.whenShort(last.at, now: store.now(), calendar: .vienna))"
    }

    // MARK: Actions

    private func setMaster(_ on: Bool) {
        changeTick += 1
        withMotion(Motion.smooth) { store.setMaster(on) }
        runner.rulesChanged(asksPermission: on)
    }

    private func setEnabled(_ rule: AutoRule, _ on: Bool) {
        changeTick += 1
        withMotion(Motion.snappy) { store.setEnabled(rule.id, on, ticket: runner.currentTicket) }
        runner.rulesChanged(asksPermission: on)
    }

    private func duplicate(_ rule: AutoRule) {
        var copy = rule
        copy.id = UUID()
        copy.name = String((rule.name + " (Kopie)").prefix(AutoRule.maxNameLength))
        copy.templateID = nil
        copy.createdAt = store.now()
        withMotion(Motion.smooth) { store.save(copy, ticket: runner.currentTicket) }
        runner.rulesChanged(asksPermission: copy.isEnabled)
    }

    private func delete(_ rule: AutoRule) {
        withMotion(Motion.smooth) { store.delete(rule.id) }
        runner.rulesChanged(asksPermission: false)
    }
}

/// The editor's input: a copy of the rule, and whether it is a new one.
struct AutoEditorRequest: Identifiable {
    let rule: AutoRule
    let isNew: Bool
    var id: UUID { rule.id }
}

/// The top of the screen: master switch, how many rules are on, the next notice and the 16 places.
struct AutoHeroCard: View {
    @Binding var isEnabled: Bool
    var activeCount: Int
    var nextText: String?
    var used: Int
    var waiting: Int

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // At accessibility sizes the title gets the full width under the icon and the switch.
            if typeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    badge
                    Spacer(minLength: Theme.Spacing.xs)
                    toggle
                }
                title
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    badge
                    title
                    Spacer(minLength: Theme.Spacing.xs)
                    toggle
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) { count; next }
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) { count; next }
            }
            AutoBudgetBar(used: isEnabled ? used : 0, waiting: isEnabled ? waiting : 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .opacity(isEnabled ? 1 : 0.85)
    }

    private var badge: some View {
        Image(systemName: "wand.and.sparkles")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(Theme.ctaGradient, in: .rect(cornerRadius: 16, style: .continuous))
            .symbolBounce(on: isEnabled)
            .accessibilityHidden(true)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Wenn … dann …")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityAddTraits(.isHeader)
            Text("Deine Regeln auf dem iPhone")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var toggle: some View {
        Toggle("Automatik", isOn: $isEnabled)
            .labelsHidden()
            .accessibilityLabel("Automatik")
    }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            CountUpText(value: Double(activeCount)) { "\(Int($0.rounded()))" }
                .font(Theme.Typography.numberLarge)
                .foregroundStyle(Theme.textPrimary)
            Text(activeCount == 1 ? "Regel aktiv" : "Regeln aktiv")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(activeCount == 1 ? "1 Regel aktiv" : "\(activeCount) Regeln aktiv")
    }

    @ViewBuilder
    private var next: some View {
        if let nextText {
            Text(nextText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }
}

/// One rule: its icon, its name, the rule as a sentence and its next moment; the switch on the right. A tap opens the editor.
struct AutoRuleRow: View {
    let rule: AutoRule
    var isMasterOn: Bool
    var nextLine: String
    var open: () -> Void
    var toggle: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let isLive = rule.isEnabled && isMasterOn
        Group {
            // At accessibility sizes the switch sits next to the icon, so the sentence keeps the whole width.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        AutoKindTile(kind: rule.trigger.kind, isOn: isLive)
                        Spacer(minLength: Theme.Spacing.xs)
                        toggleView
                    }
                    openButton(isLive: isLive, showsTile: false)
                }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    openButton(isLive: isLive, showsTile: true)
                    toggleView
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var toggleView: some View {
        Toggle(rule.name, isOn: Binding(get: { rule.isEnabled }, set: toggle))
            .labelsHidden()
            .accessibilityLabel("\(rule.name) einschalten")
    }

    private func openButton(isLive: Bool, showsTile: Bool) -> some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                if showsTile { AutoKindTile(kind: rule.trigger.kind, isOn: isLive) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name)
                        .font(.headline)
                        .foregroundStyle(isLive ? Theme.textPrimary : Theme.textSecondary)
                    Text(AutoText.sentence(rule))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: rule.trigger.isScheduled ? "calendar.badge.clock" : "bolt.fill")
                            .accessibilityHidden(true)
                        Text(isLive ? nextLine : (isMasterOn ? "aus" : "Automatik ist aus"))
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isLive ? Theme.accentText : Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rule.name), \(isLive ? "eingeschaltet" : "ausgeschaltet"). \(AutoText.sentence(rule)) \(isLive ? nextLine : "")")
        .accessibilityHint("Öffnet Testlauf und Details")
        .accessibilityAddTraits(.isButton)
    }
}
