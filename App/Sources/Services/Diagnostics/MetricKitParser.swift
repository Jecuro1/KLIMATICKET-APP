import Foundation
import MetricKit

/// Turns MetricKit payloads into `DiagnosticsEvent`s (crash, hang, CPU/disk exceptions, slow launches) and the
/// daily metric highlights. The raw JSON is stored as well – the developer symbolicates the call stacks with the
/// build's dSYM (CI artifact `dSYM-<build>`).
enum MetricKitParser {
    static let executableName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "KlimaBilanz"

    static func fileName(for payload: MXDiagnosticPayload) -> (name: String, data: Data) {
        let data = payload.jsonRepresentation()
        return ("diagnostic-\(DiagnosticsTime.stamp(payload.timeStampEnd))-\(DiagnosticsHash.fnv1a(data)).json", data)
    }

    static func fileName(for payload: MXMetricPayload) -> (name: String, data: Data) {
        let data = payload.jsonRepresentation()
        return ("metrics-\(DiagnosticsTime.stamp(payload.timeStampEnd))-\(DiagnosticsHash.fnv1a(data)).json", data)
    }

    static func events(from payload: MXDiagnosticPayload, file: String) -> [DiagnosticsEvent] {
        let date = payload.timeStampBegin
        var events: [DiagnosticsEvent] = []

        for crash in payload.crashDiagnostics ?? [] {
            let json = crash.jsonRepresentation()
            let type = crash.exceptionType?.intValue
            let signal = crash.signal?.intValue
            var parts = [machExceptionName(type), signalName(signal)].compactMap { $0 }
            let frames = topFrames(crash.callStackTree.jsonRepresentation())
            if let app = frames.app { parts.append(app) }
            if let top = frames.top, top != frames.app { parts.append("oben: \(top)") }
            if let reason = crash.exceptionReason {
                parts.append("\(reason.exceptionName): \(reason.composedMessage.prefix(160))")
            }
            if let termination = crash.terminationReason, !termination.isEmpty {
                parts.append(String(termination.prefix(120)))
            }
            events.append(DiagnosticsEvent(
                id: "mk-crash-\(DiagnosticsHash.fnv1a(json))", kind: .crash, source: .metricKit, date: date,
                title: crashTitle(type: type, signal: signal, termination: crash.terminationReason),
                detail: parts.joined(separator: " · "),
                appVersion: crash.applicationVersion, build: crash.metaData.applicationBuildVersion, payloadFile: file))
        }

        for hang in payload.hangDiagnostics ?? [] {
            let json = hang.jsonRepresentation()
            let ms = hang.hangDuration.converted(to: .milliseconds).value
            let frames = topFrames(hang.callStackTree.jsonRepresentation())
            events.append(DiagnosticsEvent(
                id: "mk-hang-\(DiagnosticsHash.fnv1a(json))", kind: .hang, source: .metricKit, date: date, durationMs: ms,
                title: "Hänger (iOS-Bericht)", detail: frames.app ?? frames.top,
                appVersion: hang.applicationVersion, build: hang.metaData.applicationBuildVersion, payloadFile: file))
        }

        for cpu in payload.cpuExceptionDiagnostics ?? [] {
            let json = cpu.jsonRepresentation()
            let cpuSeconds = cpu.totalCPUTime.converted(to: .seconds).value
            let sampled = cpu.totalSampledTime.converted(to: .seconds).value
            let frames = topFrames(cpu.callStackTree.jsonRepresentation())
            let detail = ["\(Int(cpuSeconds.rounded())) s CPU in \(Int(sampled.rounded())) s", frames.app ?? frames.top].compactMap { $0 }
            events.append(DiagnosticsEvent(
                id: "mk-cpu-\(DiagnosticsHash.fnv1a(json))", kind: .cpuException, source: .metricKit, date: date,
                title: "Hohe CPU-Last", detail: detail.joined(separator: " · "),
                appVersion: cpu.applicationVersion, build: cpu.metaData.applicationBuildVersion, payloadFile: file))
        }

        for disk in payload.diskWriteExceptionDiagnostics ?? [] {
            let json = disk.jsonRepresentation()
            let megabytes = disk.totalWritesCaused.converted(to: .megabytes).value
            let frames = topFrames(disk.callStackTree.jsonRepresentation())
            let detail = ["\(Int(megabytes.rounded())) MB geschrieben", frames.app ?? frames.top].compactMap { $0 }
            events.append(DiagnosticsEvent(
                id: "mk-disk-\(DiagnosticsHash.fnv1a(json))", kind: .diskWriteException, source: .metricKit, date: date,
                title: "Viele Schreibzugriffe", detail: detail.joined(separator: " · "),
                appVersion: disk.applicationVersion, build: disk.metaData.applicationBuildVersion, payloadFile: file))
        }

        for launch in payload.appLaunchDiagnostics ?? [] {
            let json = launch.jsonRepresentation()
            let ms = launch.launchDuration.converted(to: .milliseconds).value
            let frames = topFrames(launch.callStackTree.jsonRepresentation())
            events.append(DiagnosticsEvent(
                id: "mk-launch-\(DiagnosticsHash.fnv1a(json))", kind: .slowLaunch, source: .metricKit, date: date, durationMs: ms,
                title: "Langsamer Start", detail: frames.app ?? frames.top,
                appVersion: launch.applicationVersion, build: launch.metaData.applicationBuildVersion, payloadFile: file))
        }
        return events
    }

