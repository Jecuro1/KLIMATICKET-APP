// Hand-written stand-in for EventKit (Objective-C framework, EventKit.framework/Headers). Covers the event (calendar) side the app
// reads for Kalender-Vorschläge (App/Sources/Services/Calendar, docs/CALENDAR_SUGGESTIONS.md): the authorization status with the
// iOS 17 full / write-only access, the access requests (completion + async variant), calendars, sources, the event predicate and
// fetch, and the change notification. Swift names as the Clang importer produces them for the iOS 26 SDK: null_unspecified
// properties are implicitly unwrapped (`title`, `startDate`, `calendar`, `cgColor`), NS_ENUMs are Int/UInt enums that need
// `@unknown default` in a switch, and the deprecated `authorized` status / `requestAccess(to:)` keep their deprecation.

@_exported import Foundation
@_exported import FoundationShim
import CoreGraphics

@inline(never) @usableFromInline func _ekStub() -> Never { fatalError("type-check stub") }

public enum EKEntityType: UInt, @unchecked Sendable {
    case event = 0
    case reminder = 1
}

public struct EKEntityMask: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var event: EKEntityMask { .init(rawValue: 1) }
    public static var reminder: EKEntityMask { .init(rawValue: 2) }
}

public enum EKAuthorizationStatus: Int, @unchecked Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case fullAccess = 3
    case writeOnly = 4

    @available(*, deprecated, message: "Use EKAuthorizationStatusFullAccess.")
    public static var authorized: EKAuthorizationStatus { .fullAccess }
}

public enum EKCalendarType: Int, @unchecked Sendable {
    case local = 0
    case calDAV = 1
    case exchange = 2
    case subscription = 3
    case birthday = 4
}

public enum EKSourceType: Int, @unchecked Sendable {
    case local = 0
    case exchange = 1
    case calDAV = 2
    case mobileMe = 3
    case subscribed = 4
    case birthdays = 5
}

public enum EKSpan: Int, @unchecked Sendable {
    case thisEvent = 0
    case futureEvents = 1
}

public enum EKEventAvailability: Int, @unchecked Sendable {
    case notSupported = -1
    case busy = 0
    case free = 1
    case tentative = 2
    case unavailable = 3
}

public enum EKEventStatus: Int, @unchecked Sendable {
    case none = 0
    case confirmed = 1
    case tentative = 2
    case canceled = 3
}

public typealias EKEventStoreRequestAccessCompletionHandler = (Bool, (any Error)?) -> Void

open class EKObject: NSObject, @unchecked Sendable {
    open var hasChanges: Bool { _ekStub() }
    open var isNew: Bool { _ekStub() }
    open func reset() { _ekStub() }
    open func rollback() { _ekStub() }
    open func refresh() -> Bool { _ekStub() }
}

open class EKSource: EKObject, @unchecked Sendable {
    open var sourceIdentifier: String { _ekStub() }
    open var sourceType: EKSourceType { _ekStub() }
    open var title: String { _ekStub() }
    open var isDelegate: Bool { _ekStub() }
    open func calendars(for entityType: EKEntityType) -> Set<EKCalendar> { _ekStub() }
}

