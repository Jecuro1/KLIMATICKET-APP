// UIKit API commonly used from SwiftUI code (UIViewRepresentable views, appearance proxies,
// attributed-string attributes, Auto Layout, sheets, image picker). Same conventions as UIKit.swift;
// declarations follow the iOS 26.4 headers (UIKit.framework/Headers/<file>.h named per section).

import QuartzCore
import KBAvailability

// MARK: - Text attributes (NSText.h, NSParagraphStyle.h, NSAttributedString.h, NSShadow.h)

/// typedef NS_ENUM(NSInteger, NSTextAlignment) - iOS values
public enum NSTextAlignment: Int, @unchecked Sendable {
    case left = 0, center = 1, right = 2, justified = 3, natural = 4
}

/// typedef NS_ENUM(NSInteger, NSLineBreakMode)
public enum NSLineBreakMode: Int, @unchecked Sendable {
    case byWordWrapping = 0, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle
}

/// typedef NS_OPTIONS(NSInteger, NSUnderlineStyle)
public struct NSUnderlineStyle: OptionSet, @unchecked Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static var single: NSUnderlineStyle { .init(rawValue: 0x01) }
    public static var thick: NSUnderlineStyle { .init(rawValue: 0x02) }
    public static var double: NSUnderlineStyle { .init(rawValue: 0x09) }
    public static var patternDot: NSUnderlineStyle { .init(rawValue: 0x0100) }
    public static var patternDash: NSUnderlineStyle { .init(rawValue: 0x0200) }
    public static var byWord: NSUnderlineStyle { .init(rawValue: 0x8000) }
}

/// NSParagraphStyle.h (NS_SWIFT_SENDABLE)
open class NSParagraphStyle: NSObject, NSCopying, NSMutableCopying, @unchecked Sendable {
    public override init() { super.init() }
    open class var `default`: NSParagraphStyle { _uiStub() }
    open var lineSpacing: CGFloat { _uiStub() }
    open var paragraphSpacing: CGFloat { _uiStub() }
    open var alignment: NSTextAlignment { _uiStub() }
    open var lineBreakMode: NSLineBreakMode { _uiStub() }
    open var lineHeightMultiple: CGFloat { _uiStub() }
    open var minimumLineHeight: CGFloat { _uiStub() }
    open var maximumLineHeight: CGFloat { _uiStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _uiStub() }
    open func mutableCopy(with zone: NSZone? = nil) -> Any { _uiStub() }
}

open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {
    open override var lineSpacing: CGFloat { get { _uiStub() } set { _uiStub() } }
    open override var paragraphSpacing: CGFloat { get { _uiStub() } set { _uiStub() } }
    open override var alignment: NSTextAlignment { get { _uiStub() } set { _uiStub() } }
    open override var lineBreakMode: NSLineBreakMode { get { _uiStub() } set { _uiStub() } }
    open override var lineHeightMultiple: CGFloat { get { _uiStub() } set { _uiStub() } }
    open override var minimumLineHeight: CGFloat { get { _uiStub() } set { _uiStub() } }
    open override var maximumLineHeight: CGFloat { get { _uiStub() } set { _uiStub() } }
}

/// NSShadow.h
open class NSShadow: NSObject, NSCopying {
    public override init() { super.init() }
    open var shadowOffset: CGSize = .zero
    open var shadowBlurRadius: CGFloat = 0
    open var shadowColor: Any?
    open func copy(with zone: NSZone? = nil) -> Any { _uiStub() }
}

/// UIKIT_EXTERN NSAttributedStringKey const NS<Name>AttributeName (NSAttributedString.h)
extension NSAttributedString.Key {
    public static var font: NSAttributedString.Key { .init("NSFont") }
    public static var paragraphStyle: NSAttributedString.Key { .init("NSParagraphStyle") }
    public static var foregroundColor: NSAttributedString.Key { .init("NSColor") }
    public static var backgroundColor: NSAttributedString.Key { .init("NSBackgroundColor") }
    public static var ligature: NSAttributedString.Key { .init("NSLigature") }
    public static var kern: NSAttributedString.Key { .init("NSKern") }
    public static var tracking: NSAttributedString.Key { .init("NSTracking") }
    public static var strikethroughStyle: NSAttributedString.Key { .init("NSStrikethrough") }
    public static var underlineStyle: NSAttributedString.Key { .init("NSUnderline") }
    public static var strokeColor: NSAttributedString.Key { .init("NSStrokeColor") }
    public static var strokeWidth: NSAttributedString.Key { .init("NSStrokeWidth") }
    public static var shadow: NSAttributedString.Key { .init("NSShadow") }
    public static var link: NSAttributedString.Key { .init("NSLink") }
    public static var baselineOffset: NSAttributedString.Key { .init("NSBaselineOffset") }
    public static var underlineColor: NSAttributedString.Key { .init("NSUnderlineColor") }
    public static var strikethroughColor: NSAttributedString.Key { .init("NSStrikethroughColor") }
}

