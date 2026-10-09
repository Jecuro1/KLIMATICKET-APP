// Hand-written stand-in for UIKit (an Objective-C framework: its Swift API is
// produced by the Clang importer from UIKit.framework/Headers/*.h).
//
// Conventions (mirror the importer):
//  * NS_SWIFT_UI_ACTOR classes      -> @MainActor @preconcurrency
//  * NS_SWIFT_SENDABLE classes      -> @unchecked Sendable
//  * NS_SWIFT_NONISOLATED members   -> nonisolated
//  * NS_EXTENSION_UNAVAILABLE_IOS   -> @available(KBAppOnly)   (error in the widget target)
//  * completion-handler methods get the async variant the importer synthesises
//  * NS_ENUM -> Int enum, NS_OPTIONS -> OptionSet, NS_TYPED_ENUM -> RawRepresentable struct
// Only the parts used by the app or referenced by the SwiftUI interface are
// declared; add more as needed (see README "Extending the stubs").

@_exported import Foundation
@_exported import FoundationShim
@_exported import CoreGraphics
// UIView.h imports <QuartzCore/QuartzCore.h> (view.layer)
@_exported import QuartzCore
// UIKit.swiftinterface: @_exported import Accessibility (so `import SwiftUI`/`import UIKit`
// sees AXCustomContent, AXChartDescriptor, ...)
@_exported import Accessibility
import KBAvailability
import UniformTypeIdentifiers
import Symbols

@inline(never) @usableFromInline func _uiStub() -> Never { fatalError("type-check stub") }

// MARK: - Geometry (UIGeometry.h)

public struct UIEdgeInsets: Equatable, Hashable, @unchecked Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    public init() { top = 0; left = 0; bottom = 0; right = 0 }
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public static var zero: UIEdgeInsets { UIEdgeInsets() }
}

public struct NSDirectionalEdgeInsets: Equatable, Hashable, @unchecked Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat
    public init() { top = 0; leading = 0; bottom = 0; trailing = 0 }
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public static var zero: NSDirectionalEdgeInsets { NSDirectionalEdgeInsets() }
}

public struct UIRectEdge: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var top: UIRectEdge { .init(rawValue: 1) }
    public static var left: UIRectEdge { .init(rawValue: 2) }
    public static var bottom: UIRectEdge { .init(rawValue: 4) }
    public static var right: UIRectEdge { .init(rawValue: 8) }
    public static var all: UIRectEdge { .init(rawValue: 15) }
}

// MARK: - Trait enums (UIInterface.h, UIContentSizeCategory.h, UITraitCollection.h)

public enum UIUserInterfaceStyle: Int, @unchecked Sendable {
    case unspecified = 0
    case light = 1
    case dark = 2
}

public enum UIUserInterfaceSizeClass: Int, @unchecked Sendable {
    case unspecified = 0
    case compact = 1
    case regular = 2
}

public enum UIUserInterfaceIdiom: Int, @unchecked Sendable {
    case unspecified = -1
    case phone = 0
    case pad = 1
    case tv = 2
    case carPlay = 3
    case mac = 5
    case vision = 6
}

public enum UIUserInterfaceLevel: Int, @unchecked Sendable {
    case unspecified = -1
    case base = 0
    case elevated = 1
}

public enum UIUserInterfaceActiveAppearance: Int, @unchecked Sendable {
    case unspecified = -1
    case inactive = 0
    case active = 1
}

public enum UITraitEnvironmentLayoutDirection: Int, @unchecked Sendable {
    case unspecified = -1
    case leftToRight = 0
    case rightToLeft = 1
}

public enum UIAccessibilityContrast: Int, @unchecked Sendable {
    case unspecified = -1
    case normal = 0
    case high = 1
}

public enum UILegibilityWeight: Int, @unchecked Sendable {
    case unspecified = -1
    case regular = 0
    case bold = 1
}

public enum UIDisplayGamut: Int, @unchecked Sendable {
    case unspecified = -1
    case SRGB = 0
    case P3 = 1
}

public struct UIContentSizeCategory: RawRepresentable, Equatable, Hashable, Comparable, @unchecked Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static var unspecified: UIContentSizeCategory { _uiStub() }
    public static var extraSmall: UIContentSizeCategory { _uiStub() }
    public static var small: UIContentSizeCategory { _uiStub() }
    public static var medium: UIContentSizeCategory { _uiStub() }
    public static var large: UIContentSizeCategory { _uiStub() }
    public static var extraLarge: UIContentSizeCategory { _uiStub() }
    public static var extraExtraLarge: UIContentSizeCategory { _uiStub() }
    public static var extraExtraExtraLarge: UIContentSizeCategory { _uiStub() }
    public static var accessibilityMedium: UIContentSizeCategory { _uiStub() }
    public static var accessibilityLarge: UIContentSizeCategory { _uiStub() }
    public static var accessibilityExtraLarge: UIContentSizeCategory { _uiStub() }
    public static var accessibilityExtraExtraLarge: UIContentSizeCategory { _uiStub() }
    public static var accessibilityExtraExtraExtraLarge: UIContentSizeCategory { _uiStub() }
    public var isAccessibilityCategory: Bool { _uiStub() }
    public static func < (a: UIContentSizeCategory, b: UIContentSizeCategory) -> Bool { _uiStub() }
}

