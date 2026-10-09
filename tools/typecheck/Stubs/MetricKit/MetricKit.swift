// Hand-written stand-in for MetricKit (Objective-C, MetricKit.framework/Headers: MXMetricManager.h,
// MXDiagnosticPayload.h, MXDiagnostic.h, MXCrashDiagnostic.h, MXHangDiagnostic.h, MXCPUExceptionDiagnostic.h,
// MXDiskWriteExceptionDiagnostic.h, MXAppLaunchDiagnostic.h, MXCallStackTree.h, MXMetaData.h, MXMetricPayload.h,
// MXHistogram.h, MXAnimationMetric.h, MXAppLaunchMetric.h, MXAppResponsivenessMetric.h, MXMemoryMetric.h).
// Only what the app uses; Swift names as the Clang importer produces them.

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _mxStub() -> Never { fatalError("type-check stub") }

// MARK: Manager

// @protocol MXMetricManagerSubscriber <NSObject> @optional
// - (void)didReceiveMetricPayloads:(NSArray<MXMetricPayload *> *)payloads;          NS_SWIFT_NAME(didReceive(_:))
// - (void)didReceiveDiagnosticPayloads:(NSArray<MXDiagnosticPayload *> *)payloads;  NS_SWIFT_NAME(didReceive(_:))
public protocol MXMetricManagerSubscriber: NSObjectProtocol {
    func didReceive(_ payloads: [MXMetricPayload])
    func didReceive(_ payloads: [MXDiagnosticPayload])
}

extension MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {}
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {}
}

open class MXMetricManager: NSObject, @unchecked Sendable {
    // @property (class, readonly, strong) MXMetricManager *sharedManager;
    open class var shared: MXMetricManager { _mxStub() }
    open var pastPayloads: [MXMetricPayload] { _mxStub() }
    open var pastDiagnosticPayloads: [MXDiagnosticPayload] { _mxStub() }
    open func add(_ subscriber: any MXMetricManagerSubscriber) { _mxStub() }
    open func remove(_ subscriber: any MXMetricManagerSubscriber) { _mxStub() }
}

// MARK: Diagnostics

open class MXMetaData: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open var regionFormat: String { _mxStub() }
    open var osVersion: String { _mxStub() }
    open var deviceType: String { _mxStub() }
    open var applicationBuildVersion: String { _mxStub() }
    open var platformArchitecture: String { _mxStub() }
    open func jsonRepresentation() -> Data { _mxStub() }
    open func dictionaryRepresentation() -> [AnyHashable: Any] { _mxStub() }
}

open class MXCallStackTree: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open func jsonRepresentation() -> Data { _mxStub() }
}

open class MXDiagnostic: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open var metaData: MXMetaData { _mxStub() }
    open var applicationVersion: String { _mxStub() }
    open func jsonRepresentation() -> Data { _mxStub() }
    open func dictionaryRepresentation() -> [AnyHashable: Any] { _mxStub() }
}

open class MXCrashDiagnosticObjectiveCExceptionReason: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open var composedMessage: String { _mxStub() }
    open var formatString: String { _mxStub() }
    open var arguments: [String] { _mxStub() }
    open var exceptionType: String { _mxStub() }
    open var className: String { _mxStub() }
    open var exceptionName: String { _mxStub() }
    open func jsonRepresentation() -> Data { _mxStub() }
}

open class MXCrashDiagnostic: MXDiagnostic, @unchecked Sendable {
    open var callStackTree: MXCallStackTree { _mxStub() }
    open var terminationReason: String? { _mxStub() }
    open var virtualMemoryRegionInfo: String? { _mxStub() }
    open var exceptionType: NSNumber? { _mxStub() }
    open var exceptionCode: NSNumber? { _mxStub() }
    open var signal: NSNumber? { _mxStub() }
    open var exceptionReason: MXCrashDiagnosticObjectiveCExceptionReason? { _mxStub() }
}

open class MXHangDiagnostic: MXDiagnostic, @unchecked Sendable {
    open var callStackTree: MXCallStackTree { _mxStub() }
    open var hangDuration: Measurement<UnitDuration> { _mxStub() }
}