// MARK: - UIColor drawing (UIColor.h)

extension UIColor {
    /// - (void)set / setFill / setStroke
    public func set() { _uiStub() }
    public func setFill() { _uiStub() }
    public func setStroke() { _uiStub() }
}

// MARK: - UIActivity.ActivityType constants (UIActivity.h)

extension UIActivity.ActivityType {
    public static var postToFacebook: UIActivity.ActivityType { .init("com.apple.UIKit.activity.PostToFacebook") }
    public static var postToTwitter: UIActivity.ActivityType { .init("com.apple.UIKit.activity.PostToTwitter") }
    public static var postToWeibo: UIActivity.ActivityType { .init("com.apple.UIKit.activity.PostToWeibo") }
    public static var message: UIActivity.ActivityType { .init("com.apple.UIKit.activity.Message") }
    public static var mail: UIActivity.ActivityType { .init("com.apple.UIKit.activity.Mail") }
    public static var print: UIActivity.ActivityType { .init("com.apple.UIKit.activity.Print") }
    public static var copyToPasteboard: UIActivity.ActivityType { .init("com.apple.UIKit.activity.CopyToPasteboard") }
    public static var assignToContact: UIActivity.ActivityType { .init("com.apple.UIKit.activity.AssignToContact") }
    public static var saveToCameraRoll: UIActivity.ActivityType { .init("com.apple.UIKit.activity.SaveToCameraRoll") }
    public static var addToReadingList: UIActivity.ActivityType { .init("com.apple.UIKit.activity.AddToReadingList") }
    public static var postToFlickr: UIActivity.ActivityType { .init("com.apple.UIKit.activity.PostToFlickr") }
    public static var postToVimeo: UIActivity.ActivityType { .init("com.apple.UIKit.activity.PostToVimeo") }
    public static var postToTencentWeibo: UIActivity.ActivityType { .init("com.apple.UIKit.activity.TencentWeibo") }
    public static var airDrop: UIActivity.ActivityType { .init("com.apple.UIKit.activity.AirDrop") }
    public static var openInIBooks: UIActivity.ActivityType { .init("com.apple.UIKit.activity.OpenInIBooks") }
    public static var markupAsPDF: UIActivity.ActivityType { .init("com.apple.UIKit.activity.MarkupAsPDF") }
    public static var sharePlay: UIActivity.ActivityType { .init("com.apple.UIKit.activity.SharePlay") }
    public static var collaborationInviteWithLink: UIActivity.ActivityType { .init("com.apple.UIKit.activity.CollaborationInviteWithLink") }
    public static var collaborationCopyLink: UIActivity.ActivityType { .init("com.apple.UIKit.activity.CollaborationCopyLink") }
    public static var addToHomeScreen: UIActivity.ActivityType { .init("com.apple.UIKit.activity.AddToHomeScreen") }
}

// MARK: - Auto Layout (NSLayoutConstraint.h, NSLayoutAnchor.h, UILayoutGuide.h, UIView.h)

/// typedef float UILayoutPriority NS_TYPED_EXTENSIBLE_ENUM (+ UIKit overlay arithmetic)
public struct UILayoutPriority: RawRepresentable, Hashable, Strideable, @unchecked Sendable {
    public var rawValue: Float
    public init(rawValue: Float) { self.rawValue = rawValue }
    public init(_ rawValue: Float) { self.rawValue = rawValue }
    public static let required = UILayoutPriority(1000)
    public static let defaultHigh = UILayoutPriority(750)
    public static let dragThatCanResizeScene = UILayoutPriority(510)
    public static let sceneSizeStayPut = UILayoutPriority(500)
    public static let dragThatCannotResizeScene = UILayoutPriority(490)
    public static let defaultLow = UILayoutPriority(250)
    public static let fittingSizeLevel = UILayoutPriority(50)
    public func distance(to other: UILayoutPriority) -> Float { other.rawValue - rawValue }
    public func advanced(by n: Float) -> UILayoutPriority { UILayoutPriority(rawValue + n) }
    public static func + (lhs: UILayoutPriority, rhs: Float) -> UILayoutPriority { UILayoutPriority(lhs.rawValue + rhs) }
    public static func - (lhs: UILayoutPriority, rhs: Float) -> UILayoutPriority { UILayoutPriority(lhs.rawValue - rhs) }
}