open class UITraitCollection: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open class var current: UITraitCollection { get { _uiStub() } set { _uiStub() } }
    open var userInterfaceStyle: UIUserInterfaceStyle { _uiStub() }
    open var userInterfaceIdiom: UIUserInterfaceIdiom { _uiStub() }
    open var userInterfaceLevel: UIUserInterfaceLevel { _uiStub() }
    open var horizontalSizeClass: UIUserInterfaceSizeClass { _uiStub() }
    open var verticalSizeClass: UIUserInterfaceSizeClass { _uiStub() }
    open var displayScale: CGFloat { _uiStub() }
    open var layoutDirection: UITraitEnvironmentLayoutDirection { _uiStub() }
    open var preferredContentSizeCategory: UIContentSizeCategory { _uiStub() }
    open var accessibilityContrast: UIAccessibilityContrast { _uiStub() }
    open var legibilityWeight: UILegibilityWeight { _uiStub() }
    open var displayGamut: UIDisplayGamut { _uiStub() }
    public convenience init(userInterfaceStyle: UIUserInterfaceStyle) { _uiStub() }
    public convenience init(horizontalSizeClass: UIUserInterfaceSizeClass) { _uiStub() }
    public convenience init(preferredContentSizeCategory: UIContentSizeCategory) { _uiStub() }
    public convenience init(traitsFrom traitCollections: [UITraitCollection]) { _uiStub() }
    open func hasDifferentColorAppearance(comparedTo traitCollection: UITraitCollection?) -> Bool { _uiStub() }
    open func performAsCurrent(_ actions: () -> Void) { _uiStub() }
}

@MainActor @preconcurrency
public protocol UITraitEnvironment: NSObjectProtocol {
    var traitCollection: UITraitCollection { get }
}

// MARK: - UIColor (UIColor.h, NS_SWIFT_SENDABLE)

open class UIColor: NSObject, NSSecureCoding, NSCopying, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _uiStub() }
    public required init?(coder: NSCoder) { _uiStub() }
    open func encode(with coder: NSCoder) { _uiStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _uiStub() }

    public init(white: CGFloat, alpha: CGFloat) { super.init() }
    public init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) { super.init() }
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { super.init() }
    public init(displayP3Red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { super.init() }
    public init(cgColor: CGColor) { super.init() }
    public init(patternImage image: UIImage) { super.init() }
    /// - (UIColor *)initWithDynamicProvider:(UIColor * (^)(UITraitCollection *traitCollection))dynamicProvider
    public init(dynamicProvider: @escaping (UITraitCollection) -> UIColor) { super.init() }
    /// + (nullable UIColor *)colorNamed:(NSString *)name
    public convenience init?(named name: String) { _uiStub() }
    public convenience init?(named name: String, in bundle: Bundle?, compatibleWith traitCollection: UITraitCollection?) { _uiStub() }

    open func resolvedColor(with traitCollection: UITraitCollection) -> UIColor { _uiStub() }
    open func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { _uiStub() }
    open func getHue(_ hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?, brightness: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { _uiStub() }
    open func getWhite(_ white: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { _uiStub() }
    open func withAlphaComponent(_ alpha: CGFloat) -> UIColor { _uiStub() }
    open var cgColor: CGColor { _uiStub() }

    open class var black: UIColor { _uiStub() }
    open class var darkGray: UIColor { _uiStub() }
    open class var lightGray: UIColor { _uiStub() }
    open class var white: UIColor { _uiStub() }
    open class var gray: UIColor { _uiStub() }
    open class var red: UIColor { _uiStub() }
    open class var green: UIColor { _uiStub() }
    open class var blue: UIColor { _uiStub() }
    open class var cyan: UIColor { _uiStub() }
    open class var yellow: UIColor { _uiStub() }
    open class var magenta: UIColor { _uiStub() }
    open class var orange: UIColor { _uiStub() }
    open class var purple: UIColor { _uiStub() }
    open class var brown: UIColor { _uiStub() }
    open class var clear: UIColor { _uiStub() }
    // UIInterface.h – semantic / system colors
    open class var systemRed: UIColor { _uiStub() }
    open class var systemGreen: UIColor { _uiStub() }
    open class var systemBlue: UIColor { _uiStub() }
    open class var systemOrange: UIColor { _uiStub() }
    open class var systemYellow: UIColor { _uiStub() }
    open class var systemPink: UIColor { _uiStub() }
    open class var systemPurple: UIColor { _uiStub() }
    open class var systemTeal: UIColor { _uiStub() }
    open class var systemIndigo: UIColor { _uiStub() }
    open class var systemBrown: UIColor { _uiStub() }
    open class var systemMint: UIColor { _uiStub() }
    open class var systemCyan: UIColor { _uiStub() }
    open class var systemGray: UIColor { _uiStub() }
    open class var systemGray2: UIColor { _uiStub() }
    open class var systemGray3: UIColor { _uiStub() }
    open class var systemGray4: UIColor { _uiStub() }
    open class var systemGray5: UIColor { _uiStub() }
    open class var systemGray6: UIColor { _uiStub() }
    open class var tintColor: UIColor { _uiStub() }
    open class var label: UIColor { _uiStub() }
    open class var secondaryLabel: UIColor { _uiStub() }
    open class var tertiaryLabel: UIColor { _uiStub() }
    open class var quaternaryLabel: UIColor { _uiStub() }
    open class var link: UIColor { _uiStub() }
    open class var placeholderText: UIColor { _uiStub() }
    open class var separator: UIColor { _uiStub() }
    open class var opaqueSeparator: UIColor { _uiStub() }
    open class var systemBackground: UIColor { _uiStub() }
    open class var secondarySystemBackground: UIColor { _uiStub() }
    open class var tertiarySystemBackground: UIColor { _uiStub() }
    open class var systemGroupedBackground: UIColor { _uiStub() }
    open class var secondarySystemGroupedBackground: UIColor { _uiStub() }
    open class var tertiarySystemGroupedBackground: UIColor { _uiStub() }
    open class var systemFill: UIColor { _uiStub() }
    open class var secondarySystemFill: UIColor { _uiStub() }
    open class var tertiarySystemFill: UIColor { _uiStub() }
    open class var quaternarySystemFill: UIColor { _uiStub() }
}

// MARK: - UIFont (UIFont.h, UIFontDescriptor.h)

open class UIFont: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _uiStub() }
    public required init?(coder: NSCoder) { _uiStub() }
    open func encode(with coder: NSCoder) { _uiStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _uiStub() }
    public struct TextStyle: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static var largeTitle: TextStyle { _uiStub() }
        public static var title1: TextStyle { _uiStub() }
        public static var title2: TextStyle { _uiStub() }
        public static var title3: TextStyle { _uiStub() }
        public static var headline: TextStyle { _uiStub() }
        public static var subheadline: TextStyle { _uiStub() }
        public static var body: TextStyle { _uiStub() }
        public static var callout: TextStyle { _uiStub() }
        public static var footnote: TextStyle { _uiStub() }
        public static var caption1: TextStyle { _uiStub() }
        public static var caption2: TextStyle { _uiStub() }
    }
    public struct Weight: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public init(_ rawValue: CGFloat) { self.rawValue = rawValue }
        public static var ultraLight: Weight { _uiStub() }
        public static var thin: Weight { _uiStub() }
        public static var light: Weight { _uiStub() }
        public static var regular: Weight { _uiStub() }
        public static var medium: Weight { _uiStub() }
        public static var semibold: Weight { _uiStub() }
        public static var bold: Weight { _uiStub() }
        public static var heavy: Weight { _uiStub() }
        public static var black: Weight { _uiStub() }
    }
    open class func preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont { _uiStub() }
    public convenience init?(name fontName: String, size fontSize: CGFloat) { _uiStub() }
    open class func systemFont(ofSize fontSize: CGFloat) -> UIFont { _uiStub() }
    open class func boldSystemFont(ofSize fontSize: CGFloat) -> UIFont { _uiStub() }
    open class func systemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight) -> UIFont { _uiStub() }
    open class func monospacedDigitSystemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight) -> UIFont { _uiStub() }
    open class func monospacedSystemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight) -> UIFont { _uiStub() }
    open var familyName: String { _uiStub() }
    open var fontName: String { _uiStub() }
    open var pointSize: CGFloat { _uiStub() }
    open var lineHeight: CGFloat { _uiStub() }
    open func withSize(_ fontSize: CGFloat) -> UIFont { _uiStub() }
}

