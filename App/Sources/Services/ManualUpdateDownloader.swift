import Foundation
import CryptoKit
import KlimaCore

// MARK: settings – Manuell aktualisieren (docs/MANUAL_UPDATE.md)

/// Downloads the release's .ipa inside the app – resumable, verified by size and SHA-256 – so it can be handed to
/// SideStore/AltStore (Teilen) or saved to the Files app. iOS installs no .ipa by itself; this only gets a genuine file
/// onto the iPhone.
///
/// One instance for the app (`shared`): a download keeps running while the user leaves the page or closes the sheet.
/// Everything lives in `Caches/ManualUpdate/` – the .ipa, the resume data of a paused download and `state.json`, so a
/// paused or finished download survives a relaunch. Files of a version that is already installed are removed at launch.
@Observable
@MainActor
final class ManualUpdateDownloader {
    enum Phase: Equatable {
        case idle
        case downloading
        /// Paused by the user or interrupted (offline, app in the background) – `canResume` tells whether the bytes
        /// so far are kept.
        case paused
        case verifying
        case ready(ManualUpdate.Verification)
        case failed(Failure)
    }

    enum Failure: Equatable {
        case offline
        case server
        case storage
        /// Size or checksum did not match – the file was deleted.
        case corrupted
    }

    static let shared = ManualUpdateDownloader()

    private(set) var phase: Phase = .idle
    /// The release this download belongs to.
    private(set) var manifest: UpdateManifest?
    private(set) var received: Int64 = 0
    private(set) var total: Int64?
    /// Remaining seconds at the current speed (nil until a few hundred KB arrived).
    private(set) var secondsLeft: Int?
    /// `.paused` because the connection dropped (not by the user) – "Unterbrochen" instead of "Pausiert".
    private(set) var interrupted = false

    /// The verified .ipa (only in `.ready`).
    var fileURL: URL? {
        guard case .ready = phase, let manifest else { return nil }
        return directory.appendingPathComponent(ManualUpdate.fileName(for: manifest))
    }

    var fraction: Double? {
        if case .ready = phase { return 1 }
        return ManualUpdate.fraction(received: received, total: total)
    }

    var canResume: Bool { resumeData != nil }
    var isBusy: Bool { phase == .downloading || phase == .verifying }

    /// Whether the state belongs to this release (an older download is not offered for a newer one).
    func matches(_ other: UpdateManifest?) -> Bool {
        guard let manifest, let other else { return false }
        return manifest.version == other.version && manifest.build == other.build
    }

    @ObservationIgnored private var resumeData: Data?
    @ObservationIgnored private var task: URLSessionDownloadTask?
    /// Set when the running task continues from resume data: a refused resume (expired link) restarts once from zero.
    @ObservationIgnored private var resumedFromData = false
    @ObservationIgnored private var speed = SpeedMeter()
    @ObservationIgnored private var cachedSession: URLSession?

    private var session: URLSession {
        if let cachedSession { return cachedSession }
        let owner = WeakOwner(self)
        let delegate = ManualUpdateSessionDelegate { event in
            // In order, on the main thread – progress, finish and completion of one task must not overtake each other.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { owner.value?.handle(event) }
            }
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "KlimaBilanz.ManualUpdate"
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        cachedSession = session
        return session
    }

    private let directory: URL
    private let isDemo: Bool

