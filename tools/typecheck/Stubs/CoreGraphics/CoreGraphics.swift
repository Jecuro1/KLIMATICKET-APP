// Hand-written stand-in for CoreGraphics (C API + the Swift overlay).
//
// On Linux, CGFloat / CGPoint / CGSize / CGRect come from Foundation
// (swift-corelibs-foundation) and are re-exported here. Everything else is
// declared with the Swift names the Clang importer produces for the iOS 26 SDK
// (CoreGraphics.framework/Headers/*.h) and the CoreGraphics overlay
// (CoreGraphics.swiftmodule). Members that Linux Foundation already provides
// on CGPoint/CGSize/CGRect must NOT be redeclared here (ambiguity).

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _cgStub() -> Never { fatalError("type-check stub") }

// MARK: - CGAffineTransform (CGAffineTransform.h + overlay)

public struct CGAffineTransform: Equatable, Hashable, Codable, @unchecked Sendable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var tx: CGFloat
    public var ty: CGFloat
    public init() { a = 1; b = 0; c = 0; d = 1; tx = 0; ty = 0 }
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ tx: CGFloat, _ ty: CGFloat) {
        self.init(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
    public static var identity: CGAffineTransform { _cgStub() }
    public init(translationX tx: CGFloat, y ty: CGFloat) { _cgStub() }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { _cgStub() }
    public init(rotationAngle angle: CGFloat) { _cgStub() }
    public var isIdentity: Bool { _cgStub() }
    public func translatedBy(x tx: CGFloat, y ty: CGFloat) -> CGAffineTransform { _cgStub() }
    public func scaledBy(x sx: CGFloat, y sy: CGFloat) -> CGAffineTransform { _cgStub() }
    public func rotated(by angle: CGFloat) -> CGAffineTransform { _cgStub() }
    public func inverted() -> CGAffineTransform { _cgStub() }
    public func concatenating(_ t2: CGAffineTransform) -> CGAffineTransform { _cgStub() }
}

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint { _cgStub() }
}
extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize { _cgStub() }
}
extension CGRect {
    public func applying(_ t: CGAffineTransform) -> CGRect { _cgStub() }
}

// MARK: - CGVector (CGGeometry.h + overlay)

public struct CGVector: Equatable, Hashable, Codable, @unchecked Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public init(dx: Double, dy: Double) { self.dx = CGFloat(dx); self.dy = CGFloat(dy) }
    public init(dx: Int, dy: Int) { self.dx = CGFloat(dx); self.dy = CGFloat(dy) }
    public static var zero: CGVector { CGVector() }
}

// MARK: - Path / stroke enums (CGPath.h, CGContext.h)

public enum CGLineCap: Int32, @unchecked Sendable {
    case butt = 0
    case round = 1
    case square = 2
}

public enum CGLineJoin: Int32, @unchecked Sendable {
    case miter = 0
    case round = 1
    case bevel = 2
}

public enum CGPathFillRule: Int, @unchecked Sendable {
    case winding = 0
    case evenOdd = 1
}

public enum CGBlendMode: Int32, @unchecked Sendable {
    case normal = 0, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight,
         hardLight, difference, exclusion, hue, saturation, color, luminosity, clear, copy,
         sourceIn, sourceOut, sourceAtop, destinationOver, destinationIn, destinationOut,
         destinationAtop, xor, plusDarker, plusLighter
}

public enum CGInterpolationQuality: Int32, @unchecked Sendable {
    case `default` = 0, none = 1, low = 2, high = 3, medium = 4
}

public enum CGColorRenderingIntent: Int32, @unchecked Sendable {
    case defaultIntent = 0, absoluteColorimetric, relativeColorimetric, perceptual, saturation
}

public struct CGImageAlphaInfo: RawRepresentable, Equatable, @unchecked Sendable {
    public var rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static var none: CGImageAlphaInfo { .init(rawValue: 0) }
    public static var premultipliedLast: CGImageAlphaInfo { .init(rawValue: 1) }
    public static var premultipliedFirst: CGImageAlphaInfo { .init(rawValue: 2) }
    public static var last: CGImageAlphaInfo { .init(rawValue: 3) }
    public static var first: CGImageAlphaInfo { .init(rawValue: 4) }
    public static var noneSkipLast: CGImageAlphaInfo { .init(rawValue: 5) }
    public static var noneSkipFirst: CGImageAlphaInfo { .init(rawValue: 6) }
    public static var alphaOnly: CGImageAlphaInfo { .init(rawValue: 7) }
}

// MARK: - CF-style object types

open class CGColorSpace: @unchecked Sendable {
    public init?(name: CFString) { _cgStub() }
    public static var sRGB: CFString { _cgStub() }
    public static var displayP3: CFString { _cgStub() }
    public static var genericGrayGamma2_2: CFString { _cgStub() }
    public static var extendedSRGB: CFString { _cgStub() }
    public var name: CFString? { _cgStub() }
    public var numberOfComponents: Int { _cgStub() }
}


open class CGColor: @unchecked Sendable {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { _cgStub() }
    public init(gray: CGFloat, alpha: CGFloat) { _cgStub() }
    public init?(colorSpace space: CGColorSpace, components: UnsafePointer<CGFloat>) { _cgStub() }
    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { _cgStub() }
    public class var black: CGColor { _cgStub() }
    public class var white: CGColor { _cgStub() }
    public class var clear: CGColor { _cgStub() }
    public var alpha: CGFloat { _cgStub() }
    public var numberOfComponents: Int { _cgStub() }
    public var components: [CGFloat]? { _cgStub() }
    public var colorSpace: CGColorSpace? { _cgStub() }
    public func copy(alpha: CGFloat) -> CGColor? { _cgStub() }
    public func converted(to: CGColorSpace, intent: CGColorRenderingIntent, options: [String: Any]?) -> CGColor? { _cgStub() }
}