// MARK: - UIImage (UIImage.h, NS_SWIFT_SENDABLE)

open class UIImage: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _uiStub() }
    public required init?(coder: NSCoder) { _uiStub() }
    open func encode(with coder: NSCoder) { _uiStub() }

    public enum Orientation: Int, @unchecked Sendable {
        case up = 0, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored
    }
    public enum RenderingMode: Int, @unchecked Sendable {
        case automatic = 0, alwaysOriginal, alwaysTemplate
    }
    public enum ResizingMode: Int, @unchecked Sendable {
        case tile = 0, stretch
    }

    public override init() { super.init() }
    /// + (nullable UIImage *)imageNamed:(NSString *)name
    public init?(named name: String) { super.init() }
    public init?(named name: String, in bundle: Bundle?, compatibleWith traitCollection: UITraitCollection?) { super.init() }
    public init?(named name: String, in bundle: Bundle?, with configuration: UIImage.Configuration?) { super.init() }
    /// + (nullable UIImage *)systemImageNamed:(NSString *)name
    public init?(systemName name: String) { super.init() }
    public init?(systemName name: String, withConfiguration configuration: UIImage.Configuration?) { super.init() }
    public init?(systemName name: String, compatibleWith traitCollection: UITraitCollection?) { super.init() }
    public init?(contentsOfFile path: String) { super.init() }
    public init?(data: Data) { super.init() }
    public init?(data: Data, scale: CGFloat) { super.init() }
    public init(cgImage: CGImage) { super.init() }
    public init(cgImage: CGImage, scale: CGFloat, orientation: UIImage.Orientation) { super.init() }

    open var size: CGSize { _uiStub() }
    open var scale: CGFloat { _uiStub() }
    open var cgImage: CGImage? { _uiStub() }
    open var imageOrientation: UIImage.Orientation { _uiStub() }
    open var renderingMode: UIImage.RenderingMode { _uiStub() }
    open var isSymbolImage: Bool { _uiStub() }
    open func withRenderingMode(_ renderingMode: UIImage.RenderingMode) -> UIImage { _uiStub() }
    open func withTintColor(_ color: UIColor) -> UIImage { _uiStub() }
    open func withTintColor(_ color: UIColor, renderingMode: UIImage.RenderingMode) -> UIImage { _uiStub() }
    open func withConfiguration(_ configuration: UIImage.Configuration) -> UIImage { _uiStub() }
    open func resizableImage(withCapInsets capInsets: UIEdgeInsets) -> UIImage { _uiStub() }
    open func draw(in rect: CGRect) { _uiStub() }
    open func draw(at point: CGPoint) { _uiStub() }
    /// UIImage.h, iOS 15: - imageByPreparingForDisplay / - prepareForDisplayWithCompletionHandler:
    /// NS_SWIFT_ASYNC_NAME(byPreparingForDisplay()) / - imageByPreparingThumbnailOfSize: /
    /// - prepareThumbnailOfSize:completionHandler: NS_SWIFT_ASYNC_NAME(byPreparingThumbnail(ofSize:))
    open func preparingForDisplay() -> UIImage? { _uiStub() }
    open func prepareForDisplay(completionHandler: @escaping (UIImage?) -> Void) { _uiStub() }
    open func byPreparingForDisplay() async -> UIImage? { _uiStub() }
    open func preparingThumbnail(of size: CGSize) -> UIImage? { _uiStub() }
    open func prepareThumbnail(of size: CGSize, completionHandler: @escaping (UIImage?) -> Void) { _uiStub() }
    open func byPreparingThumbnail(ofSize size: CGSize) async -> UIImage? { _uiStub() }
    /// UIGraphicsImageRepresentation: UIImagePNGRepresentation / UIImageJPEGRepresentation (Swift names)
    open func pngData() -> Data? { _uiStub() }
    open func jpegData(compressionQuality: CGFloat) -> Data? { _uiStub() }
    open func heicData() -> Data? { _uiStub() }

    open class Configuration: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
        public static var supportsSecureCoding: Bool { _uiStub() }
        public required init?(coder: NSCoder) { _uiStub() }
        open func encode(with coder: NSCoder) { _uiStub() }
        open func copy(with zone: NSZone? = nil) -> Any { _uiStub() }
    }
    open class SymbolConfiguration: UIImage.Configuration, @unchecked Sendable {
        public enum Scale: Int, @unchecked Sendable { case `default` = -1, unspecified = 0, small = 1, medium = 2, large = 3 }
        public enum Weight: Int, @unchecked Sendable { case unspecified = 0, ultraLight, thin, light, regular, medium, semibold, bold, heavy, black }
        public convenience init(pointSize: CGFloat) { _uiStub() }
        public convenience init(pointSize: CGFloat, weight: UIImage.SymbolWeight) { _uiStub() }
        public convenience init(scale: UIImage.SymbolScale) { _uiStub() }
        public convenience init(weight: UIImage.SymbolWeight) { _uiStub() }
        public convenience init(textStyle: UIFont.TextStyle) { _uiStub() }
        public convenience init(hierarchicalColor: UIColor) { _uiStub() }
        public convenience init(paletteColors: [UIColor]) { _uiStub() }
        open class func preferringMulticolor() -> Self { _uiStub() }
    }
    public typealias SymbolScale = SymbolConfiguration.Scale
    public typealias SymbolWeight = SymbolConfiguration.Weight

    /// The Clang importer maps the factory method `+systemImageNamed:` to `init?(systemName:)`; calling it
    /// as a class method is an error in Swift.
    @available(*, unavailable, renamed: "init(systemName:)", message: "use object construction 'UIImage(systemName:)'")
    open class func systemImageNamed(_ name: String) -> UIImage? { _uiStub() }
    open class var add: UIImage { _uiStub() }
    open class var remove: UIImage { _uiStub() }
    open class var actions: UIImage { _uiStub() }
    open class var checkmark: UIImage { _uiStub() }
    open class var strokedCheckmark: UIImage { _uiStub() }
}