@MainActor @preconcurrency
open class NSLayoutConstraint: NSObject {
    /// typedef NS_ENUM(NSInteger, UILayoutConstraintAxis)
    public enum Axis: Int, @unchecked Sendable { case horizontal = 0, vertical = 1 }
    open class func activate(_ constraints: [NSLayoutConstraint]) { _uiStub() }
    open class func deactivate(_ constraints: [NSLayoutConstraint]) { _uiStub() }
    open var priority: UILayoutPriority = .required
    open var shouldBeArchived: Bool = false
    open var multiplier: CGFloat { _uiStub() }
    open var constant: CGFloat = 0
    open var isActive: Bool = false
    open var identifier: String?
}

@MainActor @preconcurrency
open class NSLayoutAnchor<AnchorType: AnyObject>: NSObject {
    open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { _uiStub() }
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { _uiStub() }
    open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { _uiStub() }
    open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
}

@MainActor @preconcurrency
open class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {
    open func anchorWithOffset(to otherAnchor: NSLayoutXAxisAnchor) -> NSLayoutDimension { _uiStub() }
    open func constraint(equalToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(greaterThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(lessThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _uiStub() }
}

@MainActor @preconcurrency
open class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {
    open func anchorWithOffset(to otherAnchor: NSLayoutYAxisAnchor) -> NSLayoutDimension { _uiStub() }
    open func constraint(equalToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(greaterThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(lessThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _uiStub() }
}

@MainActor @preconcurrency
open class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    open func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
    open func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { _uiStub() }
}

@MainActor @preconcurrency
open class UILayoutGuide: NSObject {
    public override init() { super.init() }
    open var layoutFrame: CGRect { _uiStub() }
    open weak var owningView: UIView?
    open var identifier: String = ""
    open var leadingAnchor: NSLayoutXAxisAnchor { _uiStub() }
    open var trailingAnchor: NSLayoutXAxisAnchor { _uiStub() }
    open var leftAnchor: NSLayoutXAxisAnchor { _uiStub() }
    open var rightAnchor: NSLayoutXAxisAnchor { _uiStub() }
    open var topAnchor: NSLayoutYAxisAnchor { _uiStub() }
    open var bottomAnchor: NSLayoutYAxisAnchor { _uiStub() }
    open var widthAnchor: NSLayoutDimension { _uiStub() }
    open var heightAnchor: NSLayoutDimension { _uiStub() }
    open var centerXAnchor: NSLayoutXAxisAnchor { _uiStub() }
    open var centerYAnchor: NSLayoutYAxisAnchor { _uiStub() }
}

extension UIView {
    public var leadingAnchor: NSLayoutXAxisAnchor { _uiStub() }
    public var trailingAnchor: NSLayoutXAxisAnchor { _uiStub() }
    public var leftAnchor: NSLayoutXAxisAnchor { _uiStub() }
    public var rightAnchor: NSLayoutXAxisAnchor { _uiStub() }
    public var topAnchor: NSLayoutYAxisAnchor { _uiStub() }
    public var bottomAnchor: NSLayoutYAxisAnchor { _uiStub() }
    public var widthAnchor: NSLayoutDimension { _uiStub() }
    public var heightAnchor: NSLayoutDimension { _uiStub() }
    public var centerXAnchor: NSLayoutXAxisAnchor { _uiStub() }
    public var centerYAnchor: NSLayoutYAxisAnchor { _uiStub() }
    public var firstBaselineAnchor: NSLayoutYAxisAnchor { _uiStub() }
    public var lastBaselineAnchor: NSLayoutYAxisAnchor { _uiStub() }
    public var layoutMarginsGuide: UILayoutGuide { _uiStub() }
    public var readableContentGuide: UILayoutGuide { _uiStub() }
    public var safeAreaLayoutGuide: UILayoutGuide { _uiStub() }
    public var constraints: [NSLayoutConstraint] { _uiStub() }
    public func addConstraint(_ constraint: NSLayoutConstraint) { _uiStub() }
    public func addConstraints(_ constraints: [NSLayoutConstraint]) { _uiStub() }
    public func removeConstraint(_ constraint: NSLayoutConstraint) { _uiStub() }
    public func addLayoutGuide(_ layoutGuide: UILayoutGuide) { _uiStub() }
    public func contentHuggingPriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority { _uiStub() }
    public func setContentHuggingPriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) { _uiStub() }
    public func contentCompressionResistancePriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority { _uiStub() }
    public func setContentCompressionResistancePriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) { _uiStub() }
    public func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize { _uiStub() }
    public func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize { _uiStub() }
    public func invalidateIntrinsicContentSize() { _uiStub() }
    public func insertSubview(_ view: UIView, at index: Int) { _uiStub() }
    public func insertSubview(_ view: UIView, belowSubview siblingSubview: UIView) { _uiStub() }
    public func insertSubview(_ view: UIView, aboveSubview siblingSubview: UIView) { _uiStub() }
    public func bringSubviewToFront(_ view: UIView) { _uiStub() }
    public func sendSubviewToBack(_ view: UIView) { _uiStub() }
}

// MARK: - Appearance proxies (UIAppearance.h)

@MainActor @preconcurrency
public protocol UIAppearanceContainer: NSObjectProtocol {}

@MainActor @preconcurrency
public protocol UIAppearance: NSObjectProtocol {
    static func appearance() -> Self
    static func appearance(whenContainedInInstancesOf containerTypes: [any UIAppearanceContainer.Type]) -> Self
}

extension UIView: UIAppearance {
    public class func appearance() -> Self { _uiStub() }
    public class func appearance(whenContainedInInstancesOf containerTypes: [any UIAppearanceContainer.Type]) -> Self { _uiStub() }
}

// MARK: - UIContentSizeCategoryAdjusting.h

@MainActor @preconcurrency
public protocol UIContentSizeCategoryAdjusting: NSObjectProtocol {
    var adjustsFontForContentSizeCategory: Bool { get set }
}

// MARK: - Controls (UIControl.h, UILabel.h, UITextField.h, UIPageControl.h, UIScrollView.h)

@MainActor @preconcurrency
open class UIControl: UIView {
    /// typedef NS_OPTIONS(NSUInteger, UIControlEvents)
    public struct Event: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var touchDown: Event { .init(rawValue: 1 << 0) }
        public static var touchDownRepeat: Event { .init(rawValue: 1 << 1) }
        public static var touchDragInside: Event { .init(rawValue: 1 << 2) }
        public static var touchDragOutside: Event { .init(rawValue: 1 << 3) }
        public static var touchDragEnter: Event { .init(rawValue: 1 << 4) }
        public static var touchDragExit: Event { .init(rawValue: 1 << 5) }
        public static var touchUpInside: Event { .init(rawValue: 1 << 6) }
        public static var touchUpOutside: Event { .init(rawValue: 1 << 7) }
        public static var touchCancel: Event { .init(rawValue: 1 << 8) }
        public static var valueChanged: Event { .init(rawValue: 1 << 12) }
        public static var primaryActionTriggered: Event { .init(rawValue: 1 << 13) }
        public static var menuActionTriggered: Event { .init(rawValue: 1 << 14) }
        public static var editingDidBegin: Event { .init(rawValue: 1 << 16) }
        public static var editingChanged: Event { .init(rawValue: 1 << 17) }
        public static var editingDidEnd: Event { .init(rawValue: 1 << 18) }
        public static var editingDidEndOnExit: Event { .init(rawValue: 1 << 19) }
        public static var allTouchEvents: Event { .init(rawValue: 0x00000FFF) }
        public static var allEditingEvents: Event { .init(rawValue: 0x000F0000) }
        public static var allEvents: Event { .init(rawValue: 0xFFFFFFFF) }
    }
    /// typedef NS_OPTIONS(NSUInteger, UIControlState)
    public struct State: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var normal: State { .init(rawValue: 0) }
        public static var highlighted: State { .init(rawValue: 1 << 0) }
        public static var disabled: State { .init(rawValue: 1 << 1) }
        public static var selected: State { .init(rawValue: 1 << 2) }
        public static var focused: State { .init(rawValue: 1 << 3) }
    }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var isEnabled: Bool = true
    open var isSelected: Bool = false
    open var isHighlighted: Bool = false
    open var state: UIControl.State { _uiStub() }
    open func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) { _uiStub() }
    open func removeTarget(_ target: Any?, action: Selector?, for controlEvents: UIControl.Event) { _uiStub() }
    open func sendActions(for controlEvents: UIControl.Event) { _uiStub() }
}

