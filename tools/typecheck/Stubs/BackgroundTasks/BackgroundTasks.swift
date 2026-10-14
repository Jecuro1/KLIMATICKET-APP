// Hand-written stand-in for BackgroundTasks (Objective-C framework, BackgroundTasks.framework/Headers). Covers the API the
// app uses: app refresh tasks (docs/OEBB_LIVE.md §R8, App/Sources/Services/Live/FollowBackgroundRefresh.swift). Swift names
// as imported for iOS 26; the launch handler is a plain (non-Sendable) block.

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _btStub() -> Never { fatalError("type-check stub") }

open class BGTask: NSObject, @unchecked Sendable {
    open var identifier: String { _btStub() }
    open var expirationHandler: (() -> Void)? {
        get { _btStub() }
        set { _btStub() }
    }
    open func setTaskCompleted(success: Bool) { _btStub() }
}

open class BGAppRefreshTask: BGTask, @unchecked Sendable {}

open class BGTaskRequest: NSObject, @unchecked Sendable {
    open var identifier: String
    open var earliestBeginDate: Date?
    public init(identifier: String) {
        self.identifier = identifier
    }
}

open class BGAppRefreshTaskRequest: BGTaskRequest, @unchecked Sendable {}

open class BGTaskScheduler: NSObject, @unchecked Sendable {
    open class var shared: BGTaskScheduler { _btStub() }

    @discardableResult
    open func register(forTaskWithIdentifier identifier: String, using queue: DispatchQueue?,
                       launchHandler: @escaping (BGTask) -> Void) -> Bool { _btStub() }

    open func submit(_ taskRequest: BGTaskRequest) throws { _btStub() }

    open func cancel(taskRequestWithIdentifier identifier: String) { _btStub() }
}

public enum BGTaskSchedulerErrorCode: Int, Sendable {
    case unavailable = 1, tooManyPendingTaskRequests = 2, notPermitted = 3, invalidIdentifier = 4
}
