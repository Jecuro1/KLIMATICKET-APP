import SwiftUI
import KlimaCore

// Ticket-Schreiben (docs/TICKET_LETTERS.md): shared pieces of the letter screens – what they need from a ticket, the form
// state, and what is remembered on the device.

// MARK: - Ticket values

/// Everything the letter screens need from a ticket as plain values: a sheet never holds a SwiftData model.
struct TicketLetterContext: Equatable {
    var id: UUID
    var ticket: AdvisorTicket
    var number: String
    var holder: String

    @MainActor
    init(_ entity: TicketEntity) {
        id = entity.id
        ticket = AdvAdvisor.ticket(entity)
        number = entity.ticketNumber
        holder = entity.holderName
    }
}

/// Scroll targets inside the letter sheets (CI screenshot routes).
enum LetterAnchor: Hashable {
    case preview, reminder, bottom
}

// MARK: - Form

/// What the holder types into a letter sheet.
struct LetterForm: Equatable {
    var name = ""
    var street = ""
    var postcode = ""
    var place = ""
    var ticketNumber = ""
    /// The place in the date line; nil = follows the holder's place until it is edited.
    var letterPlace: String?
    var letterDate = Date()
    var recipientText = LetterRecipient.kundenservice.text

    var sender: LetterSender { LetterSender(name: name, street: street, postcode: postcode, place: place) }
    var recipient: LetterRecipient { LetterRecipient.parse(recipientText) }
    var placeForLetter: String { letterPlace ?? place }

    /// The form of a ticket: the number and holder from the ticket, name and address from the Keychain if the holder asked to
    /// remember them.
    static func initial(for context: TicketLetterContext, remembered: LetterSender?) -> LetterForm {
        var form = LetterForm()
        form.ticketNumber = context.number
        if let remembered {
            form.name = remembered.name
            form.street = remembered.street
            form.postcode = remembered.postcode
            form.place = remembered.place
        }
        if form.name.trimmingCharacters(in: .whitespaces).isEmpty { form.name = context.holder }
        return form
    }
}

// MARK: - Remembered on the device

/// What the letters keep on the device:
/// - the deadline of the renewal letter, per ticket, in UserDefaults (a date, no personal data);
/// - name and address only if the holder switches „Name und Adresse merken“ on (default off): in the Keychain through
///   `KeychainStore`, `…ThisDeviceOnly` – not synchronised, not restored from a backup onto another device.
/// CI screenshot and performance runs keep nothing.
enum LetterStore {
    private static let deadlinesKey = "letters.deadlines.v1"
    private static let rememberKey = "letters.rememberSender"
    private static let senderKey = "letters.sender.v1"

    // MARK: Deadline

    static func deadline(for ticketID: UUID) -> Date? {
        let stored = UserDefaults.standard.dictionary(forKey: deadlinesKey) as? [String: Double]
        return stored?[ticketID.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    static func setDeadline(_ date: Date?, for ticketID: UUID) {
        guard !LaunchMode.isSandboxed else { return }
        var stored = (UserDefaults.standard.dictionary(forKey: deadlinesKey) as? [String: Double]) ?? [:]
        if let date {
            stored[ticketID.uuidString] = date.timeIntervalSince1970
        } else {
            stored.removeValue(forKey: ticketID.uuidString)
        }
        UserDefaults.standard.set(stored, forKey: deadlinesKey)
    }

    // MARK: Name and address

    static var remembersSender: Bool {
        get { UserDefaults.standard.bool(forKey: rememberKey) }
        set {
            guard !LaunchMode.isSandboxed else { return }
            UserDefaults.standard.set(newValue, forKey: rememberKey)
            if !newValue { forgetSender() }
        }
    }

    static func loadSender() -> LetterSender? {
        guard remembersSender, let data = Keychain.data(for: senderKey) else { return nil }
        return try? JSONDecoder().decode(LetterSender.self, from: data)
    }

    static func saveSender(_ sender: LetterSender) {
        guard !LaunchMode.isSandboxed, remembersSender, !sender.isEmpty, let data = try? JSONEncoder().encode(sender.trimmed) else { return }
        KeychainStore().write(data, key: senderKey, thisDeviceOnly: true)
    }

    static func forgetSender() {
        guard !LaunchMode.isSandboxed else { return }
        KeychainStore().delete(senderKey)
    }
}

// MARK: - Copy

/// Texts shared by the letter screens (du-form; the letters themselves are in the formal Sie-form).
enum LetterText {
    static let notLegalAdvice = "Keine Rechtsberatung: Der Brief fasst zusammen, was in den AGB steht. Prüf ihn, bevor du unterschreibst."
    static let regionalTicket = "Für dein Ticket gelten die Bedingungen des Verkehrsverbunds – dieses Schreiben passt nicht."
    static let otherTicket = "Dieses Schreiben passt nur zum KlimaTicket Ö nach den AGB mit Stand \(TicketRights.agbStandShort). Für dein Ticket gelten andere Bedingungen."
    static let nothingToDo = "Du musst nichts tun – ohne Zahlung verlängert sich das Ticket nicht."
    static let rememberCaption = "Nur auf diesem iPhone im Schlüsselbund – nicht synchronisiert und nicht im Backup."
    static let recipientCaption = "Aus den AGB (\(LetterRecipient.kundenserviceClauses)). Nennt dein Verlängerungsbrief eine andere Adresse, nimm diese."
    static let deadlineCaption = "Die AGB binden die Frist an deinen Verlängerungsbrief – lies sie dort ab."

    /// „Noch 12 Tage“ / „Heute“ / „Vor 3 Tagen vorbei“ – the state of a deadline in one phrase.
    static func deadlineStatus(_ status: LetterDeadline.Status) -> String {
        switch status {
        case .open(let days): "Noch \(Format.days(days))"
        case .today: "Heute ist der letzte Tag"
        case .passed(let days): days == 1 ? "Gestern vorbei" : "Seit \(Format.days(days)) vorbei"
        }
    }

    /// „Noch 12 Tage, um Ticket und Formular abzugeben“ for the four-week window of an extraordinary cancellation.
    static func windowStatus(_ status: FilingWindow.Status, lastDay: Date) -> String {
        switch status {
        case .notYet: "Der Grund liegt noch in der Zukunft."
        case .open(let days):
            days == 0 ? "Heute ist der letzte Tag, um Ticket und Formular abzugeben."
                : "Noch \(Format.days(days)) für Ticket und Formular – bis \(Format.date(lastDay, .long))."
        case .closed(let days): "Die vier Wochen sind seit \(Format.days(days)) um."
        }
    }
}
