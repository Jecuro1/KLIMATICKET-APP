import SwiftUI
import UIKit
import KlimaCore

// Einstellungen › Aussteige-Wecker (docs/EXIT_ALARM.md §4): the lead time, the sound, "auch für Umstiege", "Wecker testen",
// which kind of alarm this iPhone uses, and what the app may do with the location. Inserted after the Live-Mitteilungen.
struct SetExitAlarmSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let service = ExitAlarmService.shared
    @Bindable private var prefs = ExitAlarmPrefs.shared

    var body: some View {
        Section {
            Group {
                Picker(selection: $prefs.defaultLead) {
                    // Short titles keep the chosen value on the row's line, like the sound below ("5 Min", not "5 Min vorher").
                    ForEach(ExitAlarmLead.allCases, id: \.self) { Text($0 == .atArrival ? "Bei Ankunft" : "\($0.minutes) Min").tag($0) }
                } label: {
                    SetRowLabel(title: "Vorlauf", subtitle: "Für neue Wecker",
                                symbol: "bell.badge.fill", tint: Theme.dawn)
                }

                Picker(selection: $prefs.sound) {
                    ForEach(ExitAlarmSound.allCases) { Text($0.title).tag($0) }
                } label: {
                    SetRowLabel(title: "Ton", subtitle: prefs.sound.subtitle, symbol: "speaker.wave.2.fill", tint: Theme.dusk)
                }

                Toggle(isOn: $prefs.alsoForTransfers) {
                    SetRowLabel(title: "Auch für Umstiege", subtitle: "Der Wecker ist beim Umsteigebahnhof gleich vorgewählt",
                                symbol: "arrow.triangle.swap", tint: Theme.glacier)
                }

                Button { Task { await runTest() } } label: {
                    SetRowLabel(title: "Wecker testen", subtitle: testSubtitle, symbol: "alarm.fill", tint: Theme.alpenglow)
                }
                .disabled(service.testAt != nil)

                statusRow(title: "Art des Weckers", value: kindText.0, ok: kindText.1)
                statusRow(title: "Standort", value: locationText.0, ok: locationText.1)

                if service.locationAuthorization == .denied || service.locationAuthorization == .restricted
                    || service.locationAuthorization == .whenInUse || service.cannotRingInBackground {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        SetRowLabel(title: "In den iOS-Einstellungen ändern", subtitle: "Standort, Mitteilungen und Wecker von KlimaBilanz",
                                    symbol: "gearshape.fill", tint: Theme.glacier)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Aussteige-Wecker")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SetFooter(text: kindFooter)
                SetFooter(text: "Der Standort wird nur auf deinem iPhone gelesen, solange ein Wecker scharf ist und die Fahrt läuft. Es gibt keinen Verlauf, nur die letzte Position im Arbeitsspeicher, und nichts wird gesendet. Mit „Immer“ weckt dich der Wecker auch bei gesperrtem iPhone; ohne Standort klingelt er nach Fahrplan.")
            }
        }
        .task { await service.prepare(askForPermissions: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await service.prepare(askForPermissions: false) } }
        }
    }

    // MARK: Texts

    private var testSubtitle: String {
        if service.testRang { return "Er klingelt gerade" }
        if service.testAt != nil { return "Klingelt in wenigen Sekunden. Sperre das iPhone, wenn du es prüfen willst." }
        return "Klingelt in 10 Sekunden, so wie beim echten Wecker"
    }

    private var kindText: (String, Bool) {
        switch service.alarmKind {
        case .alarmKit: ("Wecker-Ton, auch lautlos", true)
        case .notifications: ("Mitteilung, lautlos möglich", false)
        case .none: ("noch nicht erlaubt", false)
        }
    }

    private var kindFooter: String {
        switch service.alarmKind {
        case .alarmKit:
            "Dieses iPhone nutzt den Wecker von iOS 26: Er klingelt auch im Lautlos-Modus und im Fokus. „Wecker testen“ zeigt es dir, bevor du dich darauf verlässt."
        case .notifications:
            "Dieses iPhone nutzt Mitteilungen: drei im Abstand von 20 Sekunden. Der Lautlos-Schalter und der Fokus können sie stumm schalten, denn iOS erlaubt dafür keinen Durchbruch ohne eine Berechtigung, die diese App nicht hat. Erlaubst du den Wecker in den iOS-Einstellungen, klingelt er auch lautlos."
        case .none:
            "Noch ist nichts erlaubt: Der Wecker fragt beim ersten Stellen nach der Erlaubnis für den Wecker, ersatzweise für Mitteilungen."
        }
    }

    private var locationText: (String, Bool) {
        switch service.locationAuthorization {
        case .always: ("Immer erlaubt", true)
        case .whenInUse: ("Nur beim Verwenden", false)
        case .notDetermined: ("noch nicht gefragt", false)
        case .denied, .restricted: ("in iOS aus", false)
        }
    }

    private func statusRow(title: String, value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(value).font(.footnote).foregroundStyle(ok ? Theme.positiveText : Theme.summitText).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func runTest() async {
        await service.startTest()
    }
}
