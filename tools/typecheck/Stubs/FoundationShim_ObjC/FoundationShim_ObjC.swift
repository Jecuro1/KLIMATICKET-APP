// Hand-written stand-ins for Darwin Foundation API that comes from Objective-C
// headers (and therefore is not part of Foundation.swiftinterface) and that
// swift-corelibs-foundation on Linux does not have.
//
// Signatures follow the Swift names the Clang importer produces for the iOS 26
// SDK headers (Foundation.framework/Headers/*.h). Bodies are never executed.
//
// The generated FoundationShim module re-exports this module; the harness
// implicitly imports FoundationShim into every app source file, so code that
// only says `import Foundation` sees these declarations, like on iOS.

import Foundation

@inline(never) @usableFromInline func _kbUnimplemented() -> Never { fatalError("type-check stub") }

// MARK: - NSItemProvider (NSItemProvider.h)

public enum NSItemProviderRepresentationVisibility: Int, @unchecked Sendable {
    case all = 0
    case team = 1
    case group = 2
    case ownProcess = 3
}

public struct NSItemProviderFileOptions: OptionSet, @unchecked Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static var openInPlace: NSItemProviderFileOptions { .init(rawValue: 1) }
}

public protocol NSItemProviderWriting: NSObjectProtocol {
    static var writableTypeIdentifiersForItemProvider: [String] { get }
    func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping @Sendable (Data?, (any Error)?) -> Void) -> Progress?
}

public protocol NSItemProviderReading: NSObjectProtocol {
    static var readableTypeIdentifiersForItemProvider: [String] { get }
    static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self
}

open class NSItemProvider: NSObject, NSCopying, @unchecked Sendable {
    public override init() { super.init() }
    public convenience init(object: any NSItemProviderWriting) { _kbUnimplemented() }
    public init(item: (any NSSecureCoding)?, typeIdentifier: String?) { super.init() }
    public convenience init?(contentsOf fileURL: URL!) { _kbUnimplemented() }
    open func copy(with zone: NSZone? = nil) -> Any { _kbUnimplemented() }
    open var registeredTypeIdentifiers: [String] { _kbUnimplemented() }
    open var suggestedName: String?
    open func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool { _kbUnimplemented() }
    open func registerDataRepresentation(forTypeIdentifier typeIdentifier: String, visibility: NSItemProviderRepresentationVisibility, loadHandler: @escaping @Sendable (@escaping (Data?, (any Error)?) -> Void) -> Progress?) { _kbUnimplemented() }
    open func registerObject(_ object: any NSItemProviderWriting, visibility: NSItemProviderRepresentationVisibility) { _kbUnimplemented() }
    open func canLoadObject(ofClass aClass: any NSItemProviderReading.Type) -> Bool { _kbUnimplemented() }
    @discardableResult
    open func loadDataRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping @Sendable (Data?, (any Error)?) -> Void) -> Progress { _kbUnimplemented() }
    @discardableResult
    open func loadFileRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping @Sendable (URL?, (any Error)?) -> Void) -> Progress { _kbUnimplemented() }
    open func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil, completionHandler: (@Sendable ((any NSSecureCoding)?, (any Error)?) -> Void)? = nil) { _kbUnimplemented() }
}

// MARK: - NSUserActivity (NSUserActivity.h)

public typealias NSUserActivityPersistentIdentifier = String

public protocol NSUserActivityDelegate: NSObjectProtocol {}