@MainActor @preconcurrency
open class UILabel: UIView, UIContentSizeCategoryAdjusting {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var text: String?
    /// null_resettable
    open var font: UIFont!
    open var textColor: UIColor!
    open var shadowColor: UIColor?
    open var shadowOffset: CGSize = .zero
    open var textAlignment: NSTextAlignment = .natural
    open var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    open var attributedText: NSAttributedString?
    open var highlightedTextColor: UIColor?
    open var isHighlighted: Bool = false
    open var isEnabled: Bool = true
    open var numberOfLines: Int = 1
    open var adjustsFontSizeToFitWidth: Bool = false
    open var minimumScaleFactor: CGFloat = 0
    open var allowsDefaultTighteningForTruncation: Bool = false
    open var preferredMaxLayoutWidth: CGFloat = 0
    open var adjustsFontForContentSizeCategory: Bool = false
    open func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect { _uiStub() }
    open func drawText(in rect: CGRect) { _uiStub() }
}

@MainActor @preconcurrency
open class UITextField: UIControl, UIContentSizeCategoryAdjusting {
    /// typedef NS_ENUM(NSInteger, UITextBorderStyle)
    public enum BorderStyle: Int, @unchecked Sendable { case none = 0, line, bezel, roundedRect }
    /// typedef NS_ENUM(NSInteger, UITextFieldViewMode)
    public enum ViewMode: Int, @unchecked Sendable { case never = 0, whileEditing, unlessEditing, always }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var text: String?
    open var attributedText: NSAttributedString?
    open var textColor: UIColor?
    open var font: UIFont?
    open var textAlignment: NSTextAlignment = .natural
    open var borderStyle: UITextField.BorderStyle = .none
    open var placeholder: String?
    open var attributedPlaceholder: NSAttributedString?
    open var clearsOnBeginEditing: Bool = false
    open var adjustsFontSizeToFitWidth: Bool = false
    open var minimumFontSize: CGFloat = 0
    open var clearButtonMode: UITextField.ViewMode = .never
    open var leftView: UIView?
    open var leftViewMode: UITextField.ViewMode = .never
    open var rightView: UIView?
    open var rightViewMode: UITextField.ViewMode = .never
    open var isEditing: Bool { _uiStub() }
    open var adjustsFontForContentSizeCategory: Bool = false
    // UITextInputTraits
    open var keyboardType: UIKeyboardType = .default
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var returnKeyType: UIReturnKeyType = .default
    open var isSecureTextEntry: Bool = false
    open var textContentType: UITextContentType!
}

