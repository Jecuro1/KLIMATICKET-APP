// Minimal hand-written stand-in for the Objective-C part of the Accessibility
// framework (AXCustomContent.h, AXAudiograph.h) - only what the SwiftUI / Charts
// interfaces mention. The Swift overlay is generated into Stubs/Accessibility.

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _axStub() -> Never { fatalError("type-check stub") }

open class AXCustomContent: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    /// NS_SWIFT_NAME(AXCustomContent.Importance)
    public enum Importance: UInt, @unchecked Sendable {
        case `default` = 0
        case high = 1
    }
    public static var supportsSecureCoding: Bool { _axStub() }
    public required init?(coder: NSCoder) { _axStub() }
    open func encode(with coder: NSCoder) { _axStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _axStub() }
    public convenience init(label: String, value: String) { _axStub() }
    public convenience init(attributedLabel label: NSAttributedString, attributedValue value: NSAttributedString) { _axStub() }
    open var label: String { _axStub() }
    open var attributedLabel: NSAttributedString { _axStub() }
    open var value: String { _axStub() }
    open var attributedValue: NSAttributedString { _axStub() }
    open var importance: AXCustomContent.Importance = .default
}

public protocol AXDataAxisDescriptor: NSCopying {
    var title: String { get set }
    var attributedTitle: NSAttributedString { get set }
}

open class AXNumericDataAxisDescriptor: NSObject, AXDataAxisDescriptor, @unchecked Sendable {
    public enum ScaleType: Int, @unchecked Sendable { case linear = 0, ln, log10 }
    public init(title: String, range: ClosedRange<Double>, gridlinePositions: [Double], valueDescriptionProvider: @escaping (Double) -> String) { super.init() }
    public init(attributedTitle: NSAttributedString, range: ClosedRange<Double>, gridlinePositions: [Double], valueDescriptionProvider: @escaping (Double) -> String) { super.init() }
    open func copy(with zone: NSZone? = nil) -> Any { _axStub() }
    open var title: String = ""
    open var attributedTitle: NSAttributedString = NSAttributedString(string: "")
    open var scaleType: AXNumericDataAxisDescriptor.ScaleType = .linear
    open var lowerBound: Double = 0
    open var upperBound: Double = 0
    open var gridlinePositions: [Double] = []
}

open class AXCategoricalDataAxisDescriptor: NSObject, AXDataAxisDescriptor, @unchecked Sendable {
    public init(title: String, categoryOrder: [String]) { super.init() }
    public init(attributedTitle: NSAttributedString, categoryOrder: [String]) { super.init() }
    open func copy(with zone: NSZone? = nil) -> Any { _axStub() }
    open var title: String = ""
    open var attributedTitle: NSAttributedString = NSAttributedString(string: "")
    open var categoryOrder: [String] = []
}

open class AXDataPointValue: NSObject, NSCopying, @unchecked Sendable {
    public static func number(_ number: Double) -> Self { _axStub() }
    public static func category(_ category: String) -> Self { _axStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _axStub() }
    open var number: Double = 0
    open var category: String = ""
}

open class AXDataPoint: NSObject, NSCopying, @unchecked Sendable {
    public convenience init(x xValue: String, y yValue: Double?, additionalValues: [AXDataPointValue] = [], label: String? = nil) { _axStub() }
    public convenience init(x xValue: Double, y yValue: Double?, additionalValues: [AXDataPointValue] = [], label: String? = nil) { _axStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _axStub() }
    open var label: String?
}

open class AXDataSeriesDescriptor: NSObject, NSCopying, @unchecked Sendable {
    public init(name: String, isContinuous: Bool, dataPoints: [AXDataPoint]) { super.init() }
    public init(attributedName: NSAttributedString, isContinuous: Bool, dataPoints: [AXDataPoint]) { super.init() }
    open func copy(with zone: NSZone? = nil) -> Any { _axStub() }
    open var name: String?
    open var isContinuous: Bool = false
    open var dataPoints: [AXDataPoint] = []
}

open class AXChartDescriptor: NSObject, NSCopying, @unchecked Sendable {
    public enum ContentDirection: Int, @unchecked Sendable { case leftToRight = 0, rightToLeft, topToBottom, bottomToTop, radialClockwise, radialCounterClockwise }
    public convenience init(title: String?, summary: String?, xAxis: any AXDataAxisDescriptor, yAxis: AXNumericDataAxisDescriptor?, additionalAxes: [any AXDataAxisDescriptor] = [], series: [AXDataSeriesDescriptor]) { _axStub() }
    public convenience init(attributedTitle: NSAttributedString?, summary: String?, xAxis: any AXDataAxisDescriptor, yAxis: AXNumericDataAxisDescriptor, additionalAxes: [any AXDataAxisDescriptor] = [], series: [AXDataSeriesDescriptor]) { _axStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _axStub() }
    open var title: String?
    open var summary: String?
    open var contentDirection: AXChartDescriptor.ContentDirection = .leftToRight
    open var contentFrame: CGRect = .zero
    open var series: [AXDataSeriesDescriptor] = []
}
