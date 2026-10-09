// Hand-written stand-in for the C part of Darwin's `os` module (os/log.h,
// os/signpost.h, os/lock.h). The Swift API (Logger, OSLogMessage, OSSignposter,
// OSAllocatedUnfairLock, os_log(...)) is generated from the SDK's os.swiftinterface
// into Stubs/os, which re-exports this module.

@_exported import Foundation

@inline(never) @usableFromInline func _osStub() -> Never { fatalError("type-check stub") }

/// os_log_t (OS_OBJECT_DECL(os_log)) -> class OSLog
open class OSLog: NSObject, @unchecked Sendable {
    /// os_log_create(subsystem, category)
    public init(subsystem: String, category: String) { super.init() }
    /// OS_LOG_DEFAULT
    public class var `default`: OSLog { _osStub() }
    /// OS_LOG_DISABLED
    public class var disabled: OSLog { _osStub() }
    public func isEnabled(type: OSLogType) -> Bool { _osStub() }
    public var signpostsEnabled: Bool { _osStub() }
}

public typealias os_log_t = OSLog

/// typedef uint8_t os_log_type_t (imported as a struct named OSLogType)
public struct OSLogType: RawRepresentable, Equatable, Hashable, @unchecked Sendable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
}

/// typedef uint8_t os_signpost_type_t
public struct OSSignpostType: RawRepresentable, Equatable, Hashable, @unchecked Sendable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
}

public typealias os_signpost_id_t = UInt64

/// os/lock.h
public struct os_unfair_lock_s: @unchecked Sendable {
    public var _os_unfair_lock_opaque: UInt32
    public init() { _os_unfair_lock_opaque = 0 }
}
public typealias os_unfair_lock = os_unfair_lock_s
public typealias os_unfair_lock_t = UnsafeMutablePointer<os_unfair_lock_s>
public func os_unfair_lock_lock(_ lock: os_unfair_lock_t) { _osStub() }
public func os_unfair_lock_unlock(_ lock: os_unfair_lock_t) { _osStub() }
public func os_unfair_lock_trylock(_ lock: os_unfair_lock_t) -> Bool { _osStub() }