@MainActor @preconcurrency
open class UIPageControl: UIControl {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var numberOfPages: Int = 0
    open var currentPage: Int = 0
    open var hidesForSinglePage: Bool = false
    open var pageIndicatorTintColor: UIColor?
    open var currentPageIndicatorTintColor: UIColor?
}

@MainActor @preconcurrency
public protocol UIScrollViewDelegate: NSObjectProtocol {
    func scrollViewDidScroll(_ scrollView: UIScrollView)
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView)
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool)
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView)
    func viewForZooming(in scrollView: UIScrollView) -> UIView?
    func scrollViewDidZoom(_ scrollView: UIScrollView)
}
extension UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {}
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {}
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {}
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {}
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {}
}

@MainActor @preconcurrency
open class UIScrollView: UIView {
    /// typedef NS_ENUM(NSInteger, UIScrollViewKeyboardDismissMode)
    public enum KeyboardDismissMode: Int, @unchecked Sendable {
        case none = 0, onDrag, interactive, onDragWithAccessory, interactiveWithAccessory
    }
    /// typedef NS_ENUM(NSInteger, UIScrollViewContentInsetAdjustmentBehavior)
    public enum ContentInsetAdjustmentBehavior: Int, @unchecked Sendable {
        case automatic = 0, scrollableAxes, never, always
    }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var contentOffset: CGPoint = .zero
    open var contentSize: CGSize = .zero
    open var contentInset: UIEdgeInsets = .zero
    open var adjustedContentInset: UIEdgeInsets { _uiStub() }
    open var contentInsetAdjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior = .automatic
    open var contentLayoutGuide: UILayoutGuide { _uiStub() }
    open var frameLayoutGuide: UILayoutGuide { _uiStub() }
    open weak var delegate: (any UIScrollViewDelegate)?
    open var isDirectionalLockEnabled: Bool = false
    open var bounces: Bool = true
    open var alwaysBounceVertical: Bool = false
    open var alwaysBounceHorizontal: Bool = false
    open var isPagingEnabled: Bool = false
    open var isScrollEnabled: Bool = true
    open var showsVerticalScrollIndicator: Bool = true
    open var showsHorizontalScrollIndicator: Bool = true
    open var verticalScrollIndicatorInsets: UIEdgeInsets = .zero
    open var horizontalScrollIndicatorInsets: UIEdgeInsets = .zero
    open var keyboardDismissMode: UIScrollView.KeyboardDismissMode = .none
    open var minimumZoomScale: CGFloat = 1
    open var maximumZoomScale: CGFloat = 1
    open var zoomScale: CGFloat = 1
    open var isTracking: Bool { _uiStub() }
    open var isDragging: Bool { _uiStub() }
    open var isDecelerating: Bool { _uiStub() }
    open func setContentOffset(_ contentOffset: CGPoint, animated: Bool) { _uiStub() }
    open func scrollRectToVisible(_ rect: CGRect, animated: Bool) { _uiStub() }
    open func flashScrollIndicators() { _uiStub() }
    open func setZoomScale(_ scale: CGFloat, animated: Bool) { _uiStub() }
}

