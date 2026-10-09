import Foundation

/// Parses the redirect `klimabilanz://auth-callback?code=…&state=…` (or `?error=…`) that ends the browser sign-in
/// (contract §2.3). Parameters are read from the query and the fragment, form-decoded (`+` = space).
public enum WebAuthCallback {
    /// The one-time app code, or why there is none:
    /// `.cancelled` (`access_denied`), `.stateMismatch`, `.rateLimited`, `.api(404, "provider_disabled", …)`,
    /// `.api(503, "server_not_configured", …)`, `.authorization(<sanitized provider text>)`, `.missingCode`.
    public static func parse(_ url: URL, expectedState: String) -> Result<String, CloudError> {
        let parameters = self.parameters(url)
        // The Worker puts the app's state on every redirect, errors included. Without it the URL was not produced by
        // this sign-in: a code would be login CSRF, and an error could carry a crafted "provider" text into the app.
        guard let state = parameters["state"], constantTimeEquals(state, expectedState) else {
            return .failure(.stateMismatch)
        }
        if let error = parameters["error"], !error.isEmpty {
            return .failure(map(error: error, description: parameters["error_description"]))
        }
        guard let code = parameters["code"], !code.isEmpty else { return .failure(.missingCode) }
        return .success(code)
    }

    static func map(error: String, description: String?) -> CloudError {
        switch error {
        case "access_denied":
            return .cancelled
        case "rate_limited":
            return .rateLimited(retryAfter: nil)
        case "provider_disabled":
            return .api(status: 404, code: error, message: "")
        case "server_not_configured":
            return .api(status: 503, code: error, message: "")
        case "provider_error":
            return .authorization(sanitize(description ?? ""))
        default:
            // invalid_request, invalid_id_token, server_error, …: our own English descriptions are not shown.
            return .authorization("")
        }
    }

    /// Query and fragment parameters; the first occurrence of a name wins.
    public static func parameters(_ url: URL) -> [String: String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var result: [String: String] = [:]
        for part in [comps.percentEncodedQuery, comps.percentEncodedFragment] {
            guard let part, !part.isEmpty else { continue }
            for pair in part.split(separator: "&", omittingEmptySubsequences: true) {
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = formDecode(pieces[0]), !name.isEmpty, result[name] == nil else { continue }
                result[name] = pieces.count > 1 ? (formDecode(pieces[1]) ?? "") : ""
            }
        }
        return result
    }

    private static func formDecode(_ raw: Substring) -> String? {
        raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    /// Display-safe provider text: no control characters, single spaces, at most 200 characters.
    static func sanitize(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) }
        let collapsed = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(200))
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