    init(isDemo: Bool = false) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        directory = caches.appendingPathComponent("ManualUpdate", isDirectory: true)
        self.isDemo = isDemo
        if !isDemo && !LaunchMode.isScreenshot { restore() }
    }

    // MARK: Actions

    /// Starts – or continues – the download of `release`. A different release replaces whatever was kept.
    func start(_ release: UpdateManifest) {
        guard !isBusy, let url = URL(string: release.downloadURL), url.scheme == "https" || url.scheme == "http" else { return }
        if !matches(release) {
            discardFiles()
            manifest = release
            received = 0
            total = ManualUpdate.expectedSize(release)
        }
        guard !isDemo else { phase = .downloading; return }
        speed = SpeedMeter()
        secondsLeft = nil
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
            resumedFromData = true
        } else {
            received = 0
            task = session.downloadTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
            resumedFromData = false
        }
        self.resumeData = nil
        self.task = task
        interrupted = false
        phase = .downloading
        persist()
        task.resume()
    }

    /// Keeps the bytes so far; `start` continues where it stopped.
    func pause() {
        guard phase == .downloading, let task else { return }
        self.task = nil
        interrupted = false
        let owner = WeakOwner(self)
        task.cancel(byProducingResumeData: { data in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = owner.value else { return }
                    self.resumeData = data
                    self.phase = .paused
                    self.secondsLeft = nil
                    self.persist()
                }
            }
        })
    }

    /// Stops and forgets the download (and a finished file).
    func discard() {
        task?.cancel()
        task = nil
        discardFiles()
        manifest = nil
        received = 0
        total = nil
        secondsLeft = nil
        phase = .idle
    }

    // MARK: Session events

    fileprivate enum Event: Sendable {
        case progress(task: Int, written: Int64, expected: Int64)
        case resumed(task: Int, offset: Int64, expected: Int64)
        /// The finished file is already moved to `partialURL` (the delegate must move it before returning).
        case finished(task: Int, moved: Bool, httpStatus: Int)
        case completed(task: Int, error: NSError?, resumeData: Data?)
    }

    private func handle(_ event: Event) {
        guard let current = task?.taskIdentifier else { return }
        switch event {
        case .progress(let id, let written, let expected):
            guard id == current else { return }
            update(written: written, expected: expected)
        case .resumed(let id, let offset, let expected):
            guard id == current else { return }
            update(written: offset, expected: expected)
        case .finished(let id, let moved, let status):
            guard id == current else { return }
            task = nil
            guard (200...299).contains(status) else {
                fail(.server, keepResumeData: nil)
                return
            }
            guard moved else { fail(.storage, keepResumeData: nil); return }
            Task { await verify() }
        case .completed(let id, let error, let data):
            guard id == current, let error else { return }
            task = nil
            if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled, data == nil { return }
            if resumedFromData, data == nil, let manifest {
                // The resume was refused (the signed download link expired): start over once.
                resumedFromData = false
                received = 0
                start(manifest)
                return
            }
            let offline: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                                     NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDataNotAllowed,
                                     NSURLErrorInternationalRoamingOff, NSURLErrorCancelled]
            if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) {
                fail(.storage, keepResumeData: nil)
            } else {
                fail(offline.contains(error.code) || data != nil ? .offline : .server, keepResumeData: data)
            }
        }
    }

    private func update(written: Int64, expected: Int64) {
        received = written
        if total == nil, let manifest { total = ManualUpdate.expectedSize(manifest, announced: expected) }
        if let total, let rate = speed.add(bytes: written), rate > 0 {
            secondsLeft = max(1, Int((Double(total - written) / rate).rounded(.up)))
        }
    }

    private func fail(_ failure: Failure, keepResumeData data: Data?) {
        resumeData = data
        secondsLeft = nil
        interrupted = data != nil
        phase = data != nil ? .paused : .failed(failure)
        if data == nil { try? FileManager.default.removeItem(at: resumeURL) }
        persist()
    }

    /// Size and SHA-256 off the main thread (24 MB: well under a second), then the file takes its final name.
    private func verify() async {
        guard let manifest else { return }
        phase = .verifying
        let partial = partialURL
        let final = directory.appendingPathComponent(ManualUpdate.fileName(for: manifest))
        let (size, checksum) = await Task.detached(priority: .userInitiated) { Self.measure(partial) }.value
        let result = ManualUpdate.verify(manifest: manifest, actualSize: size, actualChecksum: checksum)
        switch result {
        case .verified, .unverifiable:
            do {
                try? FileManager.default.removeItem(at: final)
                try FileManager.default.moveItem(at: partial, to: final)
                received = size
                total = size
                phase = .ready(result)
                persist()
            } catch {
                fail(.storage, keepResumeData: nil)
            }
        case .sizeMismatch, .checksumMismatch:
            try? FileManager.default.removeItem(at: partial)
            received = 0
            fail(.corrupted, keepResumeData: nil)
        }
    }

    nonisolated private static func measure(_ url: URL) -> (Int64, String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (0, nil) }
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            size += Int64(chunk.count)
        }
        let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (size, checksum)
    }

    // MARK: Files

    private var partialURL: URL { Self.partialDestination }
    private var resumeURL: URL { directory.appendingPathComponent("download.resume") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    private struct Saved: Codable {
        var manifest: UpdateManifest
        var received: Int64
        var total: Int64?
        var verified: Bool?
        var checked: Bool?
    }

    /// Where the delegate moves a finished download (it runs before `handle` and must not touch main-actor state).
    nonisolated fileprivate static var partialDestination: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("ManualUpdate", isDirectory: true).appendingPathComponent("download.partial")
    }

    private func persist() {
        guard !isDemo, let manifest else { return }
        var saved = Saved(manifest: manifest, received: received, total: total)
        if case .ready(let verification) = phase {
            saved.checked = true
            saved.verified = verification == .verified
        }
        let resumeData = self.resumeData
        let directory = self.directory, stateURL = self.stateURL, resumeURL = self.resumeURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(saved) { try? data.write(to: stateURL, options: .atomic) }
            if let resumeData { try? resumeData.write(to: resumeURL, options: .atomic) }
        }
    }

    /// Launch: a finished file or paused download of a release that is not installed yet comes back; anything older goes.
    private func restore() {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            if fm.fileExists(atPath: directory.path) { try? fm.removeItem(at: directory) }
            return
        }
        let installed = SemanticVersion(AppConfig.appVersion) ?? SemanticVersion(major: 1)
        if ManualUpdate.isStale(fileVersion: saved.manifest.version, fileBuild: saved.manifest.build,
                                installed: installed, installedBuild: AppConfig.buildNumber) {
            try? fm.removeItem(at: directory)
            return
        }
        manifest = saved.manifest
        total = saved.total
        let final = directory.appendingPathComponent(ManualUpdate.fileName(for: saved.manifest))
        if saved.checked == true, let size = (try? fm.attributesOfItem(atPath: final.path))?[.size] as? NSNumber,
           ManualUpdate.expectedSize(saved.manifest).map({ $0 == size.int64Value }) ?? true {
            received = size.int64Value
            phase = .ready(saved.verified == true ? .verified : .unverifiable)
        } else if let resume = try? Data(contentsOf: resumeURL) {
            resumeData = resume
            received = saved.received
            phase = .paused
        } else {
            manifest = nil
            total = nil
            try? fm.removeItem(at: directory)
        }
    }

    private func discardFiles() {
        resumeData = nil
        guard !isDemo else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Screenshots & previews

    /// A downloader frozen in one state (CI screenshot routes `manualUpdate*`, no network).
    static func demo(_ phase: Phase, manifest: UpdateManifest, fraction: Double = 0) -> ManualUpdateDownloader {
        let demo = ManualUpdateDownloader(isDemo: true)
        demo.manifest = manifest
        let total = ManualUpdate.expectedSize(manifest) ?? 23_692_125
        demo.total = total
        demo.received = Int64(Double(total) * fraction)
        demo.phase = phase
        if phase == .downloading { demo.secondsLeft = 6 }
        return demo
    }
}

