// Hand-written stand-in for PDFKit (Objective-C, PDFKit.framework/Headers).
// PDFView derives from UIView, so it is main-actor isolated like any UIView.

@_exported import Foundation
@_exported import FoundationShim
@_exported import UIKit

@inline(never) @usableFromInline func _pdfStub() -> Never { fatalError("type-check stub") }

/// PDFKitPlatform.h: PDFEdgeInsets is UIEdgeInsets on iOS
public typealias PDFEdgeInsets = UIEdgeInsets

public enum PDFDisplayMode: Int, @unchecked Sendable {
    case singlePage = 0, singlePageContinuous, twoUp, twoUpContinuous
}

public enum PDFDisplayDirection: Int, @unchecked Sendable {
    case vertical = 0, horizontal
}

public enum PDFDisplayBox: Int, @unchecked Sendable {
    case mediaBox = 0, cropBox, bleedBox, trimBox, artBox
}

public enum PDFInterpolationQuality: Int, @unchecked Sendable {
    case none = 0, low, high
}

open class PDFPage: NSObject, NSCopying, @unchecked Sendable {
    public override init() { super.init() }
    public init?(image: UIImage) { super.init() }
    public init?(image: UIImage, options: [String: Any] = [:]) { super.init() }
    open func copy(with zone: NSZone? = nil) -> Any { _pdfStub() }
    open weak var document: PDFDocument? { _pdfStub() }
    open var label: String? { _pdfStub() }
    open var rotation: Int = 0
    open var string: String? { _pdfStub() }
    open var numberOfCharacters: Int { _pdfStub() }
    open func bounds(for box: PDFDisplayBox) -> CGRect { _pdfStub() }
    open func setBounds(_ bounds: CGRect, for box: PDFDisplayBox) { _pdfStub() }
    open func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> UIImage { _pdfStub() }
    open func draw(with box: PDFDisplayBox, to context: CGContext) { _pdfStub() }
    open var dataRepresentation: Data? { _pdfStub() }
}

public protocol PDFDocumentDelegate: NSObjectProtocol {}

open class PDFDocument: NSObject, NSCopying, @unchecked Sendable {
    public override init() { super.init() }
    public init?(url: URL) { super.init() }
    public init?(data: Data) { super.init() }
    open func copy(with zone: NSZone? = nil) -> Any { _pdfStub() }
    open var documentURL: URL? { _pdfStub() }
    open var documentAttributes: [AnyHashable: Any]?
    open var majorVersion: Int { _pdfStub() }
    open var minorVersion: Int { _pdfStub() }
    open var isEncrypted: Bool { _pdfStub() }
    open var isLocked: Bool { _pdfStub() }
    open func unlock(withPassword password: String) -> Bool { _pdfStub() }
    open var allowsPrinting: Bool { _pdfStub() }
    open var allowsCopying: Bool { _pdfStub() }
    open var string: String? { _pdfStub() }
    open weak var delegate: (any PDFDocumentDelegate)?
    open func dataRepresentation() -> Data? { _pdfStub() }
    open func dataRepresentation(options: [AnyHashable: Any]) -> Data? { _pdfStub() }
    open func write(toFile path: String) -> Bool { _pdfStub() }
    open func write(to url: URL) -> Bool { _pdfStub() }
    open var pageCount: Int { _pdfStub() }
    open func page(at index: Int) -> PDFPage? { _pdfStub() }
    open func index(for page: PDFPage) -> Int { _pdfStub() }
    open func insert(_ page: PDFPage, at index: Int) { _pdfStub() }
    open func removePage(at index: Int) { _pdfStub() }
    open func exchangePage(at indexA: Int, withPageAt indexB: Int) { _pdfStub() }
}

@MainActor @preconcurrency
public protocol PDFViewDelegate: NSObjectProtocol {}

@MainActor @preconcurrency
open class PDFView: UIView {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { _pdfStub() }
    open var document: PDFDocument?
    open var canGoToFirstPage: Bool { _pdfStub() }
    open func goToFirstPage(_ sender: Any?) { _pdfStub() }
    open var canGoToLastPage: Bool { _pdfStub() }
    open func goToLastPage(_ sender: Any?) { _pdfStub() }
    open var canGoToNextPage: Bool { _pdfStub() }
    open func goToNextPage(_ sender: Any?) { _pdfStub() }
    open var canGoToPreviousPage: Bool { _pdfStub() }
    open func goToPreviousPage(_ sender: Any?) { _pdfStub() }
    open var currentPage: PDFPage? { _pdfStub() }
    /// - (void)goToPage:(PDFPage *)page;
    open func go(to page: PDFPage) { _pdfStub() }
    open func go(to rect: CGRect, on page: PDFPage) { _pdfStub() }
    open var displayMode: PDFDisplayMode = .singlePageContinuous
    open var displayDirection: PDFDisplayDirection = .vertical
    open var displaysPageBreaks: Bool = true
    open var pageBreakMargins: PDFEdgeInsets = .zero
    open var displayBox: PDFDisplayBox = .cropBox
    open var displaysAsBook: Bool = false
    open var displaysRTL: Bool = false
    /// @property (nonatomic, setter=enablePageShadows:) BOOL pageShadowsEnabled
    open var pageShadowsEnabled: Bool = true
    open weak var delegate: (any PDFViewDelegate)?
    open var scaleFactor: CGFloat = 1
    open var minScaleFactor: CGFloat = 0.25
    open var maxScaleFactor: CGFloat = 5
    open var autoScales: Bool = false
    open var scaleFactorForSizeToFit: CGFloat { _pdfStub() }
    open var interpolationQuality: PDFInterpolationQuality = .low
    open func usePageViewController(_ enable: Bool, withViewOptions viewOptions: [AnyHashable: Any]? = nil) { _pdfStub() }
    open var isUsingPageViewController: Bool { _pdfStub() }
    open func layoutDocumentView() { _pdfStub() }
    nonisolated public class var pageChangedNotification: NSNotification.Name { _pdfStub() }
}