// MARK: - Bars (UIBarAppearance.h, UINavigationBarAppearance.h, UITabBarAppearance.h, UINavigationBar.h, UITabBar.h)

@MainActor @preconcurrency
open class UIBarAppearance: NSObject, NSCopying {
    public override init() { super.init() }
    public init(idiom: UIUserInterfaceIdiom) { super.init() }
    public init(barAppearance: UIBarAppearance) { super.init() }
    open var idiom: UIUserInterfaceIdiom { _uiStub() }
    open func configureWithDefaultBackground() { _uiStub() }
    open func configureWithOpaqueBackground() { _uiStub() }
    open func configureWithTransparentBackground() { _uiStub() }
    open var backgroundColor: UIColor?
    open var backgroundImage: UIImage?
    open var backgroundImageContentMode: UIView.ContentMode = .scaleToFill
    open var shadowColor: UIColor?
    open var shadowImage: UIImage?
    nonisolated open func copy(with zone: NSZone? = nil) -> Any { _uiStub() }
}

@MainActor @preconcurrency
open class UINavigationBarAppearance: UIBarAppearance {
    open var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var largeTitleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var subtitleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var largeSubtitleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var backIndicatorImage: UIImage { _uiStub() }
    open func setBackIndicatorImage(_ backIndicatorImage: UIImage?, transitionMaskImage backIndicatorTransitionMaskImage: UIImage?) { _uiStub() }
}

@MainActor @preconcurrency
open class UITabBarAppearance: UIBarAppearance {}

@MainActor @preconcurrency
open class UINavigationBar: UIView {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var isTranslucent: Bool = true
    open var prefersLargeTitles: Bool = false
    open var barTintColor: UIColor?
    open var shadowImage: UIImage?
    open var titleTextAttributes: [NSAttributedString.Key: Any]?
    open var largeTitleTextAttributes: [NSAttributedString.Key: Any]?
    open var backIndicatorImage: UIImage?
    open var backIndicatorTransitionMaskImage: UIImage?
    open var standardAppearance: UINavigationBarAppearance { get { _uiStub() } set { _uiStub() } }
    open var compactAppearance: UINavigationBarAppearance?
    open var scrollEdgeAppearance: UINavigationBarAppearance?
    open var compactScrollEdgeAppearance: UINavigationBarAppearance?
}

@MainActor @preconcurrency
open class UITabBar: UIView {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _uiStub() }
    open var barTintColor: UIColor?
    open var unselectedItemTintColor: UIColor?
    open var backgroundImage: UIImage?
    open var shadowImage: UIImage?
    open var isTranslucent: Bool = true
    open var standardAppearance: UITabBarAppearance { get { _uiStub() } set { _uiStub() } }
    open var scrollEdgeAppearance: UITabBarAppearance?
}

// MARK: - Gesture recognizers (UITapGestureRecognizer.h, UILongPressGestureRecognizer.h, UIPanGestureRecognizer.h, UISwipeGestureRecognizer.h)

@MainActor @preconcurrency
open class UITapGestureRecognizer: UIGestureRecognizer {
    open var numberOfTapsRequired: Int = 1
    open var numberOfTouchesRequired: Int = 1
}

@MainActor @preconcurrency
open class UILongPressGestureRecognizer: UIGestureRecognizer {
    open var numberOfTapsRequired: Int = 0
    open var numberOfTouchesRequired: Int = 1
    open var minimumPressDuration: TimeInterval = 0.5
    open var allowableMovement: CGFloat = 10
}

