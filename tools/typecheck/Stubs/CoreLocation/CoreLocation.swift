// Hand-written stand-in for CoreLocation (Objective-C framework + small Swift
// overlay). Names/types follow the Clang importer's Swift view of the iOS 26 SDK
// headers (CoreLocation.framework/Headers). Optional delegate methods are
// requirements with default implementations.

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _clStub() -> Never { fatalError("type-check stub") }

public typealias CLLocationDegrees = Double
public typealias CLLocationAccuracy = Double
public typealias CLLocationSpeed = Double
public typealias CLLocationSpeedAccuracy = Double
public typealias CLLocationDirection = Double
public typealias CLLocationDirectionAccuracy = Double
public typealias CLLocationDistance = Double
public typealias CLHeadingComponentValue = Double

/// C struct (CLLocation.h). Not Equatable/Hashable in the SDK.
public struct CLLocationCoordinate2D: @unchecked Sendable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees
    public init() { latitude = 0; longitude = 0 }
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) { self.latitude = latitude; self.longitude = longitude }
}

public func CLLocationCoordinate2DIsValid(_ coord: CLLocationCoordinate2D) -> Bool { _clStub() }
public func CLLocationCoordinate2DMake(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) -> CLLocationCoordinate2D { _clStub() }
public let kCLLocationCoordinate2DInvalid: CLLocationCoordinate2D = CLLocationCoordinate2D()

public let kCLDistanceFilterNone: CLLocationDistance = -1
public let kCLLocationAccuracyBestForNavigation: CLLocationAccuracy = -2
public let kCLLocationAccuracyBest: CLLocationAccuracy = -1
public let kCLLocationAccuracyNearestTenMeters: CLLocationAccuracy = 10
public let kCLLocationAccuracyHundredMeters: CLLocationAccuracy = 100
public let kCLLocationAccuracyKilometer: CLLocationAccuracy = 1000
public let kCLLocationAccuracyThreeKilometers: CLLocationAccuracy = 3000
public let kCLLocationAccuracyReduced: CLLocationAccuracy = 3000
public let CLLocationDistanceMax: CLLocationDistance = .greatestFiniteMagnitude
public let CLTimeIntervalMax: TimeInterval = .greatestFiniteMagnitude

public enum CLAuthorizationStatus: Int32, @unchecked Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorizedAlways = 3
    case authorizedWhenInUse = 4
    @available(*, deprecated, message: "Use kCLAuthorizationStatusAuthorizedAlways")
    public static var authorized: CLAuthorizationStatus { .authorizedAlways }
}

public enum CLAccuracyAuthorization: Int, @unchecked Sendable {
    case fullAccuracy = 0
    case reducedAccuracy = 1
}

public enum CLActivityType: Int, @unchecked Sendable {
    case other = 1, automotiveNavigation, fitness, otherNavigation, airborne
}

public enum CLRegionState: Int, @unchecked Sendable {
    case unknown = 0, inside, outside
}

public enum CLDeviceOrientation: Int32, @unchecked Sendable {
    case unknown = 0, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown
}

open class CLFloor: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _clStub() }
    public required init?(coder: NSCoder) { _clStub() }
    open func encode(with coder: NSCoder) { _clStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _clStub() }
    open var level: Int { _clStub() }
}

open class CLLocation: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _clStub() }
    public required init?(coder: NSCoder) { _clStub() }
    open func encode(with coder: NSCoder) { _clStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _clStub() }
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) { super.init() }
    public init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy, verticalAccuracy vAccuracy: CLLocationAccuracy, timestamp: Date) { super.init() }
    public init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, horizontalAccuracy hAccuracy: CLLocationAccuracy, verticalAccuracy vAccuracy: CLLocationAccuracy, course: CLLocationDirection, speed: CLLocationSpeed, timestamp: Date) { super.init() }
    open var coordinate: CLLocationCoordinate2D { _clStub() }
    open var altitude: CLLocationDistance { _clStub() }
    open var ellipsoidalAltitude: CLLocationDistance { _clStub() }
    open var horizontalAccuracy: CLLocationAccuracy { _clStub() }
    open var verticalAccuracy: CLLocationAccuracy { _clStub() }
    open var course: CLLocationDirection { _clStub() }
    open var courseAccuracy: CLLocationDirectionAccuracy { _clStub() }
    open var speed: CLLocationSpeed { _clStub() }
    open var speedAccuracy: CLLocationSpeedAccuracy { _clStub() }
    open var timestamp: Date { _clStub() }
    open var floor: CLFloor? { _clStub() }
    open func distance(from location: CLLocation) -> CLLocationDistance { _clStub() }
}

