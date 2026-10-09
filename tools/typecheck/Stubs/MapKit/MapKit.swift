// Hand-written stand-in for MapKit's Objective-C / C API (MapKit.framework/Headers).
// The SwiftUI map API (Map, Marker, MapPolyline, ...) comes from the generated
// _MapKit_SwiftUI cross-import overlay.

@_exported import Foundation
@_exported import FoundationShim
@_exported import CoreLocation
import UIKit

@inline(never) @usableFromInline func _mkStub() -> Never { fatalError("type-check stub") }

public struct MKCoordinateSpan: @unchecked Sendable {
    public var latitudeDelta: CLLocationDegrees
    public var longitudeDelta: CLLocationDegrees
    public init() { latitudeDelta = 0; longitudeDelta = 0 }
    public init(latitudeDelta: CLLocationDegrees, longitudeDelta: CLLocationDegrees) { self.latitudeDelta = latitudeDelta; self.longitudeDelta = longitudeDelta }
}

public struct MKCoordinateRegion: @unchecked Sendable {
    public var center: CLLocationCoordinate2D
    public var span: MKCoordinateSpan
    public init() { center = CLLocationCoordinate2D(); span = MKCoordinateSpan() }
    public init(center: CLLocationCoordinate2D, span: MKCoordinateSpan) { self.center = center; self.span = span }
    /// MKCoordinateRegionMakeWithDistance
    public init(center centerCoordinate: CLLocationCoordinate2D, latitudinalMeters: CLLocationDistance, longitudinalMeters: CLLocationDistance) { _mkStub() }
    /// MKCoordinateRegionForMapRect
    public init(_ rect: MKMapRect) { _mkStub() }
}

public struct MKMapPoint: @unchecked Sendable {
    public var x: Double
    public var y: Double
    public init() { x = 0; y = 0 }
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ coordinate: CLLocationCoordinate2D) { _mkStub() }
    public var coordinate: CLLocationCoordinate2D { _mkStub() }
    public func distance(to point: MKMapPoint) -> CLLocationDistance { _mkStub() }
}

public struct MKMapSize: @unchecked Sendable {
    public var width: Double
    public var height: Double
    public init() { width = 0; height = 0 }
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct MKMapRect: @unchecked Sendable {
    public var origin: MKMapPoint
    public var size: MKMapSize
    public init() { origin = MKMapPoint(); size = MKMapSize() }
    public init(origin: MKMapPoint, size: MKMapSize) { self.origin = origin; self.size = size }
    public init(x: Double, y: Double, width: Double, height: Double) { _mkStub() }
    public static var world: MKMapRect { _mkStub() }
    public static var null: MKMapRect { _mkStub() }
    public var minX: Double { _mkStub() }
    public var maxX: Double { _mkStub() }
    public var minY: Double { _mkStub() }
    public var maxY: Double { _mkStub() }
    public var midX: Double { _mkStub() }
    public var midY: Double { _mkStub() }
    public var width: Double { _mkStub() }
    public var height: Double { _mkStub() }
    public var isNull: Bool { _mkStub() }
    public var isEmpty: Bool { _mkStub() }
    public func union(_ rect2: MKMapRect) -> MKMapRect { _mkStub() }
    public func insetBy(dx: Double, dy: Double) -> MKMapRect { _mkStub() }
    public func contains(_ point: MKMapPoint) -> Bool { _mkStub() }
}

public struct MKPointOfInterestCategory: RawRepresentable, Hashable, @unchecked Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static var airport: MKPointOfInterestCategory { _mkStub() }
    public static var publicTransport: MKPointOfInterestCategory { _mkStub() }
    public static var restaurant: MKPointOfInterestCategory { _mkStub() }
    public static var cafe: MKPointOfInterestCategory { _mkStub() }
    public static var hotel: MKPointOfInterestCategory { _mkStub() }
    public static var parking: MKPointOfInterestCategory { _mkStub() }
    public static var park: MKPointOfInterestCategory { _mkStub() }
    public static var nationalPark: MKPointOfInterestCategory { _mkStub() }
    public static var skiing: MKPointOfInterestCategory { _mkStub() }
    public static var hiking: MKPointOfInterestCategory { _mkStub() }
}

