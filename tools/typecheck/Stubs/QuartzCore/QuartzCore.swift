// Hand-written stand-in for QuartzCore / Core Animation (Objective-C framework,
// QuartzCore.framework/Headers/CALayer.h, CAGradientLayer.h, CAShapeLayer.h), Swift names as
// imported for the iOS 26 SDK. Re-exported by UIKit (UIView.layer).
// CALayer is neither NS_SWIFT_UI_ACTOR nor NS_SWIFT_SENDABLE.

@_exported import Foundation
@_exported import FoundationShim
@_exported import CoreGraphics

@inline(never) @usableFromInline func _caStub() -> Never { fatalError("type-check stub") }

/// typedef NSString * CALayerCornerCurve NS_TYPED_ENUM
public struct CALayerCornerCurve: RawRepresentable, Hashable, @unchecked Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    /// kCACornerCurveCircular / kCACornerCurveContinuous
    public static let circular = CALayerCornerCurve(rawValue: "circular")
    public static let continuous = CALayerCornerCurve(rawValue: "continuous")
}

/// typedef NS_OPTIONS (NSUInteger, CACornerMask)
public struct CACornerMask: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var layerMinXMinYCorner: CACornerMask { .init(rawValue: 1 << 0) }
    public static var layerMaxXMinYCorner: CACornerMask { .init(rawValue: 1 << 1) }
    public static var layerMinXMaxYCorner: CACornerMask { .init(rawValue: 1 << 2) }
    public static var layerMaxXMaxYCorner: CACornerMask { .init(rawValue: 1 << 3) }
}

/// struct CATransform3D (CATransform3D.h)
public struct CATransform3D: @unchecked Sendable {
    public var m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat
    public var m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat
    public var m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat
    public var m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat
    public init() {
        m11 = 0; m12 = 0; m13 = 0; m14 = 0; m21 = 0; m22 = 0; m23 = 0; m24 = 0
        m31 = 0; m32 = 0; m33 = 0; m34 = 0; m41 = 0; m42 = 0; m43 = 0; m44 = 0
    }
}
public let CATransform3DIdentity = CATransform3D()
public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D { _caStub() }
public func CATransform3DMakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D { _caStub() }
public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D { _caStub() }

open class CALayer: NSObject {
    public override init() { super.init() }
    public init(layer: Any) { super.init() }
    open func presentation() -> Self? { _caStub() }
    open func model() -> Self { _caStub() }
    open var bounds: CGRect = .zero
    open var position: CGPoint = .zero
    open var zPosition: CGFloat = 0
    open var anchorPoint: CGPoint = .zero
    open var transform: CATransform3D = CATransform3DIdentity
    open func affineTransform() -> CGAffineTransform { _caStub() }
    open func setAffineTransform(_ m: CGAffineTransform) { _caStub() }
    open var frame: CGRect = .zero
    open var isHidden: Bool = false
    open var superlayer: CALayer? { _caStub() }
    open func removeFromSuperlayer() { _caStub() }
    open var sublayers: [CALayer]?
    open func addSublayer(_ layer: CALayer) { _caStub() }
    open func insertSublayer(_ layer: CALayer, at idx: UInt32) { _caStub() }
    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) { _caStub() }
    open func insertSublayer(_ layer: CALayer, above sibling: CALayer?) { _caStub() }
    open var mask: CALayer?
    open var masksToBounds: Bool = false
    open var contents: Any?
    open var contentsScale: CGFloat = 1
    open var isOpaque: Bool = false
    open func setNeedsDisplay() { _caStub() }
    open func setNeedsLayout() { _caStub() }
    open func layoutIfNeeded() { _caStub() }
    open func layoutSublayers() { _caStub() }
    open func render(in ctx: CGContext) { _caStub() }
    open var backgroundColor: CGColor?
    open var cornerRadius: CGFloat = 0
    open var maskedCorners: CACornerMask = []
    open var cornerCurve: CALayerCornerCurve = .circular
    open var borderWidth: CGFloat = 0
    open var borderColor: CGColor?
    open var opacity: Float = 1
    open var shouldRasterize: Bool = false
    open var rasterizationScale: CGFloat = 1
    open var shadowColor: CGColor?
    open var shadowOpacity: Float = 0
    open var shadowOffset: CGSize = .zero
    open var shadowRadius: CGFloat = 3
    open var shadowPath: CGPath?
    open func removeAllAnimations() { _caStub() }
}

/// typedef NSString * CAGradientLayerType NS_TYPED_ENUM
public struct CAGradientLayerType: RawRepresentable, Hashable, @unchecked Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let axial = CAGradientLayerType(rawValue: "axial")
    public static let radial = CAGradientLayerType(rawValue: "radial")
    public static let conic = CAGradientLayerType(rawValue: "conic")
}

open class CAGradientLayer: CALayer {
    open var colors: [Any]?
    open var locations: [NSNumber]?
    open var startPoint: CGPoint = .zero
    open var endPoint: CGPoint = .zero
    open var type: CAGradientLayerType = .axial
}

open class CAShapeLayer: CALayer {
    open var path: CGPath?
    open var fillColor: CGColor?
    open var strokeColor: CGColor?
    open var lineWidth: CGFloat = 1
    open var strokeStart: CGFloat = 0
    open var strokeEnd: CGFloat = 1
}

// MARK: - CADisplayLink (CADisplayLink.h, CAFrameRateRange.h, CABase.h)

/// struct CAFrameRateRange
public struct CAFrameRateRange: Equatable, @unchecked Sendable {
    public var minimum: Float
    public var maximum: Float
    public var preferred: Float?
    public init(minimum: Float, maximum: Float, preferred: Float? = nil) {
        self.minimum = minimum
        self.maximum = maximum
        self.preferred = preferred
    }
    public static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
}

public func CACurrentMediaTime() -> CFTimeInterval { _caStub() }

open class CADisplayLink: NSObject {
    public init(target: Any, selector sel: Selector) { super.init() }
    open func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) { _caStub() }
    open func remove(from runloop: RunLoop, forMode mode: RunLoop.Mode) { _caStub() }
    open func invalidate() { _caStub() }
    open var timestamp: CFTimeInterval { _caStub() }
    open var duration: CFTimeInterval { _caStub() }
    open var targetTimestamp: CFTimeInterval { _caStub() }
    open var isPaused: Bool = false
    open var preferredFrameRateRange: CAFrameRateRange = .default
}