open class CLRegion: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _clStub() }
    public required init?(coder: NSCoder) { _clStub() }
    open func encode(with coder: NSCoder) { _clStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _clStub() }
    public override init() { super.init() }
    open var identifier: String { _clStub() }
    open var notifyOnEntry: Bool = true
    open var notifyOnExit: Bool = true
}

open class CLCircularRegion: CLRegion, @unchecked Sendable {
    public init(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) { super.init() }
    public required init?(coder: NSCoder) { _clStub() }
    open var center: CLLocationCoordinate2D { _clStub() }
    open var radius: CLLocationDistance { _clStub() }
    open func contains(_ coordinate: CLLocationCoordinate2D) -> Bool { _clStub() }
}

open class CLHeading: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _clStub() }
    public required init?(coder: NSCoder) { _clStub() }
    open func encode(with coder: NSCoder) { _clStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _clStub() }
    open var magneticHeading: CLLocationDirection { _clStub() }
    open var trueHeading: CLLocationDirection { _clStub() }
    open var headingAccuracy: CLLocationDirection { _clStub() }
    open var timestamp: Date { _clStub() }
}

open class CLVisit: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _clStub() }
    public required init?(coder: NSCoder) { _clStub() }
    open func encode(with coder: NSCoder) { _clStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _clStub() }
    open var arrivalDate: Date { _clStub() }
    open var departureDate: Date { _clStub() }
    open var coordinate: CLLocationCoordinate2D { _clStub() }
    open var horizontalAccuracy: CLLocationAccuracy { _clStub() }
}

open class CLPlacemark: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _clStub() }
    public required init?(coder: NSCoder) { _clStub() }
    open func encode(with coder: NSCoder) { _clStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _clStub() }
    public init(placemark: CLPlacemark) { super.init() }
    open var location: CLLocation? { _clStub() }
    open var region: CLRegion? { _clStub() }
    open var timeZone: TimeZone? { _clStub() }
    open var name: String? { _clStub() }
    open var thoroughfare: String? { _clStub() }
    open var subThoroughfare: String? { _clStub() }
    open var locality: String? { _clStub() }
    open var subLocality: String? { _clStub() }
    open var administrativeArea: String? { _clStub() }
    open var subAdministrativeArea: String? { _clStub() }
    open var postalCode: String? { _clStub() }
    open var isoCountryCode: String? { _clStub() }
    open var country: String? { _clStub() }
}

public typealias CLGeocodeCompletionHandler = ([CLPlacemark]?, (any Error)?) -> Void

open class CLGeocoder: NSObject {
    public override init() { super.init() }
    open var isGeocoding: Bool { _clStub() }
    open func reverseGeocodeLocation(_ location: CLLocation, completionHandler: @escaping CLGeocodeCompletionHandler) { _clStub() }
    open func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] { _clStub() }
    open func geocodeAddressString(_ addressString: String, completionHandler: @escaping CLGeocodeCompletionHandler) { _clStub() }
    open func geocodeAddressString(_ addressString: String) async throws -> [CLPlacemark] { _clStub() }
    open func cancelGeocode() { _clStub() }
}

