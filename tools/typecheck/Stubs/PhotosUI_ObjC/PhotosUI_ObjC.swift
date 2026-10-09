// Minimal hand-written stand-in for the Objective-C part of PhotosUI
// (PHPickerViewController & friends). The Swift overlay (PHPickerFilter,
// PHPickerConfiguration, ...) is generated into Stubs/PhotosUI, the SwiftUI API
// (PhotosPicker, .photosPicker, PhotosPickerItem) into Stubs/_PhotosUI_SwiftUI.

@_exported import Foundation
@_exported import FoundationShim
import UIKit

@inline(never) @usableFromInline func _phStub() -> Never { fatalError("type-check stub") }

public struct PHPickerCapabilities: OptionSet, @unchecked Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static var search: PHPickerCapabilities { .init(rawValue: 1 << 0) }
    public static var stagingArea: PHPickerCapabilities { .init(rawValue: 1 << 1) }
    public static var collectionNavigation: PHPickerCapabilities { .init(rawValue: 1 << 2) }
    public static var selectionActions: PHPickerCapabilities { .init(rawValue: 1 << 3) }
    public static var sensitivityAnalysisIntervention: PHPickerCapabilities { .init(rawValue: 1 << 4) }
}

open class PHPickerResult: NSObject, @unchecked Sendable {
    open var itemProvider: NSItemProvider { _phStub() }
    open var assetIdentifier: String? { _phStub() }
}

@MainActor @preconcurrency
public protocol PHPickerViewControllerDelegate: AnyObject {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult])
}

@MainActor @preconcurrency
open class PHPickerViewController: UIViewController {
    public required init?(coder: NSCoder) { _phStub() }
    open weak var delegate: (any PHPickerViewControllerDelegate)?
}
