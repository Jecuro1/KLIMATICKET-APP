// Hand-written stand-in for the Security framework (C API, Security.framework/Headers).
// Swift names/types as imported by the Clang importer for the iOS 26 SDK:
//   CFDictionaryRef -> CFDictionary, CFTypeRef * -> UnsafeMutablePointer<CFTypeRef?>?,
//   OSStatus constants in CF_ENUM(OSStatus) -> `var errSecX: OSStatus { get }`,
//   `extern const CFStringRef kSecX` -> `let kSecX: CFString`.
// Imported C functions are implicitly @discardableResult (no "result unused" warning in Xcode).

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _secStub() -> Never { fatalError("type-check stub") }

// MARK: SecRandom.h
/// typedef const struct __SecRandom * SecRandomRef;  (not CF-bridged -> OpaquePointer)
public typealias SecRandomRef = OpaquePointer
public let kSecRandomDefault: SecRandomRef = OpaquePointer(bitPattern: 1)!
/// int SecRandomCopyBytes(SecRandomRef __nullable rnd, size_t count, void *bytes)
@discardableResult
public func SecRandomCopyBytes(_ rnd: SecRandomRef?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 { _secStub() }

// MARK: SecItem.h
@discardableResult
public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus { _secStub() }
@discardableResult
public func SecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus { _secStub() }
@discardableResult
public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus { _secStub() }
@discardableResult
public func SecItemDelete(_ query: CFDictionary) -> OSStatus { _secStub() }

public let kSecClass: CFString = "class"
public let kSecClassGenericPassword: CFString = "genp"
public let kSecClassInternetPassword: CFString = "inet"
public let kSecClassCertificate: CFString = "cert"
public let kSecClassKey: CFString = "keys"
public let kSecClassIdentity: CFString = "idnt"
public let kSecAttrAccessible: CFString = "pdmn"
public let kSecAttrAccessibleWhenUnlocked: CFString = "ak"
public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ck"
public let kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: CFString = "akpu"
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly: CFString = "aku"
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: CFString = "cku"
public let kSecAttrAccessGroup: CFString = "agrp"
public let kSecAttrSynchronizable: CFString = "sync"
public let kSecAttrService: CFString = "svce"
public let kSecAttrAccount: CFString = "acct"
public let kSecAttrLabel: CFString = "labl"
public let kSecAttrGeneric: CFString = "gena"
public let kSecAttrCreationDate: CFString = "cdat"
public let kSecAttrModificationDate: CFString = "mdat"
public let kSecMatchLimit: CFString = "m_Limit"
public let kSecMatchLimitOne: CFString = "m_LimitOne"
public let kSecMatchLimitAll: CFString = "m_LimitAll"
public let kSecReturnData: CFString = "r_Data"
public let kSecReturnAttributes: CFString = "r_Attributes"
public let kSecReturnRef: CFString = "r_Ref"
public let kSecReturnPersistentRef: CFString = "r_PersistentRef"
public let kSecValueData: CFString = "v_Data"
public let kSecValueRef: CFString = "v_Ref"
public let kSecUseDataProtectionKeychain: CFString = "nleg"

// MARK: SecBase.h – CF_ENUM(OSStatus)
public var errSecSuccess: OSStatus { 0 }
public var errSecUnimplemented: OSStatus { -4 }
public var errSecParam: OSStatus { -50 }
public var errSecAllocate: OSStatus { -108 }
public var errSecNotAvailable: OSStatus { -25291 }
public var errSecAuthFailed: OSStatus { -25293 }
public var errSecDuplicateItem: OSStatus { -25299 }
public var errSecItemNotFound: OSStatus { -25300 }
public var errSecInteractionNotAllowed: OSStatus { -25308 }
public var errSecDecode: OSStatus { -26275 }
public var errSecMissingEntitlement: OSStatus { -34018 }
public var errSecUserCanceled: OSStatus { -128 }

/// CFStringRef SecCopyErrorMessageString(OSStatus status, void * __nullable reserved)
@discardableResult
public func SecCopyErrorMessageString(_ status: OSStatus, _ reserved: UnsafeMutableRawPointer?) -> CFString? { _secStub() }

// MARK: SecAccessControl.h (only the type, CryptoKit mentions it)
open class SecAccessControl: @unchecked Sendable {}
open class SecKey: @unchecked Sendable {}
open class SecCertificate: @unchecked Sendable {}
open class SecIdentity: @unchecked Sendable {}
open class SecTrust: @unchecked Sendable {}
