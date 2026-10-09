// Hand-written stand-in for CoreMotion (Objective-C, CoreMotion.framework/Headers).

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _cmStub() -> Never { fatalError("type-check stub") }

public struct CMRotationRate: @unchecked Sendable { public var x: Double; public var y: Double; public var z: Double
    public init() { x = 0; y = 0; z = 0 }; public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z } }
public struct CMAcceleration: @unchecked Sendable { public var x: Double; public var y: Double; public var z: Double
    public init() { x = 0; y = 0; z = 0 }; public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z } }
public struct CMQuaternion: @unchecked Sendable { public var x: Double; public var y: Double; public var z: Double; public var w: Double
    public init() { x = 0; y = 0; z = 0; w = 0 } }
public struct CMRotationMatrix: @unchecked Sendable { public var m11, m12, m13, m21, m22, m23, m31, m32, m33: Double
    public init() { m11 = 0; m12 = 0; m13 = 0; m21 = 0; m22 = 0; m23 = 0; m31 = 0; m32 = 0; m33 = 0 } }

public struct CMAttitudeReferenceFrame: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var xArbitraryZVertical: CMAttitudeReferenceFrame { .init(rawValue: 1) }
    public static var xArbitraryCorrectedZVertical: CMAttitudeReferenceFrame { .init(rawValue: 2) }
    public static var xMagneticNorthZVertical: CMAttitudeReferenceFrame { .init(rawValue: 4) }
    public static var xTrueNorthZVertical: CMAttitudeReferenceFrame { .init(rawValue: 8) }
}

open class CMLogItem: NSObject, NSSecureCoding, NSCopying, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _cmStub() }
    public required init?(coder: NSCoder) { _cmStub() }
    open func encode(with coder: NSCoder) { _cmStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _cmStub() }
    open var timestamp: TimeInterval { _cmStub() }
}

open class CMAttitude: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _cmStub() }
    public required init?(coder: NSCoder) { _cmStub() }
    open func encode(with coder: NSCoder) { _cmStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _cmStub() }
    open var roll: Double { _cmStub() }
    open var pitch: Double { _cmStub() }
    open var yaw: Double { _cmStub() }
    open var rotationMatrix: CMRotationMatrix { _cmStub() }
    open var quaternion: CMQuaternion { _cmStub() }
    open func multiply(byInverseOf attitude: CMAttitude) { _cmStub() }
}

open class CMDeviceMotion: CMLogItem, @unchecked Sendable {
    open var attitude: CMAttitude { _cmStub() }
    open var rotationRate: CMRotationRate { _cmStub() }
    open var gravity: CMAcceleration { _cmStub() }
    open var userAcceleration: CMAcceleration { _cmStub() }
    open var heading: Double { _cmStub() }
}

open class CMAccelerometerData: CMLogItem, @unchecked Sendable {
    open var acceleration: CMAcceleration { _cmStub() }
}

open class CMGyroData: CMLogItem, @unchecked Sendable {
    open var rotationRate: CMRotationRate { _cmStub() }
}

public typealias CMDeviceMotionHandler = (CMDeviceMotion?, (any Error)?) -> Void
public typealias CMAccelerometerHandler = (CMAccelerometerData?, (any Error)?) -> Void
public typealias CMGyroHandler = (CMGyroData?, (any Error)?) -> Void

open class CMMotionManager: NSObject {
    public override init() { super.init() }
    open var accelerometerUpdateInterval: TimeInterval = 0
    open var isAccelerometerAvailable: Bool { _cmStub() }
    open var isAccelerometerActive: Bool { _cmStub() }
    open var accelerometerData: CMAccelerometerData? { _cmStub() }
    open func startAccelerometerUpdates() { _cmStub() }
    open func startAccelerometerUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAccelerometerHandler) { _cmStub() }
    open func stopAccelerometerUpdates() { _cmStub() }
    open var gyroUpdateInterval: TimeInterval = 0
    open var isGyroAvailable: Bool { _cmStub() }
    open var isGyroActive: Bool { _cmStub() }
    open var gyroData: CMGyroData? { _cmStub() }
    open func startGyroUpdates() { _cmStub() }
    open func startGyroUpdates(to queue: OperationQueue, withHandler handler: @escaping CMGyroHandler) { _cmStub() }
    open func stopGyroUpdates() { _cmStub() }
    open var deviceMotionUpdateInterval: TimeInterval = 0
    open class func availableAttitudeReferenceFrames() -> CMAttitudeReferenceFrame { _cmStub() }
    open var attitudeReferenceFrame: CMAttitudeReferenceFrame { _cmStub() }
    open var isDeviceMotionAvailable: Bool { _cmStub() }
    open var isDeviceMotionActive: Bool { _cmStub() }
    open var deviceMotion: CMDeviceMotion? { _cmStub() }
    open func startDeviceMotionUpdates() { _cmStub() }
    open func startDeviceMotionUpdates(to queue: OperationQueue, withHandler handler: @escaping CMDeviceMotionHandler) { _cmStub() }
    open func startDeviceMotionUpdates(using referenceFrame: CMAttitudeReferenceFrame) { _cmStub() }
    open func startDeviceMotionUpdates(using referenceFrame: CMAttitudeReferenceFrame, to queue: OperationQueue, withHandler handler: @escaping CMDeviceMotionHandler) { _cmStub() }
    open func stopDeviceMotionUpdates() { _cmStub() }
    open var showsDeviceMovementDisplay: Bool = false
}
