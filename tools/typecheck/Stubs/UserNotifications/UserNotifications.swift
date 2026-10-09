// Hand-written stand-in for UserNotifications (Objective-C framework,
// UserNotifications.framework/Headers). Swift names as imported for iOS 26:
// completion-handler methods also get their synthesised `async` variant.
// No NS_SWIFT_UI_ACTOR / NS_SWIFT_SENDABLE annotations exist in these headers.

@_exported import Foundation
@_exported import FoundationShim
import CoreLocation

@inline(never) @usableFromInline func _unStub() -> Never { fatalError("type-check stub") }

public struct UNAuthorizationOptions: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var badge: UNAuthorizationOptions { .init(rawValue: 1 << 0) }
    public static var sound: UNAuthorizationOptions { .init(rawValue: 1 << 1) }
    public static var alert: UNAuthorizationOptions { .init(rawValue: 1 << 2) }
    public static var carPlay: UNAuthorizationOptions { .init(rawValue: 1 << 3) }
    public static var criticalAlert: UNAuthorizationOptions { .init(rawValue: 1 << 4) }
    public static var providesAppNotificationSettings: UNAuthorizationOptions { .init(rawValue: 1 << 5) }
    public static var provisional: UNAuthorizationOptions { .init(rawValue: 1 << 6) }
}

public struct UNNotificationPresentationOptions: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var badge: UNNotificationPresentationOptions { .init(rawValue: 1 << 0) }
    public static var sound: UNNotificationPresentationOptions { .init(rawValue: 1 << 1) }
    @available(*, deprecated, message: "Use -list and -banner instead.")
    public static var alert: UNNotificationPresentationOptions { .init(rawValue: 1 << 2) }
    public static var list: UNNotificationPresentationOptions { .init(rawValue: 1 << 3) }
    public static var banner: UNNotificationPresentationOptions { .init(rawValue: 1 << 4) }
}

public enum UNAuthorizationStatus: Int, @unchecked Sendable {
    case notDetermined = 0, denied, authorized, provisional, ephemeral
}

public enum UNNotificationSetting: Int, @unchecked Sendable {
    case notSupported = 0, disabled, enabled
}

public enum UNAlertStyle: Int, @unchecked Sendable {
    case none = 0, banner, alert
}

public enum UNShowPreviewsSetting: Int, @unchecked Sendable {
    case always = 0, whenAuthenticated, never
}

public enum UNNotificationInterruptionLevel: UInt, @unchecked Sendable {
    case passive = 0, active, timeSensitive, critical
}

public struct UNNotificationActionOptions: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var authenticationRequired: UNNotificationActionOptions { .init(rawValue: 1 << 0) }
    public static var destructive: UNNotificationActionOptions { .init(rawValue: 1 << 1) }
    public static var foreground: UNNotificationActionOptions { .init(rawValue: 1 << 2) }
}

public struct UNNotificationCategoryOptions: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var customDismissAction: UNNotificationCategoryOptions { .init(rawValue: 1 << 0) }
    public static var allowInCarPlay: UNNotificationCategoryOptions { .init(rawValue: 1 << 1) }
    public static var hiddenPreviewsShowTitle: UNNotificationCategoryOptions { .init(rawValue: 1 << 2) }
    public static var hiddenPreviewsShowSubtitle: UNNotificationCategoryOptions { .init(rawValue: 1 << 3) }
}

public struct UNNotificationSoundName: RawRepresentable, Hashable, @unchecked Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

open class UNNotificationSound: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open class var `default`: UNNotificationSound { _unStub() }
    open class var defaultCritical: UNNotificationSound { _unStub() }
    public convenience init(named name: UNNotificationSoundName) { _unStub() }
    open class func criticalSoundNamed(_ name: UNNotificationSoundName) -> UNNotificationSound { _unStub() }
}

open class UNNotificationAttachment: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    public convenience init(identifier: String, url URL: URL, options: [AnyHashable: Any]? = nil) throws { _unStub() }
    open var identifier: String { _unStub() }
    open var url: URL { _unStub() }
}

open class UNNotificationContent: NSObject, NSCopying, NSMutableCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    public override init() { super.init() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open func mutableCopy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var attachments: [UNNotificationAttachment] { _unStub() }
    open var badge: NSNumber? { _unStub() }
    open var body: String { _unStub() }
    open var categoryIdentifier: String { _unStub() }
    open var launchImageName: String { _unStub() }
    open var sound: UNNotificationSound? { _unStub() }
    open var subtitle: String { _unStub() }
    open var threadIdentifier: String { _unStub() }
    open var title: String { _unStub() }
    open var userInfo: [AnyHashable: Any] { _unStub() }
    open var targetContentIdentifier: String? { _unStub() }
    open var interruptionLevel: UNNotificationInterruptionLevel { _unStub() }
    open var relevanceScore: Double { _unStub() }
    open var filterCriteria: String? { _unStub() }
}