// MARK: - Graphics (UIGraphicsImageRenderer.h, UIGraphics.h)

open class UIGraphicsRendererFormat: NSObject, NSCopying, @unchecked Sendable {
    public override init() { super.init() }
    open func copy(with zone: NSZone? = nil) -> Any { _uiStub() }
    open var bounds: CGRect { _uiStub() }
    open class func preferred() -> Self { _uiStub() }
}

open class UIGraphicsImageRendererFormat: UIGraphicsRendererFormat, @unchecked Sendable {
    open var scale: CGFloat = 1
    open var opaque: Bool = false
    open var prefersExtendedRange: Bool = false
}

open class UIGraphicsRendererContext: NSObject {
    open var cgContext: CGContext { _uiStub() }
    open var format: UIGraphicsRendererFormat { _uiStub() }
    open func fill(_ rect: CGRect) { _uiStub() }
    open func stroke(_ rect: CGRect) { _uiStub() }
}

open class UIGraphicsImageRendererContext: UIGraphicsRendererContext {
    open var currentImage: UIImage { _uiStub() }
}

open class UIGraphicsRenderer: NSObject, @unchecked Sendable {
    public init(bounds: CGRect) { super.init() }
    public init(bounds: CGRect, format: UIGraphicsRendererFormat) { super.init() }
    open var format: UIGraphicsRendererFormat { _uiStub() }
    open var allowsImageOutput: Bool { _uiStub() }
}

open class UIGraphicsImageRenderer: UIGraphicsRenderer, @unchecked Sendable {
    public convenience init(size: CGSize) { _uiStub() }
    public init(size: CGSize, format: UIGraphicsImageRendererFormat) { super.init(bounds: .zero) }
    public init(bounds: CGRect, format: UIGraphicsImageRendererFormat) { super.init(bounds: bounds) }
    public typealias DrawingActions = (UIGraphicsImageRendererContext) -> Void
    open func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage { _uiStub() }
    open func pngData(actions: (UIGraphicsImageRendererContext) -> Void) -> Data { _uiStub() }
    open func jpegData(withCompressionQuality compressionQuality: CGFloat, actions: (UIGraphicsImageRendererContext) -> Void) -> Data { _uiStub() }
}

// MARK: - Responder chain (UIResponder.h, UIEvent.h, UIGestureRecognizer.h)

@MainActor @preconcurrency
open class UIEvent: NSObject {
    public enum EventType: Int, @unchecked Sendable { case touches = 0, motion, remoteControl, presses, scroll = 10, hover = 11, transform = 14 }
    open var type: UIEvent.EventType { _uiStub() }
    open var timestamp: TimeInterval { _uiStub() }
}

@MainActor @preconcurrency
open class UIResponder: NSObject {
    public override init() { super.init() }
    open var next: UIResponder? { _uiStub() }
    open var canBecomeFirstResponder: Bool { _uiStub() }
    @discardableResult open func becomeFirstResponder() -> Bool { _uiStub() }
    open var canResignFirstResponder: Bool { _uiStub() }
    @discardableResult open func resignFirstResponder() -> Bool { _uiStub() }
    open var isFirstResponder: Bool { _uiStub() }
    open var undoManager: UndoManager? { _uiStub() }
    open var userActivity: NSUserActivity?

    public struct KeyboardInfo {}
    nonisolated public class var keyboardWillShowNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var keyboardDidShowNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var keyboardWillHideNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var keyboardDidHideNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var keyboardWillChangeFrameNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var keyboardFrameEndUserInfoKey: String { _uiStub() }
    nonisolated public class var keyboardFrameBeginUserInfoKey: String { _uiStub() }
    nonisolated public class var keyboardAnimationDurationUserInfoKey: String { _uiStub() }
}

@MainActor @preconcurrency
open class UIGestureRecognizer: NSObject {
    public enum State: Int, @unchecked Sendable { case possible = 0, began, changed, ended, cancelled, failed
        public static var recognized: State { .ended } }
    public init(target: Any?, action: Selector?) { super.init() }
    public override init() { super.init() }
    open var state: UIGestureRecognizer.State { _uiStub() }
    open var isEnabled: Bool = true
    open var view: UIView? { _uiStub() }
    open var cancelsTouchesInView: Bool = true
    open func location(in view: UIView?) -> CGPoint { _uiStub() }
}