open class CGImage: @unchecked Sendable {
    public var width: Int { _cgStub() }
    public var height: Int { _cgStub() }
    public var bitsPerComponent: Int { _cgStub() }
    public var bitsPerPixel: Int { _cgStub() }
    public var bytesPerRow: Int { _cgStub() }
    public var colorSpace: CGColorSpace? { _cgStub() }
    public var alphaInfo: CGImageAlphaInfo { _cgStub() }
    public func cropping(to rect: CGRect) -> CGImage? { _cgStub() }
    public func copy() -> CGImage? { _cgStub() }
}

open class CGPath: @unchecked Sendable {
    public var boundingBox: CGRect { _cgStub() }
    public var boundingBoxOfPath: CGRect { _cgStub() }
    public var currentPoint: CGPoint { _cgStub() }
    public var isEmpty: Bool { _cgStub() }
    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool { _cgStub() }
    public func copy() -> CGPath? { _cgStub() }
    public func mutableCopy() -> CGMutablePath? { _cgStub() }
    public init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) { _cgStub() }
    public init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) { _cgStub() }
    public init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>?) { _cgStub() }
}

open class CGMutablePath: CGPath, @unchecked Sendable {
    public init() { _cgStub() }
    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) { _cgStub() }
    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) { _cgStub() }
    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) { _cgStub() }
    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) { _cgStub() }
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) { _cgStub() }
    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) { _cgStub() }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) { _cgStub() }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform = .identity) { _cgStub() }
    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) { _cgStub() }
    public func closeSubpath() { _cgStub() }
}

open class CGContext: @unchecked Sendable {
    public func saveGState() { _cgStub() }
    public func restoreGState() { _cgStub() }
    public func translateBy(x tx: CGFloat, y ty: CGFloat) { _cgStub() }
    public func scaleBy(x sx: CGFloat, y sy: CGFloat) { _cgStub() }
    public func rotate(by angle: CGFloat) { _cgStub() }
    public func concatenate(_ transform: CGAffineTransform) { _cgStub() }
    public func setFillColor(_ color: CGColor) { _cgStub() }
    public func setStrokeColor(_ color: CGColor) { _cgStub() }
    public func setLineWidth(_ width: CGFloat) { _cgStub() }
    public func setLineCap(_ cap: CGLineCap) { _cgStub() }
    public func setLineJoin(_ join: CGLineJoin) { _cgStub() }
    public func setAlpha(_ alpha: CGFloat) { _cgStub() }
    public func setBlendMode(_ mode: CGBlendMode) { _cgStub() }
    public var interpolationQuality: CGInterpolationQuality
    public func addPath(_ path: CGPath) { _cgStub() }
    public func addRect(_ rect: CGRect) { _cgStub() }
    public func addEllipse(in rect: CGRect) { _cgStub() }
    public func move(to point: CGPoint) { _cgStub() }
    public func addLine(to point: CGPoint) { _cgStub() }
    public func closePath() { _cgStub() }
    public func fillPath(using rule: CGPathFillRule = .winding) { _cgStub() }
    public func strokePath() { _cgStub() }
    public func fill(_ rect: CGRect) { _cgStub() }
    public func stroke(_ rect: CGRect) { _cgStub() }
    public func fillEllipse(in rect: CGRect) { _cgStub() }
    public func clear(_ rect: CGRect) { _cgStub() }
    public func clip() { _cgStub() }
    public func clip(to rect: CGRect) { _cgStub() }
    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) { _cgStub() }
    public func makeImage() -> CGImage? { _cgStub() }
    public var width: Int { _cgStub() }
    public var height: Int { _cgStub() }
    init() { interpolationQuality = .default }

    // CGPDFContext.h: CGPDFContextCreateWithURL / CGPDFContextBeginPage / ...
    public convenience init?(_ url: CFURL, mediaBox: UnsafePointer<CGRect>?, _ auxiliaryInfo: CFDictionary?) { _cgStub() }
    public convenience init?(consumer: CGDataConsumer, mediaBox: UnsafePointer<CGRect>?, _ auxiliaryInfo: CFDictionary?) { _cgStub() }
    public func beginPDFPage(_ pageInfo: CFDictionary?) { _cgStub() }
    public func endPDFPage() { _cgStub() }
    public func closePDF() { _cgStub() }
    public func beginPage(mediaBox: UnsafePointer<CGRect>?) { _cgStub() }
    public func endPage() { _cgStub() }
    // CGBitmapContext.h
    public convenience init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) { _cgStub() }
}

open class CGDataConsumer: @unchecked Sendable {
    public init?(url: CFURL) { _cgStub() }
    public init?(data: CFMutableData) { _cgStub() }
}

public let kCGPDFContextMediaBox: CFString = "MediaBox"
public let kCGPDFContextTitle: CFString = "kCGPDFContextTitle"
public let kCGPDFContextAuthor: CFString = "kCGPDFContextAuthor"
public let kCGPDFContextSubject: CFString = "kCGPDFContextSubject"
public let kCGPDFContextKeywords: CFString = "kCGPDFContextKeywords"
public let kCGPDFContextCreator: CFString = "kCGPDFContextCreator"

open class CGGradient: @unchecked Sendable {
    public init?(colorsSpace space: CGColorSpace?, colors: [CGColor], locations: UnsafePointer<CGFloat>?) { _cgStub() }
}
