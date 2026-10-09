import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

/// Einstellungen › Daten › "Backup sichern" as a lazy share item: nothing is built while Settings opens or scrolls.
/// The file is written only once a share target (Mail, Dateien, AirDrop …) asks for it, from a background context
/// in a detached task – the fetch, the JSON encoding and the file write never run on the main thread.
/// (The CSV row shares `TripsCSVExport` with the Fahrten tab, which works the same way.)
struct BackupShareItem: Transferable {
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            let url = try await Task.detached(priority: .userInitiated) { try item.writeFile() }.value
            return SentTransferredFile(url)
        }
    }

    /// Tickets, trips, favourites and benefits – tombstones included, so a restore merges correctly. Repository commits
    /// every change right away, so the background context sees the same rows as the screens.
    private func writeFile() throws -> URL {
        let context = ModelContext(container)
        return try Backup.temporaryFile(named: "\(Backup.timestampedName)-Backup.json", data: Backup.export(context: context))
    }
}
