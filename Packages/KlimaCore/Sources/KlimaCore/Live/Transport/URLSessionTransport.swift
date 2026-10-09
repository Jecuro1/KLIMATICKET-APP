import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Production `HTTPTransport` (SPEC §A2.1): an ephemeral session without cookies or URL cache. Every HTTP status is
/// returned as a response; only transport failures throw (`.offline`, `.timeout`, `.network`). Cancellation is
/// rethrown as `CancellationError`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    /// Ephemeral configuration, no cookie storage, no URLCache, `waitsForConnectivity = false`.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if !canImport(FoundationNetworking)
        config.waitsForConnectivity = false // read-only (always false) in swift-corelibs-foundation
        #endif
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var r = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeout)
        r.httpMethod = request.method
        r.httpShouldHandleCookies = false
        for (name, value) in request.headers { r.setValue(value, forHTTPHeaderField: name) }
        if r.value(forHTTPHeaderField: "Accept-Encoding") == nil { r.setValue("gzip", forHTTPHeaderField: "Accept-Encoding") }
        r.httpBody = request.body
        do {
            let (data, response) = try await session.data(for: r)
            guard let http = response as? HTTPURLResponse else { throw LiveError.network("Keine HTTP-Antwort") }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as LiveError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw LiveError.network(error.localizedDescription)
        }
    }

    /// URLError → LiveError (SPEC §A2.1); `.cancelled` becomes `CancellationError`.
    static func map(_ error: URLError) -> Error {
        switch error.code {
        case .cancelled: return CancellationError()
        case .timedOut: return LiveError.timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: return LiveError.offline
        default: return LiveError.network(error.localizedDescription)
        }
    }
}
