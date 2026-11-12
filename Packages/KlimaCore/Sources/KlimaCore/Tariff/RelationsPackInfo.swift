import Foundation

/// The optional `relationsPack` block of the remote tariffs document: where the current relation-price table (the exact
/// ÖBB Standard-Ticket prices) can be downloaded and how to verify it. Additive – a catalogue without it decodes as before
/// and the app keeps using the table it has.
public struct RelationsPackInfo: Codable, Hashable, Sendable {
    /// Absolute `https` URL, or a path relative to the tariffs document ("relations-pack.bin"), which then lives next to it.
    public var url: String
    /// Lowercase hex SHA-256 of the whole pack file.
    public var sha256: String
    /// Monotonic data version; the pack is installed only when it is higher than the table in use.
    public var version: Int
    /// First day the prices are valid ("2026-12-13"); a pack is not used before that day.
    public var validFrom: String
    /// Exact size of the pack file in bytes.
    public var bytes: Int

    public init(url: String, sha256: String, version: Int, validFrom: String, bytes: Int) {
        self.url = url
        self.sha256 = sha256
        self.version = version
        self.validFrom = validFrom
        self.bytes = bytes
    }

    /// Hosts of the owner's repository (GitHub): a tariffs document on one of them may point to a pack on the others
    /// (release assets, raw files).
    static let repositoryHosts: Set<String> = ["github.com", "raw.githubusercontent.com"]

    /// The download URL: an absolute `https` URL as given, a relative one resolved against the tariffs document.
    /// nil for anything else: other schemes, user info, no tariffs document to anchor it, or a host other than the one
    /// the tariffs document comes from (or, on GitHub, its repository hosts) – the refresh talks only to the owner's host.
    public func resolvedURL(relativeTo tariffsURL: URL?) -> URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512, let tariffsURL, let tariffsHost = tariffsURL.host?.lowercased() else { return nil }
        let resolved: URL?
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            resolved = absolute
        } else {
            resolved = URL(string: trimmed, relativeTo: tariffsURL)?.absoluteURL
        }
        guard let resolved, resolved.scheme?.lowercased() == "https", let host = resolved.host?.lowercased(), !host.isEmpty,
              resolved.user == nil, resolved.password == nil else { return nil }
        let sameHost = host == tariffsHost
        let sameRepositoryHost = Self.repositoryHosts.contains(host) && Self.repositoryHosts.contains(tariffsHost)
        return sameHost || sameRepositoryHost ? resolved : nil
    }
}