open class NSUserActivity: NSObject, @unchecked Sendable {
    public init(activityType: String) { super.init() }
    open var activityType: String { _kbUnimplemented() }
    open var title: String?
    open var userInfo: [AnyHashable: Any]?
    open func addUserInfoEntries(from otherDictionary: [AnyHashable: Any]) { _kbUnimplemented() }
    open var requiredUserInfoKeys: Set<String>?
    open var needsSave: Bool = false
    open var webpageURL: URL?
    open var referrerURL: URL?
    open var expirationDate: Date?
    open var keywords: Set<String> = []
    open var supportsContinuationStreams: Bool = false
    open weak var delegate: (any NSUserActivityDelegate)?
    open var targetContentIdentifier: String?
    open func becomeCurrent() { _kbUnimplemented() }
    open func resignCurrent() { _kbUnimplemented() }
    open func invalidate() { _kbUnimplemented() }
    open var isEligibleForHandoff: Bool = false
    open var isEligibleForSearch: Bool = false
    open var isEligibleForPublicIndexing: Bool = false
    open var isEligibleForPrediction: Bool = false
    open var persistentIdentifier: NSUserActivityPersistentIdentifier?
}

// MARK: - UndoManager (NSUndoManager.h) – only what SwiftUI's environment needs

open class UndoManager: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open var canUndo: Bool { _kbUnimplemented() }
    open var canRedo: Bool { _kbUnimplemented() }
    open func undo() { _kbUnimplemented() }
    open func redo() { _kbUnimplemented() }
    open func beginUndoGrouping() { _kbUnimplemented() }
    open func endUndoGrouping() { _kbUnimplemented() }
    open var levelsOfUndo: Int = 0
    open func removeAllActions() { _kbUnimplemented() }
    open func setActionName(_ actionName: String) { _kbUnimplemented() }
    open func registerUndo<TargetType: AnyObject>(withTarget target: TargetType, handler: @escaping @Sendable (TargetType) -> Void) { _kbUnimplemented() }
}

// MARK: - FileWrapper (NSFileWrapper.h)

open class FileWrapper: NSObject, @unchecked Sendable {
    public struct ReadingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var immediate: ReadingOptions { .init(rawValue: 1) }
        public static var withoutMapping: ReadingOptions { .init(rawValue: 2) }
    }
    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var atomic: WritingOptions { .init(rawValue: 1) }
        public static var withNameUpdating: WritingOptions { .init(rawValue: 2) }
    }
    public init(url: URL, options: FileWrapper.ReadingOptions = []) throws { super.init() }
    public init(directoryWithFileWrappers childrenByPreferredName: [String: FileWrapper]) { super.init() }
    public init(regularFileWithContents contents: Data) { super.init() }
    open var regularFileContents: Data? { _kbUnimplemented() }
    open var filename: String?
    open var preferredFilename: String?
    open var isDirectory: Bool { _kbUnimplemented() }
    open var isRegularFile: Bool { _kbUnimplemented() }
    open var fileWrappers: [String: FileWrapper]? { _kbUnimplemented() }
    open func write(to url: URL, options: FileWrapper.WritingOptions = [], originalContentsURL: URL?) throws { _kbUnimplemented() }
}

// MARK: - ValueTransformer (NSValueTransformer.h)

open class ValueTransformer: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open class func allowsReverseTransformation() -> Bool { _kbUnimplemented() }
    open func transformedValue(_ value: Any?) -> Any? { _kbUnimplemented() }
    open func reverseTransformedValue(_ value: Any?) -> Any? { _kbUnimplemented() }
}

open class NSSecureUnarchiveFromDataTransformer: ValueTransformer, @unchecked Sendable {}

// MARK: - Methods Darwin Foundation has on existing classes

extension FileManager {
    /// NSFileManager.h: containerURLForSecurityApplicationGroupIdentifier:
    public func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? { _kbUnimplemented() }
    /// @property (nullable, readonly, copy) id<NSObject,NSCopying,NSCoding> ubiquityIdentityToken
    public var ubiquityIdentityToken: (any NSCoding & NSCopying & NSObjectProtocol)? { _kbUnimplemented() }
}

