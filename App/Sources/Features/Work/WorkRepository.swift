import Foundation
import KlimaCore

/// Writes of the "Arbeit & Steuer" module – through Repository, so save, widgets and sync stay consistent.
extension Repository {
    /// Sets the purpose of a logged trip (e.g. "Dienstreise" for the business-trip proof). No-op when unchanged.
    func workSetCategory(_ category: TripCategory?, for trip: TripEntity) {
        guard trip.category != category else { return }
        trip.category = category
        updateTrip(trip)
    }

    /// Jobticket: what the employer pays (tax-free) for the ticket, clamped to price + extras. No-op when unchanged.
    func workSetEmployerContribution(_ amount: Double, for ticket: TicketEntity) {
        let clamped = min(max(0, amount), max(0, ticket.price + ticket.addOnPrice))
        guard abs(ticket.employerContribution - clamped) > 0.004 else { return }
        ticket.employerContribution = clamped
        updateTicket(ticket)
    }
}