/// The session's delegate outlives nothing: it only ever reaches the downloader weakly.
private final class WeakOwner: @unchecked Sendable {
    weak var value: ManualUpdateDownloader?
    init(_ value: ManualUpdateDownloader) { self.value = value }
}

/// Bytes per second over the last few seconds – for "noch ca. 8 s".
private struct SpeedMeter {
    private var samples: [(time: TimeInterval, bytes: Int64)] = []

    /// Returns the current rate once there is enough to say something sensible.
    mutating func add(bytes: Int64) -> Double? {
        let now = ProcessInfo.processInfo.systemUptime
        samples.append((now, bytes))
        samples.removeAll { now - $0.time > 4 }
        guard let first = samples.first, now - first.time > 0.8, bytes - first.bytes > 200_000 else { return nil }
        return Double(bytes - first.bytes) / (now - first.time)
    }
}

/// URLSession's delegate: forwards events in order and moves the finished file synchronously (URLSession deletes its
/// temporary file as soon as `didFinishDownloadingTo` returns). Progress is thinned to about 30 updates per second.
final class ManualUpdateSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    fileprivate typealias Send = @Sendable (ManualUpdateDownloader.Event) -> Void

    private let send: Send
    /// Only touched on the session's serial delegate queue.
    private var lastProgress: TimeInterval = 0

    fileprivate init(send: @escaping Send) {
        self.send = send
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProgress > 1.0 / 30 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastProgress = now
        send(.progress(task: downloadTask.taskIdentifier, written: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64,
                    expectedTotalBytes: Int64) {
        send(.resumed(task: downloadTask.taskIdentifier, offset: fileOffset, expected: expectedTotalBytes))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        let destination = ManualUpdateDownloader.partialDestination
        let fm = FileManager.default
        var moved = false
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)
            moved = true
        } catch {
            moved = false
        }
        send(.finished(task: downloadTask.taskIdentifier, moved: moved, httpStatus: status))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let nsError = error as NSError?
        let resumeData = nsError?.userInfo["NSURLSessionDownloadTaskResumeData"] as? Data
        send(.completed(task: task.taskIdentifier, error: nsError, resumeData: resumeData))
    }
}