    static func highlights(from payload: MXMetricPayload) -> MetricKitHighlights {
        var highlights = MetricKitHighlights(periodEnd: payload.timeStampEnd)
        if let ratio = payload.animationMetrics?.scrollHitchTimeRatio {
            highlights.scrollHitchTimeRatio = ratio.value
        }
        if let launch = payload.applicationLaunchMetrics {
            highlights.averageTimeToFirstDrawMs = average(launch.histogrammedTimeToFirstDraw)
        }
        if let responsiveness = payload.applicationResponsivenessMetrics {
            highlights.averageHangTimeMs = average(responsiveness.histogrammedApplicationHangTime)
        }
        if let memory = payload.memoryMetrics {
            highlights.peakMemoryMB = memory.peakMemoryUsage.converted(to: .megabytes).value
        }
        return highlights
    }

    /// Mean of a duration histogram (bucket mid-points weighted by their counts), in ms.
    static func average(_ histogram: MXHistogram<UnitDuration>) -> Double? {
        var weighted = 0.0
        var count = 0
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitDuration> {
            let start = bucket.bucketStart.converted(to: .milliseconds).value
            let end = bucket.bucketEnd.converted(to: .milliseconds).value
            weighted += (start + end) / 2 * Double(bucket.bucketCount)
            count += bucket.bucketCount
        }
        return count > 0 ? weighted / Double(count) : nil
    }

    // MARK: Call stacks

    /// Topmost frame of the attributed thread, and the topmost frame inside the app binary
    /// ("KlimaBilanz +0x1a2b3c" – symbolicate with `atos -o <dSYM> -l 0x100000000 <0x100000000 + offset>`).
    static func topFrames(_ treeJSON: Data) -> (top: String?, app: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: treeJSON) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]] else { return (nil, nil) }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first
        var top: String?
        var depth = 0
        while let current = frame, depth < 512 {
            let binary = current["binaryName"] as? String ?? "?"
            let offset = (current["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value ?? 0
            let text = "\(binary) +0x\(String(offset, radix: 16))"
            if top == nil { top = text }
            if binary == executableName { return (top, text) }
            frame = (current["subFrames"] as? [[String: Any]])?.first
            depth += 1
        }
        return (top, nil)
    }

    // MARK: Names

    static func crashTitle(type: Int?, signal: Int?, termination: String?) -> String {
        if let termination, termination.lowercased().contains("8badf00d") { return "Von iOS beendet – App hing zu lange" }
        switch type {
        case 1: return "Speicherzugriffsfehler"
        case 2: return "Ungültige Anweisung"
        case 3: return "Rechenfehler"
        case 6: return "Swift-Laufzeitfehler"
        case 10: return "Abbruch"
        case 11: return "Ressourcenlimit überschritten"
        case 12: return "Geschützte Ressource verletzt"
        default: break
        }
        switch signal {
        case 5: return "Swift-Laufzeitfehler"
        case 6: return "Abbruch"
        case 9: return "Von iOS beendet"
        case 10, 11: return "Speicherzugriffsfehler"
        default: return "Absturz"
        }
    }

    static func machExceptionName(_ type: Int?) -> String? {
        guard let type else { return nil }
        let names = [1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE",
                     6: "EXC_BREAKPOINT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY"]
        return names[type] ?? "EXC \(type)"
    }

    static func signalName(_ signal: Int?) -> String? {
        guard let signal else { return nil }
        let names = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV",
                     13: "SIGPIPE", 15: "SIGTERM"]
        return names[signal] ?? "SIG \(signal)"
    }
}