open class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {
    open override var attachments: [UNNotificationAttachment] { get { _unStub() } set { _unStub() } }
    open override var badge: NSNumber? { get { _unStub() } set { _unStub() } }
    open override var body: String { get { _unStub() } set { _unStub() } }
    open override var categoryIdentifier: String { get { _unStub() } set { _unStub() } }
    open override var launchImageName: String { get { _unStub() } set { _unStub() } }
    open override var sound: UNNotificationSound? { get { _unStub() } set { _unStub() } }
    open override var subtitle: String { get { _unStub() } set { _unStub() } }
    open override var threadIdentifier: String { get { _unStub() } set { _unStub() } }
    open override var title: String { get { _unStub() } set { _unStub() } }
    open override var userInfo: [AnyHashable: Any] { get { _unStub() } set { _unStub() } }
    open override var targetContentIdentifier: String? { get { _unStub() } set { _unStub() } }
    open override var interruptionLevel: UNNotificationInterruptionLevel { get { _unStub() } set { _unStub() } }
    open override var relevanceScore: Double { get { _unStub() } set { _unStub() } }
    open override var filterCriteria: String? { get { _unStub() } set { _unStub() } }
}

open class UNNotificationTrigger: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var repeats: Bool { _unStub() }
}

open class UNPushNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {}

open class UNTimeIntervalNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    open var timeInterval: TimeInterval { _unStub() }
    /// + (instancetype)triggerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats;
    public convenience init(timeInterval: TimeInterval, repeats: Bool) { _unStub() }
    open func nextTriggerDate() -> Date? { _unStub() }
}

open class UNCalendarNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    open var dateComponents: DateComponents { _unStub() }
    /// + (instancetype)triggerWithDateMatchingComponents:(NSDateComponents *)dateComponents repeats:(BOOL)repeats;
    public convenience init(dateMatching dateComponents: DateComponents, repeats: Bool) { _unStub() }
    open func nextTriggerDate() -> Date? { _unStub() }
}

open class UNLocationNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    open var region: CLRegion { _unStub() }
    public convenience init(region: CLRegion, repeats: Bool) { _unStub() }
}

open class UNNotificationRequest: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var identifier: String { _unStub() }
    open var content: UNNotificationContent { _unStub() }
    open var trigger: UNNotificationTrigger? { _unStub() }
    /// + (instancetype)requestWithIdentifier:content:trigger:
    public convenience init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) { _unStub() }
}

open class UNNotification: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var date: Date { _unStub() }
    open var request: UNNotificationRequest { _unStub() }
}

open class UNNotificationResponse: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var notification: UNNotification { _unStub() }
    open var actionIdentifier: String { _unStub() }
}

open class UNTextInputNotificationResponse: UNNotificationResponse, @unchecked Sendable {
    open var userText: String { _unStub() }
}

public let UNNotificationDefaultActionIdentifier: String = "com.apple.UNNotificationDefaultActionIdentifier"
public let UNNotificationDismissActionIdentifier: String = "com.apple.UNNotificationDismissActionIdentifier"

open class UNNotificationActionIcon: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    public convenience init(templateImageName: String) { _unStub() }
    public convenience init(systemImageName: String) { _unStub() }
}

open class UNNotificationAction: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var identifier: String { _unStub() }
    open var title: String { _unStub() }
    open var options: UNNotificationActionOptions { _unStub() }
    open var icon: UNNotificationActionIcon? { _unStub() }
    public convenience init(identifier: String, title: String, options: UNNotificationActionOptions = []) { _unStub() }
    public convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: UNNotificationActionIcon?) { _unStub() }
}

open class UNTextInputNotificationAction: UNNotificationAction, @unchecked Sendable {
    public convenience init(identifier: String, title: String, options: UNNotificationActionOptions = [], textInputButtonTitle: String, textInputPlaceholder: String) { _unStub() }
    open var textInputButtonTitle: String { _unStub() }
    open var textInputPlaceholder: String { _unStub() }
}