open class MXCPUExceptionDiagnostic: MXDiagnostic, @unchecked Sendable {
    open var callStackTree: MXCallStackTree { _mxStub() }
    open var totalCPUTime: Measurement<UnitDuration> { _mxStub() }
    open var totalSampledTime: Measurement<UnitDuration> { _mxStub() }
}

open class MXDiskWriteExceptionDiagnostic: MXDiagnostic, @unchecked Sendable {
    open var callStackTree: MXCallStackTree { _mxStub() }
    open var totalWritesCaused: Measurement<UnitInformationStorage> { _mxStub() }
}

open class MXAppLaunchDiagnostic: MXDiagnostic, @unchecked Sendable {
    open var callStackTree: MXCallStackTree { _mxStub() }
    open var launchDuration: Measurement<UnitDuration> { _mxStub() }
}

open class MXDiagnosticPayload: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open var cpuExceptionDiagnostics: [MXCPUExceptionDiagnostic]? { _mxStub() }
    open var diskWriteExceptionDiagnostics: [MXDiskWriteExceptionDiagnostic]? { _mxStub() }
    open var hangDiagnostics: [MXHangDiagnostic]? { _mxStub() }
    open var appLaunchDiagnostics: [MXAppLaunchDiagnostic]? { _mxStub() }
    open var crashDiagnostics: [MXCrashDiagnostic]? { _mxStub() }
    open var timeStampBegin: Date { _mxStub() }
    open var timeStampEnd: Date { _mxStub() }
    open func jsonRepresentation() -> Data { _mxStub() }
    open func dictionaryRepresentation() -> [AnyHashable: Any] { _mxStub() }
}

// MARK: Metrics

open class MXHistogramBucket<UnitType: Unit>: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open var bucketStart: Measurement<UnitType> { _mxStub() }
    open var bucketEnd: Measurement<UnitType> { _mxStub() }
    open var bucketCount: Int { _mxStub() }
}

open class MXHistogram<UnitType: Unit>: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open var totalBucketCount: Int { _mxStub() }
    open var bucketEnumerator: NSEnumerator { _mxStub() }
}

open class MXMetric: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open func jsonRepresentation() -> Data { _mxStub() }
    open func dictionaryRepresentation() -> [AnyHashable: Any] { _mxStub() }
}

open class MXAnimationMetric: MXMetric, @unchecked Sendable {
    open var scrollHitchTimeRatio: Measurement<Unit> { _mxStub() }
}

open class MXAppLaunchMetric: MXMetric, @unchecked Sendable {
    open var histogrammedTimeToFirstDraw: MXHistogram<UnitDuration> { _mxStub() }
    open var histogrammedApplicationResumeTime: MXHistogram<UnitDuration> { _mxStub() }
    open var histogrammedOptimizedTimeToFirstDraw: MXHistogram<UnitDuration> { _mxStub() }
    open var histogrammedExtendedLaunch: MXHistogram<UnitDuration> { _mxStub() }
}

open class MXAppResponsivenessMetric: MXMetric, @unchecked Sendable {
    open var histogrammedApplicationHangTime: MXHistogram<UnitDuration> { _mxStub() }
}

open class MXMemoryMetric: MXMetric, @unchecked Sendable {
    open var peakMemoryUsage: Measurement<UnitInformationStorage> { _mxStub() }
}

open class MXMetricPayload: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mxStub() }
    public required init?(coder: NSCoder) { _mxStub() }
    open func encode(with coder: NSCoder) { _mxStub() }
    open var latestApplicationVersion: String { _mxStub() }
    open var includesMultipleApplicationVersions: Bool { _mxStub() }
    open var timeStampBegin: Date { _mxStub() }
    open var timeStampEnd: Date { _mxStub() }
    open var metaData: MXMetaData? { _mxStub() }
    open var applicationLaunchMetrics: MXAppLaunchMetric? { _mxStub() }
    open var applicationResponsivenessMetrics: MXAppResponsivenessMetric? { _mxStub() }
    open var animationMetrics: MXAnimationMetric? { _mxStub() }
    open var memoryMetrics: MXMemoryMetric? { _mxStub() }
    open func jsonRepresentation() -> Data { _mxStub() }
    open func dictionaryRepresentation() -> [AnyHashable: Any] { _mxStub() }
}
