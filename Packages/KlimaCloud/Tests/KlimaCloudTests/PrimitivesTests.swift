import XCTest
@testable import KlimaCloud

final class TimestampTests: XCTestCase {
    func testCanonicalFormatAndMicroseconds() {
        let raw = "2026-10-09T06:45:00.000001Z"
        let date = APITimestamp.date(from: raw)!
        XCTAssertEqual(APITimestamp.string(from: date), raw)
        XCTAssertEqual(APITimestamp.string(from: Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000000Z")
        XCTAssertEqual(APITimestamp.string(from: Date(timeIntervalSince1970: -0.5)), "1969-12-31T23:59:59.500000Z")
    }

    func testEveryMicrosecondOfASecondRoundTrips() {
        let base = APITimestamp.date(from: "2026-03-01T07:12:33Z")!.timeIntervalSince1970
        for micro in stride(from: 0, to: 1_000_000, by: 7919) {
            let date = Date(timeIntervalSince1970: base + Double(micro) / 1_000_000)
            let string = APITimestamp.string(from: date)
            XCTAssertEqual(APITimestamp.string(from: APITimestamp.date(from: string)!), string)
            XCTAssertTrue(string.hasSuffix(String(format: ".%06dZ", micro)), string)
        }
    }

    func testOffsetForms() {
        let utc = "2026-10-08T03:50:12.500000Z"
        for form in ["2026-10-08T05:50:12.500000+02:00", "2026-10-08T05:50:12.5+0200", "2026-10-08T05:50:12.500+02",
                     "2026-10-08 05:50:12.500000+02:00", "2026-10-08t03:50:12.500000z", "2026-10-08T01:50:12.5-02:00",
                     "2026-10-08T05:50:12,5+02:00:00", "2026-10-08T03:50:12.5000009Z"] {
            XCTAssertEqual(APITimestamp.date(from: form).map(APITimestamp.string(from:)), utc, form)
        }
        XCTAssertEqual(APITimestamp.date(from: "2026-10-08T03:50Z").map(APITimestamp.string(from:)), "2026-10-08T03:50:00.000000Z")
        XCTAssertEqual(APITimestamp.date(from: "2026-10-08").map(APITimestamp.string(from:)), "2026-10-08T00:00:00.000000Z")
    }

    func testRejectsGarbage() {
        for bad in ["", "2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-10-08T25:00:00Z", "2026-10-08T03:50:12.Z",
                    "2026-10-08T03:50:12Zjunk", "10/08/2026", "2026-10-08T03:50:12+2"] {
            XCTAssertNil(APITimestamp.date(from: bad), bad)
        }
        XCTAssertNotNil(APITimestamp.date(from: "2024-02-29T00:00:00Z"))
    }

    func testCodersUseCanonicalStrings() throws {
        struct Box: Codable { var at: Date }
        let date = APITimestamp.date(from: "2026-10-09T12:00:00.123456Z")!
        let json = String(data: try CloudCoding.encoder.encode(Box(at: date)), encoding: .utf8)!
        XCTAssertEqual(json, #"{"at":"2026-10-09T12:00:00.123456Z"}"#)
        let back = try CloudCoding.decoder.decode(Box.self, from: Data(#"{"at":"2026-10-09T14:00:00.123456+02:00"}"#.utf8))
        XCTAssertEqual(APITimestamp.string(from: back.at), "2026-10-09T12:00:00.123456Z")
        XCTAssertThrowsError(try CloudCoding.decoder.decode(Box.self, from: Data(#"{"at":"gestern"}"#.utf8)))
    }
}

final class CryptoTests: XCTestCase {
    private let vectors: [(String, String)] = [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
    ]

    func testPortableSHA256AgainstNISTVectors() {
        for (input, expected) in vectors {
            XCTAssertEqual(PKCE.hex(SHA256Hasher.portable(Data(input.utf8))), expected, input)
        }
        XCTAssertEqual(PKCE.hex(SHA256Hasher.portable(Data(repeating: 0x61, count: 1_000_000))),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        // Padding edge cases (55, 56, 63, 64 bytes) must agree with the platform implementation where there is one.
        for length in [55, 56, 63, 64, 65, 119, 120] {
            let data = Data((0..<length).map { UInt8($0 & 0xff) })
            XCTAssertEqual(SHA256Hasher.portable(data), SHA256Hasher.hash(data), "length \(length)")
        }
    }

    /// The public API (CryptoKit on Apple platforms, the portable code on Linux) against the same vectors.
    func testPublicSHA256AgainstNISTVectors() {
        for (input, expected) in vectors {
            XCTAssertEqual(PKCE.sha256Hex(input), expected, input)
        }
    }

    func testPKCEAgainstRFC7636AppendixB() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierStateAndChallengeShapes() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var seen = Set<String>()
        for _ in 0..<50 {
            let verifier = PKCE.makeVerifier()
            XCTAssertEqual(verifier.count, 64)
            XCTAssertTrue(verifier.unicodeScalars.allSatisfy(allowed.contains))
            let challenge = PKCE.challenge(for: verifier)
            XCTAssertEqual(challenge.count, 43)
            XCTAssertTrue(challenge.unicodeScalars.allSatisfy(allowed.contains))
            seen.insert(verifier)
        }
        XCTAssertEqual(seen.count, 50)
        XCTAssertEqual(PKCE.randomURLSafe(byteCount: 24).count, 32)
        XCTAssertEqual(PKCE.randomURLSafe(byteCount: 32).count, 43)
        XCTAssertEqual(PKCE.base64URL(Data([0xfb, 0xff, 0xfe])), "-__-")
    }
}

final class CallbackTests: XCTestCase {
    func testCodeFromQuery() {
        let url = URL(string: "klimabilanz://auth-callback?code=abc_DEF-123&state=s1234567890abcdef")!
        XCTAssertEqual(try WebAuthCallback.parse(url, expectedState: "s1234567890abcdef").get(), "abc_DEF-123")
    }

    func testCodeFromFragment() {
        let url = URL(string: "klimabilanz://auth-callback#state=s1234567890abcdef&code=xyz")!
        XCTAssertEqual(try WebAuthCallback.parse(url, expectedState: "s1234567890abcdef").get(), "xyz")
    }

    func testStateMismatchAndMissingState() {
        let wrong = URL(string: "klimabilanz://auth-callback?code=abc&state=other")!
        XCTAssertEqual(WebAuthCallback.parse(wrong, expectedState: "mine").failure, .stateMismatch)
        let missing = URL(string: "klimabilanz://auth-callback?code=abc")!
        XCTAssertEqual(WebAuthCallback.parse(missing, expectedState: "mine").failure, .stateMismatch)
    }

    func testMissingCode() {
        let url = URL(string: "klimabilanz://auth-callback?state=mine")!
        XCTAssertEqual(WebAuthCallback.parse(url, expectedState: "mine").failure, .missingCode)
    }

    func testErrors() {
        func parse(_ query: String) -> CloudError? {
            WebAuthCallback.parse(URL(string: "klimabilanz://auth-callback?\(query)")!, expectedState: "mine").failure
        }
        XCTAssertEqual(parse("error=access_denied&state=mine"), .cancelled)
        XCTAssertEqual(parse("error=rate_limited&state=mine"), .rateLimited(retryAfter: nil))
        XCTAssertEqual(parse("error=provider_disabled&state=mine")?.code, "provider_disabled")
        XCTAssertEqual(parse("error=provider_disabled&state=mine")?.message(providerName: "Google"),
                       "Die Anmeldung mit Google ist auf dem Server noch nicht eingerichtet.")
        XCTAssertEqual(parse("error=server_not_configured&state=mine")?.message(providerName: nil),
                       "Der Server ist noch nicht fertig eingerichtet.")
        // "+" is a space, %2B a literal plus; control characters are removed.
        XCTAssertEqual(parse("error=provider_error&error_description=AADSTS50011%3A+Redirect+URI+%2B+mismatch%0A&state=mine"),
                       .authorization("AADSTS50011: Redirect URI + mismatch"))
        // Our own English descriptions are never shown.
        XCTAssertEqual(parse("error=invalid_id_token&error_description=nonce+mismatch&state=mine"), .authorization(""))
        XCTAssertEqual(parse("error=invalid_id_token&state=mine")?.errorDescription,
                       "Die Anmeldung hat nicht geklappt. Bitte versuch es noch einmal.")
        // An error with somebody else's state is still a state mismatch; without a state it is reported as is.
        XCTAssertEqual(parse("error=access_denied&state=theirs"), .stateMismatch)
        XCTAssertEqual(parse("error=access_denied"), .cancelled)
    }

    func testFirstOccurrenceWins() {
        let url = URL(string: "klimabilanz://auth-callback?code=first&state=mine#code=second")!
        XCTAssertEqual(try WebAuthCallback.parse(url, expectedState: "mine").get(), "first")
    }

    func testSanitizeCapsLength() {
        XCTAssertEqual(WebAuthCallback.sanitize(String(repeating: "x", count: 500)).count, 200)
        XCTAssertEqual(WebAuthCallback.sanitize("a\u{0}b\u{7}  c\r\nd"), "a b c d")
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