@MainActor @preconcurrency
public protocol UIGestureRecognizerDelegate: NSObjectProtocol {}

@MainActor @preconcurrency
open class UIKeyCommand: NSObject {
    public override init() { super.init() }
}

@MainActor @preconcurrency
public protocol UIFocusEnvironment: NSObjectProtocol {}
@MainActor @preconcurrency
public protocol UIFocusItem: UIFocusEnvironment {}
@MainActor @preconcurrency
open class UIFocusUpdateContext: NSObject {}
@MainActor @preconcurrency
open class UIFocusAnimationCoordinator: NSObject {}
@MainActor @preconcurrency
public protocol UIDragSession: NSObjectProtocol {}
@MainActor @preconcurrency
public protocol UIDropSession: NSObjectProtocol {}
@MainActor @preconcurrency
public protocol UIViewControllerTransitionCoordinator: NSObjectProtocol {}
@MainActor @preconcurrency
public protocol UIContentContainer: NSObjectProtocol {}
@MainActor @preconcurrency
public protocol UIConfigurationState {}
@MainActor @preconcurrency
public protocol UIContentConfiguration {}
@MainActor @preconcurrency
public protocol UIContentView: NSObjectProtocol {}

// MARK: - Views (UIView.h, UIViewController.h, UIWindow.h, UIScreen.h)

@MainActor @preconcurrency
open class UIView: UIResponder, UITraitEnvironment {
    public init(frame: CGRect) { super.init() }
    public required init?(coder: NSCoder) { _uiStub() }
    public convenience override init() { self.init(frame: .zero) }
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var center: CGPoint = .zero
    open var transform: CGAffineTransform = .identity
    open var superview: UIView? { _uiStub() }
    open var subviews: [UIView] { _uiStub() }
    open var window: UIWindow? { _uiStub() }
    open var backgroundColor: UIColor?
    open var tintColor: UIColor!
    open var alpha: CGFloat = 1
    open var isHidden: Bool = false
    open var isOpaque: Bool = true
    open var clipsToBounds: Bool = false
    open var isUserInteractionEnabled: Bool = true
    open var contentMode: UIView.ContentMode = .scaleToFill
    open var traitCollection: UITraitCollection { _uiStub() }
    open var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
    open var safeAreaInsets: UIEdgeInsets { _uiStub() }
    open var layoutMargins: UIEdgeInsets = .zero
    open var intrinsicContentSize: CGSize { _uiStub() }
    open var translatesAutoresizingMaskIntoConstraints: Bool = true
    /// @property(class, nonatomic, readonly) Class layerClass  (overridden by subclasses)
    open class var layerClass: AnyClass { CALayer.self }
    open var layer: CALayer { _uiStub() }
    open func addSubview(_ view: UIView) { _uiStub() }
    open func removeFromSuperview() { _uiStub() }
    open func layoutSubviews() { _uiStub() }
    open func setNeedsLayout() { _uiStub() }
    open func layoutIfNeeded() { _uiStub() }
    open func setNeedsDisplay() { _uiStub() }
    open func draw(_ rect: CGRect) { _uiStub() }
    open func sizeThatFits(_ size: CGSize) -> CGSize { _uiStub() }
    open func sizeToFit() { _uiStub() }
    open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) { _uiStub() }
    open func convert(_ point: CGPoint, to view: UIView?) -> CGPoint { _uiStub() }
    open func convert(_ rect: CGRect, to view: UIView?) -> CGRect { _uiStub() }
    open func snapshotView(afterScreenUpdates afterUpdates: Bool) -> UIView? { _uiStub() }
    open func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool { _uiStub() }
    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) { _uiStub() }
    open class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void) { _uiStub() }
    open class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) { _uiStub() }
    open class var areAnimationsEnabled: Bool { _uiStub() }
    open class func performWithoutAnimation(_ actionsWithoutAnimation: () -> Void) { _uiStub() }

    public enum ContentMode: Int, @unchecked Sendable {
        case scaleToFill = 0, scaleAspectFit, scaleAspectFill, redraw, center, top, bottom, left, right,
             topLeft, topRight, bottomLeft, bottomRight
    }
}

@MainActor @preconcurrency
open class UIWindow: UIView {
    public init(windowScene: UIWindowScene) { super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var windowScene: UIWindowScene?
    open var rootViewController: UIViewController?
    open var isKeyWindow: Bool { _uiStub() }
    open func makeKeyAndVisible() { _uiStub() }
}

@MainActor @preconcurrency
open class UIScreen: NSObject, UITraitEnvironment {
    @available(*, deprecated, message: "Use a UIScreen instance found through context instead: i.e, view.window.windowScene.screen")
    open class var main: UIScreen { _uiStub() }
    open var bounds: CGRect { _uiStub() }
    open var nativeBounds: CGRect { _uiStub() }
    open var scale: CGFloat { _uiStub() }
    open var nativeScale: CGFloat { _uiStub() }
    open var brightness: CGFloat = 0.5
    open var traitCollection: UITraitCollection { _uiStub() }
}

@MainActor @preconcurrency
open class UIViewController: UIResponder, UITraitEnvironment, UIContentContainer, UIFocusEnvironment {
    public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init() }
    public required init?(coder: NSCoder) { _uiStub() }
    public convenience override init() { self.init(nibName: nil, bundle: nil) }
    open var view: UIView!
    open func loadView() { _uiStub() }
    open func viewDidLoad() { _uiStub() }
    open func viewWillAppear(_ animated: Bool) { _uiStub() }
    open func viewDidAppear(_ animated: Bool) { _uiStub() }
    open func viewWillDisappear(_ animated: Bool) { _uiStub() }
    open func viewDidDisappear(_ animated: Bool) { _uiStub() }
    open func viewDidLayoutSubviews() { _uiStub() }
    open var title: String?
    open var traitCollection: UITraitCollection { _uiStub() }
    open var presentedViewController: UIViewController? { _uiStub() }
    open var presentingViewController: UIViewController? { _uiStub() }
    open var parent: UIViewController? { _uiStub() }
    open var children: [UIViewController] { _uiStub() }
    open var preferredContentSize: CGSize = .zero
    open var modalPresentationStyle: UIModalPresentationStyle = .automatic
    open var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
    open var preferredStatusBarStyle: UIStatusBarStyle { _uiStub() }
    open var prefersStatusBarHidden: Bool { _uiStub() }
    open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) { _uiStub() }
    open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) { _uiStub() }
    open func addChild(_ childController: UIViewController) { _uiStub() }
    open func removeFromParent() { _uiStub() }
    open func didMove(toParent parent: UIViewController?) { _uiStub() }
    open func willMove(toParent parent: UIViewController?) { _uiStub() }
    open func setNeedsStatusBarAppearanceUpdate() { _uiStub() }
}