extension ProcessInfo {
    /// NSProcessInfo.h (getter=isMacCatalystApp / isiOSAppOnMac)
    public var isMacCatalystApp: Bool { _kbUnimplemented() }
    public var isiOSAppOnMac: Bool { _kbUnimplemented() }
    /// @property (readonly, getter=isLowPowerModeEnabled) BOOL lowPowerModeEnabled
    public var isLowPowerModeEnabled: Bool { _kbUnimplemented() }
    /// typedef NS_ENUM(NSInteger, NSProcessInfoThermalState)
    public enum ThermalState: Int, @unchecked Sendable {
        case nominal = 0, fair, serious, critical
    }
    /// @property (readonly) NSProcessInfoThermalState thermalState
    public var thermalState: ProcessInfo.ThermalState { _kbUnimplemented() }
    /// NSProcessInfoThermalStateDidChangeNotification
    public class var thermalStateDidChangeNotification: NSNotification.Name { _kbUnimplemented() }
}

extension Notification.Name {
    /// NSProcessInfoPowerStateDidChangeNotification
    public static var NSProcessInfoPowerStateDidChange: Notification.Name { _kbUnimplemented() }
}

// MARK: - NSUbiquitousKeyValueStore.h (Darwin only)

open class NSUbiquitousKeyValueStore: NSObject {
    /// @property (class, readonly, strong) NSUbiquitousKeyValueStore *defaultStore
    open class var `default`: NSUbiquitousKeyValueStore { _kbUnimplemented() }
    public override init() { super.init() }
    open func object(forKey aKey: String) -> Any? { _kbUnimplemented() }
    open func set(_ anObject: Any?, forKey aKey: String) { _kbUnimplemented() }
    open func removeObject(forKey aKey: String) { _kbUnimplemented() }
    open func string(forKey aKey: String) -> String? { _kbUnimplemented() }
    open func array(forKey aKey: String) -> [Any]? { _kbUnimplemented() }
    open func dictionary(forKey aKey: String) -> [String: Any]? { _kbUnimplemented() }
    open func data(forKey aKey: String) -> Data? { _kbUnimplemented() }
    open func longLong(forKey aKey: String) -> Int64 { _kbUnimplemented() }
    open func double(forKey aKey: String) -> Double { _kbUnimplemented() }
    open func bool(forKey aKey: String) -> Bool { _kbUnimplemented() }
    open func set(_ aString: String?, forKey aKey: String) { _kbUnimplemented() }
    open func set(_ aData: Data?, forKey aKey: String) { _kbUnimplemented() }
    open func set(_ anArray: [Any]?, forKey aKey: String) { _kbUnimplemented() }
    open func set(_ aDictionary: [String: Any]?, forKey aKey: String) { _kbUnimplemented() }
    open func set(_ value: Int64, forKey aKey: String) { _kbUnimplemented() }
    open func set(_ value: Double, forKey aKey: String) { _kbUnimplemented() }
    open func set(_ value: Bool, forKey aKey: String) { _kbUnimplemented() }
    open var dictionaryRepresentation: [String: Any] { _kbUnimplemented() }
    /// - (BOOL)synchronize  (imported Objective-C methods are implicitly @discardableResult)
    @discardableResult open func synchronize() -> Bool { _kbUnimplemented() }
    /// NSUbiquitousKeyValueStoreDidChangeExternallyNotification
    public class var didChangeExternallyNotification: NSNotification.Name { _kbUnimplemented() }
}
public let NSUbiquitousKeyValueStoreChangeReasonKey: String = "NSUbiquitousKeyValueStoreChangeReasonKey"
public let NSUbiquitousKeyValueStoreChangedKeysKey: String = "NSUbiquitousKeyValueStoreChangedKeysKey"
public var NSUbiquitousKeyValueStoreServerChange: Int { 0 }
public var NSUbiquitousKeyValueStoreInitialSyncChange: Int { 1 }
public var NSUbiquitousKeyValueStoreQuotaViolationChange: Int { 2 }
public var NSUbiquitousKeyValueStoreAccountChange: Int { 3 }

// MARK: - NSListFormatter.h (Darwin only)

open class ListFormatter: Formatter, @unchecked Sendable {
    public override init() { super.init() }
    public required init?(coder: NSCoder) { _kbUnimplemented() }
    /// @property (null_resettable, copy) NSLocale *locale
    open var locale: Locale! = .current
    open var itemFormatter: Formatter?
    open class func localizedString(byJoining strings: [String]) -> String { _kbUnimplemented() }
    open func string(from items: [Any]) -> String? { _kbUnimplemented() }
}