@MainActor @preconcurrency
open class UIPanGestureRecognizer: UIGestureRecognizer {
    open var minimumNumberOfTouches: Int = 1
    open var maximumNumberOfTouches: Int = .max
    open func translation(in view: UIView?) -> CGPoint { _uiStub() }
    open func setTranslation(_ translation: CGPoint, in view: UIView?) { _uiStub() }
    open func velocity(in view: UIView?) -> CGPoint { _uiStub() }
}

@MainActor @preconcurrency
open class UISwipeGestureRecognizer: UIGestureRecognizer {
    /// typedef NS_OPTIONS(NSUInteger, UISwipeGestureRecognizerDirection)
    public struct Direction: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var right: Direction { .init(rawValue: 1 << 0) }
        public static var left: Direction { .init(rawValue: 1 << 1) }
        public static var up: Direction { .init(rawValue: 1 << 2) }
        public static var down: Direction { .init(rawValue: 1 << 3) }
    }
    open var numberOfTouchesRequired: Int = 1
    open var direction: UISwipeGestureRecognizer.Direction = .right
}

// MARK: - Sheets (UIPresentationController.h, UISheetPresentationController.h, UIViewController.h)

@MainActor @preconcurrency
open class UIPresentationController: NSObject {
    open var presentingViewController: UIViewController { _uiStub() }
    open var presentedViewController: UIViewController { _uiStub() }
    open var containerView: UIView? { _uiStub() }
}

@MainActor @preconcurrency
public protocol UISheetPresentationControllerDetentResolutionContext: NSObjectProtocol {
    var containerTraitCollection: UITraitCollection { get }
    var maximumDetentValue: CGFloat { get }
}

@MainActor @preconcurrency
public protocol UISheetPresentationControllerDelegate: NSObjectProtocol {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController)
}
extension UISheetPresentationControllerDelegate {
    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {}
}

@MainActor @preconcurrency
open class UISheetPresentationController: UIPresentationController {
    @MainActor @preconcurrency
    open class Detent: NSObject {
        /// typedef NSString *UISheetPresentationControllerDetentIdentifier NS_TYPED_EXTENSIBLE_ENUM
        public struct Identifier: RawRepresentable, Hashable, @unchecked Sendable {
            public var rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public init(_ rawValue: String) { self.rawValue = rawValue }
            public static let medium = Identifier("com.apple.UIKit.medium")
            public static let large = Identifier("com.apple.UIKit.large")
        }
        open class func medium() -> UISheetPresentationController.Detent { _uiStub() }
        open class func large() -> UISheetPresentationController.Detent { _uiStub() }
        /// Swift refinement of +customDetentWithIdentifier:resolver:
        public static func custom(identifier: UISheetPresentationController.Detent.Identifier? = nil, resolver: @escaping (_ context: any UISheetPresentationControllerDetentResolutionContext) -> CGFloat?) -> UISheetPresentationController.Detent { _uiStub() }
        open var identifier: UISheetPresentationController.Detent.Identifier { _uiStub() }
        open func resolvedValue(in context: any UISheetPresentationControllerDetentResolutionContext) -> CGFloat? { _uiStub() }
    }
    open weak var delegate: (any UISheetPresentationControllerDelegate)?
    open var sourceView: UIView?
    open var prefersPageSizing: Bool = false
    open var prefersEdgeAttachedInCompactHeight: Bool = false
    open var widthFollowsPreferredContentSizeWhenEdgeAttached: Bool = false
    open var prefersGrabberVisible: Bool = false
    open var preferredCornerRadius: CGFloat = 0
    open var detents: [UISheetPresentationController.Detent] = []
    open func invalidateDetents() { _uiStub() }
    open var selectedDetentIdentifier: UISheetPresentationController.Detent.Identifier?
    open var largestUndimmedDetentIdentifier: UISheetPresentationController.Detent.Identifier?
    open var prefersScrollingExpandsWhenScrolledToEdge: Bool = true
    open func animateChanges(_ changes: () -> Void) { _uiStub() }
}

extension UIViewController {
    public var sheetPresentationController: UISheetPresentationController? { _uiStub() }
    public var presentationController: UIPresentationController? { _uiStub() }
    public var navigationController: UINavigationController? { _uiStub() }
}

// MARK: - Navigation & image picker (UINavigationController.h, UIImagePickerController.h)

@MainActor @preconcurrency
public protocol UINavigationControllerDelegate: NSObjectProtocol {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool)
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool)
}
extension UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {}
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {}
}

