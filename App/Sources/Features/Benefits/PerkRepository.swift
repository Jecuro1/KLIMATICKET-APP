import Foundation
import SwiftData
import KlimaCore

/// Writes for the Vorteilswelt log. Like every other write they go through `Repository`, so saving,
/// widget refresh and cloud sync stay consistent. Deletes are soft (tombstone via `deletedAt` for sync).
extension Repository {
    @discardableResult
    func addBenefit(_ benefit: BenefitEntity) -> BenefitEntity {
        context.insert(benefit)
        commit()
        return benefit
    }

    func updateBenefit(_ benefit: BenefitEntity) {
        benefit.touch()
        commit()
    }

    /// Soft delete – the row stays as a tombstone so the deletion syncs to other devices.
    func deleteBenefit(_ benefit: BenefitEntity) {
        benefit.deletedAt = Date()
        benefit.touch()
        commit()
    }

    func restoreBenefit(_ benefit: BenefitEntity) {
        benefit.deletedAt = nil
        benefit.touch()
        commit()
    }

    /// Logs the same benefit again ("Heute nochmal genutzt").
    @discardableResult
    func repeatBenefit(_ benefit: BenefitEntity, on date: Date = Date()) -> BenefitEntity {
        let copy = BenefitEntity(date: date, partnerID: benefit.partnerID, title: benefit.title, savedEUR: benefit.savedEUR)
        context.insert(copy)
        commit()
        return copy
    }

    /// Live (not deleted) benefits, newest first.
    func liveBenefits() -> [BenefitEntity] {
        (try? context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt == nil },
                                                           sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }
}