// MARK: - NSDateComponentsFormatter.h
// swift-corelibs-foundation marks DateComponentsFormatter unavailable; this declaration shadows it.

open class DateComponentsFormatter: Formatter, @unchecked Sendable {
    /// NS_ENUM(NSInteger, NSDateComponentsFormatterUnitsStyle)
    public enum UnitsStyle: Int, @unchecked Sendable {
        case positional = 0, abbreviated, short, full, spellOut, brief
    }
    /// NS_OPTIONS(NSUInteger, NSDateComponentsFormatterZeroFormattingBehavior)
    public struct ZeroFormattingBehavior: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var `default`: ZeroFormattingBehavior { .init(rawValue: 1 << 0) }
        public static var dropLeading: ZeroFormattingBehavior { .init(rawValue: 1 << 1) }
        public static var dropMiddle: ZeroFormattingBehavior { .init(rawValue: 1 << 2) }
        public static var dropTrailing: ZeroFormattingBehavior { .init(rawValue: 1 << 3) }
        public static var dropAll: ZeroFormattingBehavior { .init(rawValue: 14) }
        public static var pad: ZeroFormattingBehavior { .init(rawValue: 1 << 16) }
    }
    public override init() { super.init() }
    public required init?(coder: NSCoder) { _kbUnimplemented() }
    open func string(from components: DateComponents) -> String? { _kbUnimplemented() }
    open func string(from startDate: Date, to endDate: Date) -> String? { _kbUnimplemented() }
    open func string(from ti: TimeInterval) -> String? { _kbUnimplemented() }
    open class func localizedString(from components: DateComponents, unitsStyle: DateComponentsFormatter.UnitsStyle) -> String? { _kbUnimplemented() }
    open var unitsStyle: DateComponentsFormatter.UnitsStyle = .positional
    /// @property NSCalendarUnit allowedUnits
    open var allowedUnits: NSCalendar.Unit = []
    open var zeroFormattingBehavior: DateComponentsFormatter.ZeroFormattingBehavior = .default
    open var calendar: Calendar?
    open var referenceDate: Date?
    open var allowsFractionalUnits: Bool = false
    open var maximumUnitCount: Int = 0
    open var collapsesLargestUnit: Bool = false
    open var includesApproximationPhrase: Bool = false
    open var includesTimeRemainingPhrase: Bool = false
    open var formattingContext: Formatter.Context = .unknown
}

// MARK: - NSRelativeDateTimeFormatter.h (Darwin only)

open class RelativeDateTimeFormatter: Formatter, @unchecked Sendable {
    /// NS_ENUM(NSInteger, NSRelativeDateTimeFormatterStyle)
    public enum DateTimeStyle: Int, @unchecked Sendable {
        case numeric = 0
        case named = 1
    }
    /// NS_ENUM(NSInteger, NSRelativeDateTimeFormatterUnitsStyle)
    public enum UnitsStyle: Int, @unchecked Sendable {
        case full = 0
        case spellOut = 1
        case short = 2
        case abbreviated = 3
    }
    public override init() { super.init() }
    public required init?(coder: NSCoder) { _kbUnimplemented() }
    open var dateTimeStyle: RelativeDateTimeFormatter.DateTimeStyle = .numeric
    open var unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full
    open var formattingContext: Formatter.Context = .unknown
    open var calendar: Calendar! = .current
    open var locale: Locale! = .current
    open func localizedString(from dateComponents: DateComponents) -> String { _kbUnimplemented() }
    open func localizedString(fromTimeInterval timeInterval: TimeInterval) -> String { _kbUnimplemented() }
    open func localizedString(for date: Date, relativeTo referenceDate: Date) -> String { _kbUnimplemented() }
}

// MARK: - NSPersonNameComponentsFormatter.h
// swift-corelibs-foundation declares the class but none of its API, so this
// declaration shadows it (a module's declarations shadow those of modules it
// imports).