public enum MKOverlayLevel: Int, @unchecked Sendable {
    case aboveRoads = 0, aboveLabels
}

public enum MKLookAroundBadgePosition: Int, @unchecked Sendable {
    case topLeading = 0, topTrailing, bottomTrailing
}

public protocol MKAnnotation: NSObjectProtocol {
    var coordinate: CLLocationCoordinate2D { get }
}

public protocol MKOverlay: MKAnnotation {
    var boundingMapRect: MKMapRect { get }
}

open class MKShape: NSObject, MKAnnotation, @unchecked Sendable {
    public override init() { super.init() }
    open var coordinate: CLLocationCoordinate2D { _mkStub() }
    open var title: String?
    open var subtitle: String?
}

open class MKMultiPoint: MKShape, @unchecked Sendable {
    open var pointCount: Int { _mkStub() }
    open func points() -> UnsafeMutablePointer<MKMapPoint> { _mkStub() }
}

open class MKPolyline: MKMultiPoint, MKOverlay, @unchecked Sendable {
    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int) { _mkStub() }
    public convenience init(points: UnsafePointer<MKMapPoint>, count: Int) { _mkStub() }
    open var boundingMapRect: MKMapRect { _mkStub() }
}

open class MKPolygon: MKMultiPoint, MKOverlay, @unchecked Sendable {
    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int) { _mkStub() }
    open var boundingMapRect: MKMapRect { _mkStub() }
}

open class MKCircle: MKShape, MKOverlay, @unchecked Sendable {
    public convenience init(center coord: CLLocationCoordinate2D, radius: CLLocationDistance) { _mkStub() }
    open var radius: CLLocationDistance { _mkStub() }
    open var boundingMapRect: MKMapRect { _mkStub() }
}

open class MKPlacemark: CLPlacemark, MKAnnotation, @unchecked Sendable {
    public init(coordinate: CLLocationCoordinate2D) { _mkStub() }
    public required init?(coder: NSCoder) { _mkStub() }
    open var coordinate: CLLocationCoordinate2D { _mkStub() }
}

open class MKMapItem: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    public init(placemark: MKPlacemark) { super.init() }
    open class func forCurrentLocation() -> MKMapItem { _mkStub() }
    open var placemark: MKPlacemark { _mkStub() }
    open var isCurrentLocation: Bool { _mkStub() }
    open var name: String?
    open var phoneNumber: String?
    open var url: URL?
    open var timeZone: TimeZone?
    open var pointOfInterestCategory: MKPointOfInterestCategory?
    open func openInMaps(launchOptions: [String: Any]? = nil) -> Bool { _mkStub() }
}

open class MKMapItemRequest: NSObject, @unchecked Sendable {}

open class MKRoute: NSObject, @unchecked Sendable {
    open var name: String { _mkStub() }
    open var polyline: MKPolyline { _mkStub() }
    open var distance: CLLocationDistance { _mkStub() }
    open var expectedTravelTime: TimeInterval { _mkStub() }
}

open class MKMapCamera: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _mkStub() }
    public required init?(coder: NSCoder) { _mkStub() }
    public override init() { super.init() }
    open func encode(with coder: NSCoder) { _mkStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _mkStub() }
    open var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    open var centerCoordinateDistance: CLLocationDistance = 0
    open var heading: CLLocationDirection = 0
    open var pitch: CGFloat = 0
}

open class MKLookAroundScene: NSObject, NSCopying, @unchecked Sendable {
    open func copy(with zone: NSZone? = nil) -> Any { _mkStub() }
}
