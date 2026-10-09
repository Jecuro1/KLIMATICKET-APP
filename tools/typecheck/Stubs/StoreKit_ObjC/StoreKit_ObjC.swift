// Minimal hand-written stand-in for the Objective-C part of StoreKit
// (StoreKit 1 classes). StoreKit 2 (Product, Transaction, AppStore, ...) is
// generated from the SDK's StoreKit.swiftinterface into Stubs/StoreKit.

@_exported import Foundation
@_exported import FoundationShim
import UIKit

@inline(never) @usableFromInline func _skStub() -> Never { fatalError("type-check stub") }

@MainActor @preconcurrency
open class SKStoreReviewController: NSObject {
    @available(*, deprecated, message: "Use AppStore.requestReview(in:)")
    open class func requestReview(in windowScene: UIWindowScene) { _skStub() }
}

open class SKProduct: NSObject, @unchecked Sendable {}
open class SKPayment: NSObject, @unchecked Sendable {}
open class SKPaymentTransaction: NSObject, @unchecked Sendable {}
open class SKStorefront: NSObject, @unchecked Sendable {
    open var countryCode: String { _skStub() }
    open var identifier: String { _skStub() }
}
