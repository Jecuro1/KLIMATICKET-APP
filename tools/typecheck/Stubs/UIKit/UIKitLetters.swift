// UIKit API of the Ticket-Schreiben (docs/TICKET_LETTERS.md): the PDF of a letter drawn with UIGraphicsPDFRenderer and the
// AirPrint sheet. Same conventions as UIKit.swift; declarations follow the iOS 26.4 headers
// (UIGraphicsPDFRenderer.h, NSStringDrawing.h, UIPrintInteractionController.h, UIPrintInfo.h).

import Foundation
import CoreGraphics

// MARK: - Extended string drawing (NSStringDrawing.h)

/// typedef NS_OPTIONS(NSInteger, NSStringDrawingOptions)
public struct NSStringDrawingOptions: OptionSet, @unchecked Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static var usesLineFragmentOrigin: NSStringDrawingOptions { .init(rawValue: 1 << 0) }
    public static var usesFontLeading: NSStringDrawingOptions { .init(rawValue: 1 << 1) }
    public static var usesDeviceMetrics: NSStringDrawingOptions { .init(rawValue: 1 << 3) }
    public static var truncatesLastVisibleLine: NSStringDrawingOptions { .init(rawValue: 1 << 5) }
}

open class NSStringDrawingContext: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    open var minimumScaleFactor: CGFloat = 1
    open var totalBounds: CGRect { _uiStub() }
}

/// @interface NSAttributedString (NSExtendedStringDrawing)
extension NSAttributedString {
    public func draw(at point: CGPoint) { _uiStub() }
    public func draw(in rect: CGRect) { _uiStub() }
    public func draw(with rect: CGRect, options: NSStringDrawingOptions = [], context: NSStringDrawingContext?) { _uiStub() }
    public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], context: NSStringDrawingContext?) -> CGRect { _uiStub() }
}

// MARK: - PDF renderer (UIGraphicsPDFRenderer.h)

open class UIGraphicsPDFRendererFormat: UIGraphicsRendererFormat, @unchecked Sendable {
    /// @property documentInfo – kCGPDFContextTitle, kCGPDFContextAuthor, …
    open var documentInfo: [String: Any] = [:]
}

open class UIGraphicsPDFRendererContext: UIGraphicsRendererContext {
    open var pdfContextBounds: CGRect { _uiStub() }
    open func beginPage() { _uiStub() }
    open func beginPage(withBounds bounds: CGRect, pageInfo: [String: Any]) { _uiStub() }
    open func setURL(_ url: URL, for rect: CGRect) { _uiStub() }
    open func addDestination(withName name: String, at point: CGPoint) { _uiStub() }
    open func setDestinationWithName(_ name: String, for rect: CGRect) { _uiStub() }
}

open class UIGraphicsPDFRenderer: UIGraphicsRenderer, @unchecked Sendable {
    public init(bounds: CGRect, format: UIGraphicsPDFRendererFormat) { super.init(bounds: bounds, format: format) }
    public typealias DrawingActions = (UIGraphicsPDFRendererContext) -> Void
    open func writePDF(to url: URL, withActions actions: (UIGraphicsPDFRendererContext) -> Void) throws { _uiStub() }
    open func pdfData(actions: (UIGraphicsPDFRendererContext) -> Void) -> Data { _uiStub() }
}

// MARK: - Printing (UIPrintInfo.h, UIPrintInteractionController.h)

@MainActor @preconcurrency
open class UIPrintInfo: NSObject {
    public enum OutputType: Int, @unchecked Sendable { case general = 0, photo, grayscale, photoGrayscale }
    public enum Orientation: Int, @unchecked Sendable { case portrait = 0, landscape }
    public enum Duplex: Int, @unchecked Sendable { case none = 0, longEdge, shortEdge }
    open class func printInfo() -> UIPrintInfo { _uiStub() }
    open var printerID: String?
    open var jobName: String = ""
    open var outputType: UIPrintInfo.OutputType = .general
    open var orientation: UIPrintInfo.Orientation = .portrait
    open var duplex: UIPrintInfo.Duplex = .longEdge
}

@MainActor @preconcurrency
open class UIPrintInteractionController: NSObject {
    public typealias CompletionHandler = (UIPrintInteractionController, Bool, (any Error)?) -> Void
    open class var isPrintingAvailable: Bool { _uiStub() }
    open class func canPrint(_ data: Data) -> Bool { _uiStub() }
    open class func canPrint(_ url: URL) -> Bool { _uiStub() }
    open class var shared: UIPrintInteractionController { _uiStub() }
    open var printInfo: UIPrintInfo?
    open var printingItem: Any?
    open var printingItems: [Any]?
    open var showsNumberOfCopies: Bool = true
    open var showsPaperSelectionForLoadedPapers: Bool = false
    @discardableResult
    open func present(animated: Bool, completionHandler completion: UIPrintInteractionController.CompletionHandler? = nil) -> Bool { _uiStub() }
    open func dismiss(animated: Bool) { _uiStub() }
}
