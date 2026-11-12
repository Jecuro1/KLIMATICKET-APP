import Foundation
import KlimaCore

// Aussteige-Wecker: the saved book of alarms (docs/EXIT_ALARM.md §6). UserDefaults on this device, never synced, never sent.
// What is saved: the stops, the schedule and the state of each alarm. The newest position is not saved (`ExitAlarmState`
// leaves it out of its coding keys), and there is no track.

final class ExitAlarmUserDefaultsStorage: ExitAlarmPersisting {
    static let key = "exitAlarm.book"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ExitAlarmBook? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(ExitAlarmBook.self, from: data)
    }

    func save(_ book: ExitAlarmBook) {
        guard !book.alarms.isEmpty else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        // The engine saves after every fix and every 5-second tick, but the saved book only changes when an alarm does (the newest
        // position is not part of it): identical data is not written again, which spares the disk and the battery on a night train.
        guard let data = try? JSONEncoder().encode(book), defaults.data(forKey: Self.key) != data else { return }
        defaults.set(data, forKey: Self.key)
    }
}
