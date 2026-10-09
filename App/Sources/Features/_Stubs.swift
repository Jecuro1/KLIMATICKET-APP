// TEMPORARY placeholders so the foundation compiles. Each feature module replaces its stub (delete the line here).
import SwiftUI
import KlimaCore

struct DashboardView: View { var body: some View { NavigationStack { Text("Übersicht").navigationTitle("Übersicht") } } }
struct TripsView: View { var body: some View { NavigationStack { Text("Fahrten").navigationTitle("Fahrten") } } }
struct StatisticsView: View { var body: some View { NavigationStack { Text("Statistik").navigationTitle("Statistik") } } }
struct TicketView: View { var body: some View { NavigationStack { Text("Ticket").navigationTitle("Ticket") } } }
struct OnboardingFlow: View { var body: some View { Text("Willkommen") } }
struct TripEditorView: View { let draft: TripDraft; var body: some View { Text("Fahrt") } }
struct TripDetailView: View { let trip: TripEntity; var body: some View { Text(trip.fromName) } }
struct AchievementsView: View { var body: some View { Text("Erfolge") } }
struct SettingsView: View { var body: some View { Text("Einstellungen") } }
struct UpdateSheet: View { var body: some View { Text("Update") } }
struct WidgetGalleryView: View { var body: some View { Text("Widgets") } }
