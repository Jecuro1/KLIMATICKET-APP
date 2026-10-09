// Minimal hand-written stand-in for CoreSpotlight (Objective-C framework); only
// what AppIntents' IndexedEntity API mentions.

@_exported import Foundation
@_exported import FoundationShim
import UniformTypeIdentifiers

@inline(never) @usableFromInline func _csStub() -> Never { fatalError("type-check stub") }

open class CSSearchableItemAttributeSet: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _csStub() }
    public required init?(coder: NSCoder) { _csStub() }
    open func encode(with coder: NSCoder) { _csStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _csStub() }
    public init(contentType: UTType) { super.init() }
    open var title: String?
    open var displayName: String?
    open var contentDescription: String?
    open var keywords: [String]?
    open var thumbnailData: Data?
    open var thumbnailURL: URL?
    open var contentURL: URL?
    open var latitude: NSNumber?
    open var longitude: NSNumber?
}

open class CSCustomAttributeKey: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _csStub() }
    public required init?(coder: NSCoder) { _csStub() }
    open func encode(with coder: NSCoder) { _csStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _csStub() }
    public convenience init?(keyName: String) { _csStub() }
    open var keyName: String { _csStub() }
}

open class CSSearchableItem: NSObject, NSSecureCoding, NSCopying, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _csStub() }
    public required init?(coder: NSCoder) { _csStub() }
    open func encode(with coder: NSCoder) { _csStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _csStub() }
    public init(uniqueIdentifier: String?, domainIdentifier: String?, attributeSet: CSSearchableItemAttributeSet) { super.init() }
    open var uniqueIdentifier: String { _csStub() }
    open var domainIdentifier: String? { _csStub() }
    open var attributeSet: CSSearchableItemAttributeSet { _csStub() }
}

open class CSSearchableIndex: NSObject, @unchecked Sendable {
    open class func `default`() -> Self { _csStub() }
    public init(name: String) { super.init() }
    open func indexSearchableItems(_ items: [CSSearchableItem]) async throws { _csStub() }
    open func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws { _csStub() }
    open func deleteAllSearchableItems() async throws { _csStub() }
}