open class UNNotificationCategory: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var identifier: String { _unStub() }
    open var actions: [UNNotificationAction] { _unStub() }
    open var intentIdentifiers: [String] { _unStub() }
    open var options: UNNotificationCategoryOptions { _unStub() }
    /// + categoryWithIdentifier:actions:intentIdentifiers:options:
    public convenience init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) { _unStub() }
    public convenience init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], hiddenPreviewsBodyPlaceholder: String, options: UNNotificationCategoryOptions = []) { _unStub() }
    public convenience init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], hiddenPreviewsBodyPlaceholder: String?, categorySummaryFormat: String?, options: UNNotificationCategoryOptions = []) { _unStub() }
}

open class UNNotificationSettings: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _unStub() }
    public required init?(coder: NSCoder) { _unStub() }
    open func encode(with coder: NSCoder) { _unStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _unStub() }
    open var authorizationStatus: UNAuthorizationStatus { _unStub() }
    open var soundSetting: UNNotificationSetting { _unStub() }
    open var badgeSetting: UNNotificationSetting { _unStub() }
    open var alertSetting: UNNotificationSetting { _unStub() }
    open var notificationCenterSetting: UNNotificationSetting { _unStub() }
    open var lockScreenSetting: UNNotificationSetting { _unStub() }
    open var carPlaySetting: UNNotificationSetting { _unStub() }
    open var alertStyle: UNAlertStyle { _unStub() }
    open var showPreviewsSetting: UNShowPreviewsSetting { _unStub() }
    open var criticalAlertSetting: UNNotificationSetting { _unStub() }
    open var providesAppNotificationSettings: Bool { _unStub() }
    open var announcementSetting: UNNotificationSetting { _unStub() }
    open var timeSensitiveSetting: UNNotificationSetting { _unStub() }
    open var scheduledDeliverySetting: UNNotificationSetting { _unStub() }
    open var directMessagesSetting: UNNotificationSetting { _unStub() }
}

open class UNUserNotificationCenter: NSObject {
    open weak var delegate: (any UNUserNotificationCenterDelegate)?
    open var supportsContentExtensions: Bool { _unStub() }
    /// + (UNUserNotificationCenter *)currentNotificationCenter;
    open class func current() -> UNUserNotificationCenter { _unStub() }

    open func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping (Bool, (any Error)?) -> Void) { _unStub() }
    open func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool { _unStub() }
    open func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { _unStub() }
    open func getNotificationCategories(completionHandler: @escaping (Set<UNNotificationCategory>) -> Void) { _unStub() }
    open func notificationCategories() async -> Set<UNNotificationCategory> { _unStub() }
    open func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) { _unStub() }
    open func notificationSettings() async -> UNNotificationSettings { _unStub() }
    open func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (((any Error)?) -> Void)? = nil) { _unStub() }
    open func add(_ request: UNNotificationRequest) async throws { _unStub() }
    open func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) { _unStub() }
    open func pendingNotificationRequests() async -> [UNNotificationRequest] { _unStub() }
    open func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { _unStub() }
    open func removeAllPendingNotificationRequests() { _unStub() }
    open func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) { _unStub() }
    open func deliveredNotifications() async -> [UNNotification] { _unStub() }
    open func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { _unStub() }
    open func removeAllDeliveredNotifications() { _unStub() }
    open func setBadgeCount(_ newBadgeCount: Int, withCompletionHandler completionHandler: (((any Error)?) -> Void)? = nil) { _unStub() }
    open func setBadgeCount(_ newBadgeCount: Int) async throws { _unStub() }
}

/// All methods are @optional in Objective-C; modelled as requirements with
/// default implementations.
public protocol UNUserNotificationCenterDelegate: NSObjectProtocol {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?)
}

extension UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {}
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [] }
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {}
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {}
    public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {}
}

/// UNError.h: NS_ERROR_ENUM(UNErrorDomain) -> struct UNError with nested Code
public struct UNError: Error, Hashable, @unchecked Sendable {
    public enum Code: Int, @unchecked Sendable {
        case notificationsNotAllowed = 1, attachmentInvalidURL = 100, attachmentUnrecognizedType, attachmentInvalidFileSize,
             attachmentNotInDataStore, attachmentMoveIntoDataStoreFailed, attachmentCorrupt,
             notificationInvalidNoDate = 1400, notificationInvalidNoContent, contentProvidingObjectNotAllowed = 1500,
             contentProvidingInvalid, badgeInputInvalid = 1600
    }
    public var code: Code { _unStub() }
    public static var notificationsNotAllowed: Code { .notificationsNotAllowed }
}