@MainActor @preconcurrency
open class UINavigationController: UIViewController {
    public init(rootViewController: UIViewController) { super.init(nibName: nil, bundle: nil) }
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil) }
    public required init?(coder: NSCoder) { _uiStub() }
    open func pushViewController(_ viewController: UIViewController, animated: Bool) { _uiStub() }
    @discardableResult open func popViewController(animated: Bool) -> UIViewController? { _uiStub() }
    @discardableResult open func popToRootViewController(animated: Bool) -> [UIViewController]? { _uiStub() }
    open var topViewController: UIViewController? { _uiStub() }
    open var visibleViewController: UIViewController? { _uiStub() }
    open var viewControllers: [UIViewController] = []
    open func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) { _uiStub() }
    open var isNavigationBarHidden: Bool = false
    open func setNavigationBarHidden(_ hidden: Bool, animated: Bool) { _uiStub() }
    open var navigationBar: UINavigationBar { _uiStub() }
    // `weak var delegate: (any UINavigationControllerDelegate)?` is not declared: UIImagePickerController
    // redeclares it with a narrower type, which only the Clang importer can express.
}

@MainActor @preconcurrency
public protocol UIImagePickerControllerDelegate: NSObjectProtocol {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController)
}
extension UIImagePickerControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {}
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {}
}

@MainActor @preconcurrency
open class UIImagePickerController: UINavigationController {
    public enum SourceType: Int, @unchecked Sendable {
        case photoLibrary = 0, camera = 1, savedPhotosAlbum = 2
    }
    public enum QualityType: Int, @unchecked Sendable {
        case typeHigh = 0, typeMedium = 1, typeLow = 2, type640x480 = 3, typeIFrame1280x720 = 4, typeIFrame960x540 = 5
    }
    public enum CameraCaptureMode: Int, @unchecked Sendable { case photo = 0, video = 1 }
    public enum CameraDevice: Int, @unchecked Sendable { case rear = 0, front = 1 }
    public enum CameraFlashMode: Int, @unchecked Sendable { case off = -1, auto = 0, on = 1 }
    /// typedef NSString * UIImagePickerControllerInfoKey NS_TYPED_ENUM
    public struct InfoKey: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let mediaType = InfoKey("UIImagePickerControllerMediaType")
        public static let originalImage = InfoKey("UIImagePickerControllerOriginalImage")
        public static let editedImage = InfoKey("UIImagePickerControllerEditedImage")
        public static let cropRect = InfoKey("UIImagePickerControllerCropRect")
        public static let mediaURL = InfoKey("UIImagePickerControllerMediaURL")
        public static let mediaMetadata = InfoKey("UIImagePickerControllerMediaMetadata")
        public static let livePhoto = InfoKey("UIImagePickerControllerLivePhoto")
        public static let imageURL = InfoKey("UIImagePickerControllerImageURL")
    }
    public init() { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { _uiStub() }
    open class func isSourceTypeAvailable(_ sourceType: UIImagePickerController.SourceType) -> Bool { _uiStub() }
    open class func availableMediaTypes(for sourceType: UIImagePickerController.SourceType) -> [String]? { _uiStub() }
    open class func isCameraDeviceAvailable(_ cameraDevice: UIImagePickerController.CameraDevice) -> Bool { _uiStub() }
    open class func isFlashAvailable(for cameraDevice: UIImagePickerController.CameraDevice) -> Bool { _uiStub() }
    /// @property(nullable,nonatomic,weak) id <UINavigationControllerDelegate, UIImagePickerControllerDelegate> delegate
    open weak var delegate: (any UIImagePickerControllerDelegate & UINavigationControllerDelegate)?
    open var sourceType: UIImagePickerController.SourceType = .photoLibrary
    open var mediaTypes: [String] = []
    open var allowsEditing: Bool = false
    open var videoMaximumDuration: TimeInterval = 600
    open var videoQuality: UIImagePickerController.QualityType = .typeMedium
    open var showsCameraControls: Bool = true
    open var cameraOverlayView: UIView?
    open var cameraViewTransform: CGAffineTransform = .identity
    open func takePicture() { _uiStub() }
    @discardableResult open func startVideoCapture() -> Bool { _uiStub() }
    open func stopVideoCapture() { _uiStub() }
    open var cameraCaptureMode: UIImagePickerController.CameraCaptureMode = .photo
    open var cameraDevice: UIImagePickerController.CameraDevice = .rear
    open var cameraFlashMode: UIImagePickerController.CameraFlashMode = .auto
}