public enum UIModalPresentationStyle: Int, @unchecked Sendable {
    case fullScreen = 0, pageSheet, formSheet, currentContext, custom, overFullScreen, overCurrentContext, popover
    case none = -1
    case automatic = -2
}

public enum UIStatusBarStyle: Int, @unchecked Sendable {
    case `default` = 0, lightContent = 1, darkContent = 3
}

public enum UIStatusBarAnimation: Int, @unchecked Sendable {
    case none = 0, fade, slide
}

// MARK: - Text input traits (UITextInputTraits.h, UITextInput.h)

public enum UIKeyboardType: Int, @unchecked Sendable {
    case `default` = 0, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad,
         emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
    public static var alphabet: UIKeyboardType { .asciiCapable }
}

public enum UITextAutocapitalizationType: Int, @unchecked Sendable {
    case none = 0, words, sentences, allCharacters
}

public enum UITextAutocorrectionType: Int, @unchecked Sendable {
    case `default` = 0, no, yes
}

public enum UIReturnKeyType: Int, @unchecked Sendable {
    case `default` = 0, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue`
}

public struct UITextContentType: RawRepresentable, Hashable, @unchecked Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static var name: UITextContentType { _uiStub() }
    public static var namePrefix: UITextContentType { _uiStub() }
    public static var givenName: UITextContentType { _uiStub() }
    public static var middleName: UITextContentType { _uiStub() }
    public static var familyName: UITextContentType { _uiStub() }
    public static var nameSuffix: UITextContentType { _uiStub() }
    public static var nickname: UITextContentType { _uiStub() }
    public static var jobTitle: UITextContentType { _uiStub() }
    public static var organizationName: UITextContentType { _uiStub() }
    public static var location: UITextContentType { _uiStub() }
    public static var fullStreetAddress: UITextContentType { _uiStub() }
    public static var streetAddressLine1: UITextContentType { _uiStub() }
    public static var streetAddressLine2: UITextContentType { _uiStub() }
    public static var addressCity: UITextContentType { _uiStub() }
    public static var addressState: UITextContentType { _uiStub() }
    public static var addressCityAndState: UITextContentType { _uiStub() }
    public static var sublocality: UITextContentType { _uiStub() }
    public static var countryName: UITextContentType { _uiStub() }
    public static var postalCode: UITextContentType { _uiStub() }
    public static var telephoneNumber: UITextContentType { _uiStub() }
    public static var emailAddress: UITextContentType { _uiStub() }
    public static var URL: UITextContentType { _uiStub() }
    public static var creditCardNumber: UITextContentType { _uiStub() }
    public static var username: UITextContentType { _uiStub() }
    public static var password: UITextContentType { _uiStub() }
    public static var newPassword: UITextContentType { _uiStub() }
    public static var oneTimeCode: UITextContentType { _uiStub() }
    public static var dateTime: UITextContentType { _uiStub() }
    public static var flightNumber: UITextContentType { _uiStub() }
    public static var shipmentTrackingNumber: UITextContentType { _uiStub() }
}

// MARK: - Scenes (UIScene.h, UIWindowScene.h, UISceneSession.h)

@MainActor @preconcurrency
open class UIScene: UIResponder {
    public enum ActivationState: Int, @unchecked Sendable { case unattached = -1, foregroundActive = 0, foregroundInactive, background }
    open var activationState: UIScene.ActivationState { _uiStub() }
    open var session: UISceneSession { _uiStub() }
    open var title: String!
    open var delegate: (any UISceneDelegate)?
}

@MainActor @preconcurrency
open class UIWindowScene: UIScene {
    open var windows: [UIWindow] { _uiStub() }
    open var keyWindow: UIWindow? { _uiStub() }
    open var screen: UIScreen { _uiStub() }
    open var traitCollection: UITraitCollection { _uiStub() }
}

@MainActor @preconcurrency
open class UISceneSession: NSObject {
    open var persistentIdentifier: String { _uiStub() }
    open var scene: UIScene? { _uiStub() }
}

@MainActor @preconcurrency
public protocol UISceneDelegate: NSObjectProtocol {}

@MainActor @preconcurrency
public protocol UIWindowSceneDelegate: UISceneDelegate {}

// MARK: - UIApplication (UIApplication.h, NS_SWIFT_UI_ACTOR)

public enum UIApplicationState: Int, @unchecked Sendable {
    case active = 0, inactive, background
}

public enum UIBackgroundRefreshStatus: Int, @unchecked Sendable {
    case restricted = 0, denied, available
}

public struct UIBackgroundTaskIdentifier: RawRepresentable, Hashable, @unchecked Sendable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static var invalid: UIBackgroundTaskIdentifier { _uiStub() }
}

@MainActor @preconcurrency
open class UIApplication: UIResponder {
    /// @property(class, readonly) UIApplication *sharedApplication NS_EXTENSION_UNAVAILABLE_IOS(...)
    @available(KBAppOnly)
    open class var shared: UIApplication { _uiStub() }

    public struct OpenExternalURLOptionsKey: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static var universalLinksOnly: OpenExternalURLOptionsKey { _uiStub() }
        public static var eventAttribution: OpenExternalURLOptionsKey { _uiStub() }
    }
    public struct LaunchOptionsKey: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static var url: LaunchOptionsKey { _uiStub() }
        public static var sourceApplication: LaunchOptionsKey { _uiStub() }
        public static var remoteNotification: LaunchOptionsKey { _uiStub() }
        public static var annotation: LaunchOptionsKey { _uiStub() }
        public static var location: LaunchOptionsKey { _uiStub() }
        public static var userActivityDictionary: LaunchOptionsKey { _uiStub() }
        public static var userActivityType: LaunchOptionsKey { _uiStub() }
        public static var shortcutItem: LaunchOptionsKey { _uiStub() }
    }
    public struct OpenURLOptionsKey: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static var sourceApplication: OpenURLOptionsKey { _uiStub() }
        public static var annotation: OpenURLOptionsKey { _uiStub() }
        public static var openInPlace: OpenURLOptionsKey { _uiStub() }
    }

    open var delegate: (any UIApplicationDelegate)?
    /// - (BOOL)canOpenURL:(NSURL *)url NS_SWIFT_NONISOLATED;
    nonisolated open func canOpenURL(_ url: URL) -> Bool { _uiStub() }
    /// - (void)openURL:options:completionHandler:
    open func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: (@MainActor @Sendable (Bool) -> Void)? = nil) { _uiStub() }
    open func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:]) async -> Bool { _uiStub() }
    /// - (BOOL)sendAction:(SEL)action to:(nullable id)target from:(nullable id)sender forEvent:(nullable UIEvent *)event;
    open func sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool { _uiStub() }
    open var applicationState: UIApplicationState { _uiStub() }
    open var backgroundTimeRemaining: TimeInterval { _uiStub() }
    open var backgroundRefreshStatus: UIBackgroundRefreshStatus { _uiStub() }
    nonisolated open var isProtectedDataAvailable: Bool { _uiStub() }
    open var connectedScenes: Set<UIScene> { _uiStub() }
    open var openSessions: Set<UISceneSession> { _uiStub() }
    open var supportsMultipleScenes: Bool { _uiStub() }
    open var isIdleTimerDisabled: Bool = false
    @available(*, deprecated, message: "Use -[UNUserNotificationCenter setBadgeCount:withCompletionHandler:] instead.")
    open var applicationIconBadgeNumber: Int = 0
    open func registerForRemoteNotifications() { _uiStub() }
    open func unregisterForRemoteNotifications() { _uiStub() }
    open var isRegisteredForRemoteNotifications: Bool { _uiStub() }
    open func beginBackgroundTask(withName taskName: String?, expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil) -> UIBackgroundTaskIdentifier { _uiStub() }
    open func beginBackgroundTask(expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil) -> UIBackgroundTaskIdentifier { _uiStub() }
    open func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) { _uiStub() }
    /// UIApplication (UIAlternateApplicationIcons) – NS_EXTENSION_UNAVAILABLE
    @available(KBAppOnly)
    open var supportsAlternateIcons: Bool { _uiStub() }
    @available(KBAppOnly)
    open var alternateIconName: String? { _uiStub() }
    @available(KBAppOnly)
    open func setAlternateIconName(_ alternateIconName: String?, completionHandler: (@MainActor @Sendable ((any Error)?) -> Void)? = nil) { _uiStub() }
    @available(KBAppOnly)
    open func setAlternateIconName(_ alternateIconName: String?) async throws { _uiStub() }

    /// UIKIT_EXTERN NSString *const UIApplicationOpenSettingsURLString NS_SWIFT_NONISOLATED;
    nonisolated public class var openSettingsURLString: String { _uiStub() }
    nonisolated public class var openNotificationSettingsURLString: String { _uiStub() }
    nonisolated public class var openDefaultApplicationsSettingsURLString: String { _uiStub() }
    // Notifications (NSNotificationName constants, NS_SWIFT_NONISOLATED)
    nonisolated public class var didEnterBackgroundNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var willEnterForegroundNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var didFinishLaunchingNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var didBecomeActiveNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var willResignActiveNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var didReceiveMemoryWarningNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var willTerminateNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var significantTimeChangeNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var protectedDataWillBecomeUnavailableNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var protectedDataDidBecomeAvailableNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var backgroundRefreshStatusDidChangeNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var userDidTakeScreenshotNotification: NSNotification.Name { _uiStub() }
}

/// UIApplicationDelegate: all requirements are @optional in ObjC; modelled as
/// requirements with default implementations so any subset can be implemented.
@MainActor @preconcurrency
public protocol UIApplicationDelegate: NSObjectProtocol {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    func applicationWillResignActive(_ application: UIApplication)
    func applicationDidEnterBackground(_ application: UIApplication)
    func applicationWillEnterForeground(_ application: UIApplication)
    func applicationWillTerminate(_ application: UIApplication)
    func applicationDidReceiveMemoryWarning(_ application: UIApplication)
    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication)
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error)
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void)
}

extension UIApplicationDelegate {
    public func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    public func applicationDidBecomeActive(_ application: UIApplication) {}
    public func applicationWillResignActive(_ application: UIApplication) {}
    public func applicationDidEnterBackground(_ application: UIApplication) {}
    public func applicationWillEnterForeground(_ application: UIApplication) {}
    public func applicationWillTerminate(_ application: UIApplication) {}
    public func applicationDidReceiveMemoryWarning(_ application: UIApplication) {}
    public func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {}
    public func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {}
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {}
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {}
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult { .noData }
    public func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration { _uiStub() }
    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool { false }
    public func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {}
}

public enum UIBackgroundFetchResult: UInt, @unchecked Sendable {
    case newData = 0, noData, failed
}

@MainActor @preconcurrency
public protocol UIUserActivityRestoring: NSObjectProtocol {}

extension UIScene {
    @MainActor @preconcurrency
    open class ConnectionOptions: NSObject {
        open var urlContexts: Set<UIOpenURLContext> { _uiStub() }
        open var userActivities: Set<NSUserActivity> { _uiStub() }
    }
}

@MainActor @preconcurrency
open class UIOpenURLContext: NSObject {
    open var url: URL { _uiStub() }
}

@MainActor @preconcurrency
open class UISceneConfiguration: NSObject {
    public init(name: String?, sessionRole: UISceneSession.Role) { super.init() }
    open var delegateClass: AnyClass?
}

extension UISceneSession {
    public struct Role: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static var windowApplication: Role { _uiStub() }
    }
}

// MARK: - UIDevice (UIDevice.h, NS_SWIFT_UI_ACTOR)

public enum UIDeviceOrientation: Int, @unchecked Sendable {
    case unknown = 0, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown
    public var isPortrait: Bool { _uiStub() }
    public var isLandscape: Bool { _uiStub() }
    public var isFlat: Bool { _uiStub() }
}

@MainActor @preconcurrency
open class UIDevice: NSObject {
    public enum BatteryState: Int, @unchecked Sendable { case unknown = 0, unplugged, charging, full }
    open class var current: UIDevice { _uiStub() }
    open var name: String { _uiStub() }
    open var model: String { _uiStub() }
    open var localizedModel: String { _uiStub() }
    open var systemName: String { _uiStub() }
    open var systemVersion: String { _uiStub() }
    open var orientation: UIDeviceOrientation { _uiStub() }
    open var identifierForVendor: UUID? { _uiStub() }
    open var isBatteryMonitoringEnabled: Bool = false
    open var batteryState: UIDevice.BatteryState { _uiStub() }
    open var batteryLevel: Float { _uiStub() }
    open var isMultitaskingSupported: Bool { _uiStub() }
    open var userInterfaceIdiom: UIUserInterfaceIdiom { _uiStub() }
    open func playInputClick() { _uiStub() }
    nonisolated public class var orientationDidChangeNotification: NSNotification.Name { _uiStub() }
    nonisolated public class var batteryStateDidChangeNotification: NSNotification.Name { _uiStub() }
}

// MARK: - UIPasteboard (UIPasteboard.h, NS_SWIFT_SENDABLE)

open class UIPasteboard: NSObject, @unchecked Sendable {
    public struct Name: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static var general: Name { _uiStub() }
    }
    open class var general: UIPasteboard { _uiStub() }
    public init?(name pasteboardName: UIPasteboard.Name, create: Bool) { super.init() }
    open var name: UIPasteboard.Name { _uiStub() }
    open var changeCount: Int { _uiStub() }
    open var types: [String] { _uiStub() }
    open func data(forPasteboardType pasteboardType: String) -> Data? { _uiStub() }
    open func value(forPasteboardType pasteboardType: String) -> Any? { _uiStub() }
    open func setValue(_ value: Any, forPasteboardType pasteboardType: String) { _uiStub() }
    open func setData(_ data: Data, forPasteboardType pasteboardType: String) { _uiStub() }
    open var items: [[String: Any]] = []
    open func addItems(_ items: [[String: Any]]) { _uiStub() }
    open var string: String?
    open var strings: [String]?
    open var url: URL?
    open var urls: [URL]?
    open var image: UIImage?
    open var images: [UIImage]?
    open var color: UIColor?
    open var hasStrings: Bool { _uiStub() }
    open var hasURLs: Bool { _uiStub() }
    open var hasImages: Bool { _uiStub() }
    open var hasColors: Bool { _uiStub() }
    nonisolated public class var changedNotification: NSNotification.Name { _uiStub() }
}

// MARK: - Haptics (UIFeedbackGenerator.h, NS_SWIFT_UI_ACTOR)

@MainActor @preconcurrency
open class UIFeedbackGenerator: NSObject {
    public override init() { super.init() }
    open func prepare() { _uiStub() }
}

@MainActor @preconcurrency
open class UIImpactFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackStyle: Int, @unchecked Sendable { case light = 0, medium, heavy, soft, rigid }
    public init(style: UIImpactFeedbackGenerator.FeedbackStyle) { super.init() }
    public override init() { super.init() }
    open func impactOccurred() { _uiStub() }
    open func impactOccurred(intensity: CGFloat) { _uiStub() }
}

@MainActor @preconcurrency
open class UINotificationFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackType: Int, @unchecked Sendable { case success = 0, warning, error }
    open func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) { _uiStub() }
}

@MainActor @preconcurrency
open class UISelectionFeedbackGenerator: UIFeedbackGenerator {
    open func selectionChanged() { _uiStub() }
}

// MARK: - Accessibility (UIAccessibility.h, UIAccessibilityConstants.h)

public enum UIAccessibility {
    public struct Notification: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static var announcement: Notification { _uiStub() }
        public static var screenChanged: Notification { _uiStub() }
        public static var layoutChanged: Notification { _uiStub() }
        public static var pageScrolled: Notification { _uiStub() }
    }
    @MainActor public static func post(notification: UIAccessibility.Notification, argument: Any?) { _uiStub() }
    public static var isVoiceOverRunning: Bool { _uiStub() }
    public static var isReduceMotionEnabled: Bool { _uiStub() }
    public static var isReduceTransparencyEnabled: Bool { _uiStub() }
    public static var isBoldTextEnabled: Bool { _uiStub() }
    public static var isDarkerSystemColorsEnabled: Bool { _uiStub() }
    public static var shouldDifferentiateWithoutColor: Bool { _uiStub() }
    public static var voiceOverStatusDidChangeNotification: NSNotification.Name { _uiStub() }
    public static var reduceMotionStatusDidChangeNotification: NSNotification.Name { _uiStub() }
}

// MARK: - Activity view controller (UIActivityViewController.h)

@MainActor @preconcurrency
open class UIActivity: NSObject {
    public struct ActivityType: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
}

@MainActor @preconcurrency
open class UIActivityViewController: UIViewController {
    public init(activityItems: [Any], applicationActivities: [UIActivity]?) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var excludedActivityTypes: [UIActivity.ActivityType]?
    public typealias CompletionWithItemsHandler = (UIActivity.ActivityType?, Bool, [Any]?, (any Error)?) -> Void
    open var completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler?
}
