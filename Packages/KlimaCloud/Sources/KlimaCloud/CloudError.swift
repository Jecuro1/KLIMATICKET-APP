import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Errors of the cloud API (contract §3.1 / §6.5). `api(…)`, `upgradeRequired`, `rateLimited`, `schemaOutdated` and
/// `invalidRow` are only produced for answers that carry `X-KB-API: 1`, i.e. that really come from our Worker. Anything
/// else that is not 2xx (captive portal, proxy, Cloudflare error page) becomes `http(status, …)` and never signs out.
public enum CloudError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case invalidResponse
    /// The sign-in redirect carried neither a code nor an error.
    case missingCode
    /// The sign-in redirect did not carry the `state` this app generated.
    case stateMismatch
    /// The user cancelled the sign-in (`error=access_denied`); shown silently.
    case cancelled
    /// The identity provider (or the Worker on its behalf) reported an error; the text is already sanitized.
    case authorization(String)
    /// The refresh token was rejected: sign in again.
    case sessionExpired
    /// The server does not know a column or table this app sends (backend not redeployed).
    case schemaOutdated
    case upgradeRequired(minVersion: String?)
    case rateLimited(retryAfter: Int?)
    /// `422 invalid_row`: a row failed validation; `field` from `details.field`.
    case invalidRow(field: String?)
    /// A JSON error from our API: `{"error": code, "error_description": message}`.
    case api(status: Int, code: String, message: String)
    /// A non-2xx answer that did not come from our API (no `X-KB-API` header), with a short body excerpt.
    case http(Int, String)

    public var status: Int? {
        switch self {
        case .http(let status, _), .api(let status, _, _): status
        case .upgradeRequired: 426
        case .rateLimited: 429
        case .invalidRow: 422
        case .sessionExpired: 400
        default: nil
        }
    }

    public var code: String? {
        switch self {
        case .api(_, let code, _): code
        case .upgradeRequired: "upgrade_required"
        case .rateLimited: "rate_limited"
        case .invalidRow: "invalid_row"
        case .sessionExpired: "invalid_grant"
        case .cancelled: "access_denied"
        default: nil
        }
    }

    /// The access token was not accepted (expired or revoked): refresh once and retry.
    public var isUnauthorized: Bool {
        if case .api(401, "invalid_token", _) = self { return true }
        return false
    }

    /// Only these mean the session is dead (sign out to a local profile): `sessionExpired`, or `400 invalid_grant`
    /// from our API. Being offline, rate limited or behind a captive portal never counts.
    public var isDefinitiveAuthFailure: Bool {
        switch self {
        case .sessionExpired: true
        case .api(400, "invalid_grant", _): true
        default: false
        }
    }

    public var errorDescription: String? { message(providerName: nil) }

    static let signInFailed = "Die Anmeldung hat nicht geklappt. Bitte versuch es noch einmal."
    static let sessionExpiredText = "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an."

    /// German text for the user (§6.5). `providerName` fills in "Die Anmeldung mit {Anbieter} …".
    public func message(providerName: String?) -> String {
        switch self {
        case .notConfigured:
            return "Cloud-Anmeldung ist noch nicht eingerichtet."
        case .invalidResponse:
            return "Unerwartete Antwort vom Server."
        case .missingCode, .stateMismatch:
            return Self.signInFailed
        case .cancelled:
            return "Die Anmeldung wurde abgebrochen."
        case .authorization(let detail):
            return detail.isEmpty ? Self.signInFailed : "\(Self.signInFailed) (\(detail))"
        case .sessionExpired:
            return Self.sessionExpiredText
        case .schemaOutdated:
            return "Der Server ist nicht auf dem neuesten Stand. Bitte das Backend neu bereitstellen (GitHub › Actions › Backend)."
        case .upgradeRequired:
            return "Bitte aktualisiere KlimaBilanz – diese Version wird vom Server nicht mehr unterstützt."
        case .rateLimited:
            return "Zu viele Versuche. Bitte warte kurz und versuch es dann noch einmal."
        case .invalidRow(let field):
            guard let field, !field.isEmpty else { return "Ein Eintrag konnte nicht synchronisiert werden." }
            return "Ein Eintrag konnte nicht synchronisiert werden (ungültiges Feld „\(field)“)."
        case .api(let status, let code, _):
            switch code {
            case "invalid_grant", "invalid_token":
                return Self.sessionExpiredText
            case "provider_disabled":
                return "Die Anmeldung mit \(providerName ?? "diesem Anbieter") ist auf dem Server noch nicht eingerichtet."
            case "server_not_configured":
                return "Der Server ist noch nicht fertig eingerichtet."
            case "invalid_id_token", "provider_error", "invalid_request", "unsupported_grant_type":
                return Self.signInFailed
            case "payload_too_large":
                return "Die Daten sind zu groß für die Synchronisierung."
            case "server_error":
                return "Der Server hat gerade ein Problem (\(status)). Bitte versuch es später noch einmal."
            default:
                return "Serverfehler (\(status))."
            }
        case .http(let status, _):
            if status >= 500 { return "Der Server ist gerade nicht erreichbar (HTTP \(status))." }
            return "Unerwartete Antwort vom Server (HTTP \(status)). Bist du in einem WLAN mit Anmeldeseite?"
        }
    }

    /// User-facing text for any error of a cloud operation (network errors keep the app's existing texts).
    public static func userMessage(for error: Error, providerName: String? = nil) -> String {
        if let error = error as? CloudError { return error.message(providerName: providerName) }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "Keine Internetverbindung."
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed:
                return "Der Server ist gerade nicht erreichbar."
            default:
                return error.localizedDescription
            }
        }
        if error is DecodingError { return "Unerwartete Daten vom Server." }
        return error.localizedDescription
    }
}

/// An already-worded failure (e.g. "account deletion not supported by this server").
public struct CloudFailure: LocalizedError, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
