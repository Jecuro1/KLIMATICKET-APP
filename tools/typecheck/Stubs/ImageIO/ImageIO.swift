// Hand-written stand-in for ImageIO (C API, ImageIO.framework/Headers), names as
// imported into Swift for the iOS 26 SDK. CF types are aliases (see FoundationShim_ObjC).

@_exported import Foundation
@_exported import FoundationShim
@_exported import CoreGraphics

@inline(never) @usableFromInline func _ioStub() -> Never { fatalError("type-check stub") }

open class CGImageSource: @unchecked Sendable {}
open class CGImageDestination: @unchecked Sendable {}
open class CGImageMetadata: @unchecked Sendable {}

// CGImageSource.h
public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? { _ioStub() }
public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? { _ioStub() }
public func CGImageSourceGetCount(_ isrc: CGImageSource) -> Int { _ioStub() }
public func CGImageSourceGetType(_ isrc: CGImageSource) -> CFString? { _ioStub() }
public func CGImageSourceCreateImageAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? { _ioStub() }
public func CGImageSourceCreateThumbnailAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? { _ioStub() }
public func CGImageSourceCopyPropertiesAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CFDictionary? { _ioStub() }

public let kCGImageSourceCreateThumbnailFromImageIfAbsent: CFString = "kCGImageSourceCreateThumbnailFromImageIfAbsent"
public let kCGImageSourceCreateThumbnailFromImageAlways: CFString = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceThumbnailMaxPixelSize: CFString = "kCGImageSourceThumbnailMaxPixelSize"
public let kCGImageSourceCreateThumbnailWithTransform: CFString = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceShouldCache: CFString = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldCacheImmediately: CFString = "kCGImageSourceShouldCacheImmediately"
public let kCGImageSourceTypeIdentifierHint: CFString = "kCGImageSourceTypeIdentifierHint"
public let kCGImagePropertyOrientation: CFString = "Orientation"
public let kCGImagePropertyPixelWidth: CFString = "PixelWidth"
public let kCGImagePropertyPixelHeight: CFString = "PixelHeight"

// CGImageDestination.h
public func CGImageDestinationCreateWithData(_ data: CFMutableData, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? { _ioStub() }
public func CGImageDestinationCreateWithURL(_ url: CFURL, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? { _ioStub() }
public func CGImageDestinationAddImage(_ idst: CGImageDestination, _ image: CGImage, _ properties: CFDictionary?) { _ioStub() }
public func CGImageDestinationAddImageFromSource(_ idst: CGImageDestination, _ isrc: CGImageSource, _ index: Int, _ properties: CFDictionary?) { _ioStub() }
public func CGImageDestinationSetProperties(_ idst: CGImageDestination, _ properties: CFDictionary?) { _ioStub() }
public func CGImageDestinationFinalize(_ idst: CGImageDestination) -> Bool { _ioStub() }

public let kCGImageDestinationLossyCompressionQuality: CFString = "kCGImageDestinationLossyCompressionQuality"
public let kCGImageDestinationBackgroundColor: CFString = "kCGImageDestinationBackgroundColor"
public let kCGImageDestinationImageMaxPixelSize: CFString = "kCGImageDestinationImageMaxPixelSize"