open class EKCalendar: EKObject, @unchecked Sendable {
    public init(for entityType: EKEntityType, eventStore: EKEventStore) { _ekStub() }
    open var source: EKSource! {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var calendarIdentifier: String { _ekStub() }
    open var title: String {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var type: EKCalendarType { _ekStub() }
    open var allowsContentModifications: Bool { _ekStub() }
    open var isSubscribed: Bool { _ekStub() }
    open var isImmutable: Bool { _ekStub() }
    open var cgColor: CGColor! {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var allowedEntityTypes: EKEntityMask { _ekStub() }
}

open class EKCalendarItem: EKObject, @unchecked Sendable {
    open var calendar: EKCalendar! {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var calendarItemIdentifier: String { _ekStub() }
    open var calendarItemExternalIdentifier: String! { _ekStub() }
    open var title: String! {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var location: String? {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var notes: String? {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var url: URL? {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var lastModifiedDate: Date? { _ekStub() }
    open var creationDate: Date? { _ekStub() }
    open var timeZone: TimeZone? {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var hasAlarms: Bool { _ekStub() }
    open var hasRecurrenceRules: Bool { _ekStub() }
    open var hasAttendees: Bool { _ekStub() }
    open var hasNotes: Bool { _ekStub() }
}

open class EKEvent: EKCalendarItem, @unchecked Sendable {
    public init(eventStore: EKEventStore) { _ekStub() }
    open var eventIdentifier: String! { _ekStub() }
    open var isAllDay: Bool {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var startDate: Date! {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var endDate: Date! {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var availability: EKEventAvailability {
        get { _ekStub() }
        set { _ekStub() }
    }
    open var status: EKEventStatus { _ekStub() }
    open var isDetached: Bool { _ekStub() }
    open var occurrenceDate: Date! { _ekStub() }
    open var birthdayContactIdentifier: String? { _ekStub() }
    open func compareStartDate(with other: EKEvent) -> ComparisonResult { _ekStub() }
}

open class EKEventStore: NSObject, @unchecked Sendable {
    open class func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus { _ekStub() }
    public override init() { _ekStub() }

    open func requestFullAccessToEvents(completion: @escaping EKEventStoreRequestAccessCompletionHandler) { _ekStub() }
    open func requestFullAccessToEvents() async throws -> Bool { _ekStub() }
    open func requestWriteOnlyAccessToEvents(completion: @escaping EKEventStoreRequestAccessCompletionHandler) { _ekStub() }
    open func requestWriteOnlyAccessToEvents() async throws -> Bool { _ekStub() }
    open func requestFullAccessToReminders(completion: @escaping EKEventStoreRequestAccessCompletionHandler) { _ekStub() }
    open func requestFullAccessToReminders() async throws -> Bool { _ekStub() }
    @available(*, deprecated, message: "Use -requestFullAccessToEventsWithCompletion:, -requestWriteOnlyAccessToEventsWithCompletion:, or -requestFullAccessToRemindersWithCompletion:")
    open func requestAccess(to entityType: EKEntityType, completion: @escaping EKEventStoreRequestAccessCompletionHandler) { _ekStub() }
    @available(*, deprecated, message: "Use -requestFullAccessToEventsWithCompletion:, -requestWriteOnlyAccessToEventsWithCompletion:, or -requestFullAccessToRemindersWithCompletion:")
    open func requestAccess(to entityType: EKEntityType) async throws -> Bool { _ekStub() }

    open var eventStoreIdentifier: String { _ekStub() }
    open var sources: [EKSource] { _ekStub() }
    open func source(withIdentifier identifier: String) -> EKSource? { _ekStub() }
    open func calendars(for entityType: EKEntityType) -> [EKCalendar] { _ekStub() }
    open var defaultCalendarForNewEvents: EKCalendar? { _ekStub() }
    open func calendar(withIdentifier identifier: String) -> EKCalendar? { _ekStub() }
    open func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? { _ekStub() }
    open func event(withIdentifier identifier: String) -> EKEvent? { _ekStub() }
    open func events(matching predicate: NSPredicate) -> [EKEvent] { _ekStub() }
    open func enumerateEvents(matching predicate: NSPredicate, using block: (EKEvent, UnsafeMutablePointer<ObjCBool>) -> Void) { _ekStub() }
    open func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]?) -> NSPredicate { _ekStub() }
    open func save(_ event: EKEvent, span: EKSpan) throws { _ekStub() }
    open func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws { _ekStub() }
    open func remove(_ event: EKEvent, span: EKSpan) throws { _ekStub() }
    open func commit() throws { _ekStub() }
    open func reset() { _ekStub() }
    open func refreshSourcesIfNecessary() { _ekStub() }
}

extension NSNotification.Name {
    /// `EKEventStoreChangedNotification`
    public static let EKEventStoreChanged = NSNotification.Name("EKEventStoreChangedNotification")
}