open class PersonNameComponentsFormatter: Formatter, @unchecked Sendable {
    public enum Style: Int, @unchecked Sendable {
        case `default` = 0, short, medium, long, abbreviated
    }
    public struct Options: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var phonetic: Options { .init(rawValue: 2) }
    }
    public override init() { super.init() }
    public required init?(coder: NSCoder) { _kbUnimplemented() }
    open var style: PersonNameComponentsFormatter.Style = .default
    open var isPhonetic: Bool = false
    open var locale: Locale! = .current
    open class func localizedString(from components: PersonNameComponents, style nameFormatStyle: PersonNameComponentsFormatter.Style, options nameOptions: PersonNameComponentsFormatter.Options = []) -> String { _kbUnimplemented() }
    open func string(from components: PersonNameComponents) -> String { _kbUnimplemented() }
    open func annotatedString(from components: PersonNameComponents) -> NSAttributedString { _kbUnimplemented() }
    open func personNameComponents(from string: String) -> PersonNameComponents? { _kbUnimplemented() }
}


extension NSData {
    /// NSData.h: NSDataCompressionAlgorithm
    public enum CompressionAlgorithm: Int, @unchecked Sendable {
        case lzfse = 0
        case lz4 = 1
        case lzma = 2
        case zlib = 3
    }
    /// - (nullable instancetype)decompressedDataUsingAlgorithm:error:
    public func decompressed(using algorithm: NSData.CompressionAlgorithm) throws -> Self { _kbUnimplemented() }
    /// - (nullable instancetype)compressedDataUsingAlgorithm:error:
    public func compressed(using algorithm: NSData.CompressionAlgorithm) throws -> Self { _kbUnimplemented() }
}

// MARK: - Objective-C runtime bits (ObjectiveC module on Darwin)

/// ObjectiveC.Selector
public struct Selector: ExpressibleByStringLiteral, Equatable, Hashable, CustomStringConvertible, @unchecked Sendable {
    public init(_ str: String) { description = str }
    public init(stringLiteral value: String) { description = value }
    public let description: String
}

public func NSSelectorFromString(_ aSelectorName: String) -> Selector { Selector(aSelectorName) }
public func NSStringFromSelector(_ aSelector: Selector) -> String { aSelector.description }

/// Target of `#selector(...)`, which tools/typecheck/preprocess.py rewrites to
/// `__kbSelector(...)` (Linux has no Objective-C runtime). Taking the method
/// reference as an argument still type-checks that the method exists.
public func __kbSelector<T>(_ method: T) -> Selector { _kbUnimplemented() }
public func __kbSelector<T>(getter property: T) -> Selector { _kbUnimplemented() }
public func __kbSelector<T>(setter property: T) -> Selector { _kbUnimplemented() }

// MARK: - CoreFoundation types (re-exported by Foundation on Darwin)
//
// CF types are toll-free bridged on Darwin (`data as CFData`, `cfString as String`).
// swift-corelibs-foundation supports the same `as` bridging for the NS classes,
// so the CF names are modelled as aliases of their NS counterparts.
public typealias CFTypeRef = AnyObject
public typealias CFString = NSString
public typealias CFMutableString = NSMutableString
public typealias CFData = NSData
public typealias CFMutableData = NSMutableData
public typealias CFDictionary = NSDictionary
public typealias CFMutableDictionary = NSMutableDictionary
public typealias CFArray = NSArray
public typealias CFMutableArray = NSMutableArray
public typealias CFNumber = NSNumber
public typealias CFBoolean = NSNumber
public typealias CFURL = NSURL
public typealias CFDate = NSDate
public typealias CFError = NSError
public typealias CFIndex = Int
public typealias CFTimeInterval = Double
public typealias CFAbsoluteTime = Double
public typealias OSStatus = Int32
public typealias OSType = UInt32
public let kCFBooleanTrue: CFBoolean! = nil
public let kCFBooleanFalse: CFBoolean! = nil