open class CLLocationManager: NSObject {
    public override init() { super.init() }
    open class func locationServicesEnabled() -> Bool { _clStub() }
    open class func headingAvailable() -> Bool { _clStub() }
    open class func significantLocationChangeMonitoringAvailable() -> Bool { _clStub() }
    /// + (BOOL)isMonitoringAvailableForClass:(Class)regionClass;
    open class func isMonitoringAvailable(for regionClass: AnyClass) -> Bool { _clStub() }
    open class func isRangingAvailable() -> Bool { _clStub() }
    @available(*, deprecated, message: "Use -authorizationStatus")
    open class func authorizationStatus() -> CLAuthorizationStatus { _clStub() }
    open var authorizationStatus: CLAuthorizationStatus { _clStub() }
    open var accuracyAuthorization: CLAccuracyAuthorization { _clStub() }
    open var isAuthorizedForWidgetUpdates: Bool { _clStub() }
    open weak var delegate: (any CLLocationManagerDelegate)?
    open var activityType: CLActivityType = .other
    open var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    open var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    open var pausesLocationUpdatesAutomatically: Bool = true
    open var allowsBackgroundLocationUpdates: Bool = false
    open var showsBackgroundLocationIndicator: Bool = false
    open var location: CLLocation? { _clStub() }
    open var headingFilter: CLLocationDegrees = 1
    open var heading: CLHeading? { _clStub() }
    open var maximumRegionMonitoringDistance: CLLocationDistance { _clStub() }
    open var monitoredRegions: Set<CLRegion> { _clStub() }
    open func requestWhenInUseAuthorization() { _clStub() }
    open func requestAlwaysAuthorization() { _clStub() }
    open func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String, completion: (((any Error)?) -> Void)? = nil) { _clStub() }
    open func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) async throws { _clStub() }
    open func startUpdatingLocation() { _clStub() }
    open func stopUpdatingLocation() { _clStub() }
    open func requestLocation() { _clStub() }
    open func startUpdatingHeading() { _clStub() }
    open func stopUpdatingHeading() { _clStub() }
    open func dismissHeadingCalibrationDisplay() { _clStub() }
    open func startMonitoringSignificantLocationChanges() { _clStub() }
    open func stopMonitoringSignificantLocationChanges() { _clStub() }
    open func startMonitoringVisits() { _clStub() }
    open func stopMonitoringVisits() { _clStub() }
    @available(*, deprecated, message: "Use -[CLMonitor addConditionForMonitoring:identifier:]")
    open func startMonitoring(for region: CLRegion) { _clStub() }
    @available(*, deprecated, message: "Use -[CLMonitor removeConditionFromMonitoringWithIdentifier:]")
    open func stopMonitoring(for region: CLRegion) { _clStub() }
    @available(*, deprecated, message: "Use CLMonitor")
    open func requestState(for region: CLRegion) { _clStub() }
}

public protocol CLLocationManagerDelegate: NSObjectProtocol {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading)
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error)
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error)
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion)
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager)
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: (any Error)?)
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit)
}

extension CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {}
    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {}
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {}
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {}
    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {}
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {}
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: (any Error)?) {}
    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {}
}

/// CLError.h: NS_ERROR_ENUM(kCLErrorDomain) -> struct CLError
public struct CLError: Error, Hashable, @unchecked Sendable {
    public enum Code: Int, @unchecked Sendable {
        case locationUnknown = 0, denied, network, headingFailure, regionMonitoringDenied, regionMonitoringFailure,
             regionMonitoringSetupDelayed, regionMonitoringResponseDelayed, geocodeFoundNoResult, geocodeFoundPartialResult,
             geocodeCanceled, deferredFailed, deferredNotUpdatingLocation, deferredAccuracyTooLow, deferredDistanceFiltered,
             deferredCanceled, rangingUnavailable, rangingFailure, promptDeclined, historicalLocationError = 19
    }
    public var code: Code { _clStub() }
    public static var locationUnknown: Code { .locationUnknown }
    public static var denied: Code { .denied }
    public static var network: Code { .network }
}

// MARK: Swift overlay (CoreLocation.swiftinterface, iOS 17+)

public struct CLLocationUpdate: Sendable {
    public var location: CLLocation? { _clStub() }
    public var isStationary: Bool { _clStub() }
    public var authorizationDenied: Bool { _clStub() }
    public var authorizationDeniedGlobally: Bool { _clStub() }
    public var authorizationRequestInProgress: Bool { _clStub() }
    public var insufficientlyInUse: Bool { _clStub() }
    public var locationUnavailable: Bool { _clStub() }
    public var accuracyLimited: Bool { _clStub() }
    public var serviceSessionRequired: Bool { _clStub() }
    public enum LiveConfiguration: Sendable { case `default`, automotiveNavigation, otherNavigation, fitness, airborne }
    public struct Updates: AsyncSequence, Sendable {
        public typealias Element = CLLocationUpdate
        public struct Iterator: AsyncIteratorProtocol {
            public mutating func next() async throws -> CLLocationUpdate? { _clStub() }
        }
        public func makeAsyncIterator() -> Iterator { _clStub() }
    }
    public static func liveUpdates(_ configuration: CLLocationUpdate.LiveConfiguration = .default) -> CLLocationUpdate.Updates { _clStub() }
}
