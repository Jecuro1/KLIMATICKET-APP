// Unit tests: crypto helpers, key derivation (pinned vectors from an independent Python implementation),
// timestamps, Apple key parsing, sanitizing.
import { describe, expect, it } from "vitest";
import { unsealAppleToken, sealAppleToken } from "../src/apple";
import {
  base64urlDecode,
  base64urlEncode,
  decodeJwt,
  sha256Base64url,
  sha256Hex,
  signEs256,
  timingSafeEqualString,
  utf8,
} from "../src/crypto";
import { loadKeys } from "../src/keys";
import { appleClientSecret, appleKeyDer, appleSigningKey, providerFlags } from "../src/providers";
import { bucketFor } from "../src/ratelimit";
import { signAccessToken, verifyAccessToken } from "../src/sessions";
import { canonicalFromMs, canonicalTimestamp } from "../src/timestamps";
import { sanitizeText } from "../src/http";
import { versionBelow } from "../src/routes/sync";
import { T0, makeDeps, pem, testEnv } from "./helpers";

const SECRET = "test-only-session-signing-key-0123456789abcdefghijklmnop";

describe("encoding and hashing", () => {
  it("base64url round-trips and rejects non-base64url", () => {
    const bytes = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255]);
    const s = base64urlEncode(bytes);
    expect(s).toBe("AAEC-vv8_f7_");
    expect(base64urlDecode(s)).toEqual(bytes);
    expect(base64urlDecode("ab+c")).toBeNull();
    expect(base64urlDecode("abc=")).toBeNull();
    expect(base64urlDecode("a")).toBeNull();
  });

  it("PKCE S256 matches RFC 7636 appendix B", async () => {
    expect(await sha256Base64url("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")).toBe("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
  });

  it("SHA-256 hex matches the NIST vectors", async () => {
    expect(await sha256Hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    expect(await sha256Hex("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  });

  it("constant-time compare", () => {
    expect(timingSafeEqualString("abc", "abc")).toBe(true);
    expect(timingSafeEqualString("abc", "abd")).toBe(false);
    expect(timingSafeEqualString("abc", "abcd")).toBe(false);
    expect(timingSafeEqualString("", "")).toBe(true);
  });

  it("decodeJwt rejects malformed tokens", () => {
    expect(decodeJwt("a.b")).toBeNull();
    expect(decodeJwt("a.b.c.d")).toBeNull();
    expect(decodeJwt("!!.e30.e30")).toBeNull();
    expect(decodeJwt(".e30.")).toBeNull();
    expect(decodeJwt(`${base64urlEncode(utf8("[]"))}.e30.`)).toBeNull();
    expect(decodeJwt("x".repeat(20_000))).toBeNull();
    expect(decodeJwt("e30.e30.")).not.toBeNull();
  });
});

describe("session key derivation (pinned vectors)", () => {
  it("derives the documented kid and rate-limit bucket (HKDF-SHA256, salt klimabilanz-api)", async () => {
    const keys = (await loadKeys(testEnv({ SESSION_SIGNING_KEY: SECRET, SESSION_SIGNING_KEY_PREVIOUS: undefined })))!;
    expect(keys.current.kid).toBe("94JaU4Dq");
    expect(await bucketFor(keys, "auth_start", "203.0.113.7")).toBe("auth_start:FORaVgqajcfSgMYod9cScI");
  });

  it("signs access tokens byte-identical to the reference implementation", async () => {
    const keys = (await loadKeys(testEnv({ SESSION_SIGNING_KEY: SECRET })))!;
    const jwt = await signAccessToken(keys, "0b9c6a4e-6f5e-4d2a-9a51-3f7d2c1e8b10", "AAAAAAAAAAAAAAAAAAAAAA", T0);
    expect(jwt).toBe(
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Ijk0SmFVNERxIn0." +
        "eyJpc3MiOiJrbGltYWJpbGFuei1hcGkiLCJhdWQiOiJrbGltYWJpbGFuei1pb3MiLCJzdWIiOiIwYjljNmE0ZS02ZjVlLTRkMmEtOWE1MS0zZjdkMmMxZThiMTAiLCJzaWQiOiJBQUFBQUFBQUFBQUFBQUFBQUFBQUFBIiwiaWF0IjoxNzkxNTQ3MjAwLCJleHAiOjE3OTE1NDgxMDAsInYiOjF9." +
        "1Yz0cP7W6Ftx5hNUIcJBqmTUXLv-S5K7NACE_ISyHt8",
    );
  });

  it("returns null for a missing or short key", async () => {
    expect(await loadKeys(testEnv({ SESSION_SIGNING_KEY: undefined }))).toBeNull();
    expect(await loadKeys(testEnv({ SESSION_SIGNING_KEY: "x".repeat(31) }))).toBeNull();
  });

  it("verifies access tokens: exact alg, kid, signature, iss/aud, exp without leeway; previous key verifies only", async () => {
    const keys = (await loadKeys(testEnv()))!;
    const uid = "0b9c6a4e-6f5e-4d2a-9a51-3f7d2c1e8b10";
    const sid = "AAAAAAAAAAAAAAAAAAAAAA";
    const jwt = await signAccessToken(keys, uid, sid, T0);
    expect(await verifyAccessToken(keys, jwt, T0 + 1000)).toEqual({ userId: uid, sessionId: sid });
    expect(await verifyAccessToken(keys, jwt, T0 + 900_000)).toBeNull(); // exp == now → invalid
    expect(await verifyAccessToken(keys, jwt, T0 + 900_000, true)).not.toBeNull(); // logout accepts expired
    expect(await verifyAccessToken(keys, jwt, T0 - 61_000)).toBeNull(); // iat in the future

    const [h, p, s] = jwt.split(".") as [string, string, string];
    const flipped = s.slice(0, -2) + (s.endsWith("A") ? "BA" : "AA");
    expect(await verifyAccessToken(keys, `${h}.${p}.${flipped}`, T0)).toBeNull();
    const none = base64urlEncode(utf8(JSON.stringify({ alg: "none", kid: keys.current.kid })));
    expect(await verifyAccessToken(keys, `${none}.${p}.`, T0)).toBeNull();
    const otherKid = base64urlEncode(utf8(JSON.stringify({ alg: "HS256", typ: "JWT", kid: "zzzzzzzz" })));
    expect(await verifyAccessToken(keys, `${otherKid}.${p}.${s}`, T0)).toBeNull();

    // Rotation: the old key verifies through SESSION_SIGNING_KEY_PREVIOUS, new tokens use the new key.
    const rotated = (await loadKeys(testEnv({ SESSION_SIGNING_KEY: "n".repeat(40), SESSION_SIGNING_KEY_PREVIOUS: testEnv().SESSION_SIGNING_KEY })))!;
    expect(await verifyAccessToken(rotated, jwt, T0 + 1000)).toEqual({ userId: uid, sessionId: sid });
    const fresh = await signAccessToken(rotated, uid, sid, T0);
    expect(decodeJwt(fresh)!.header.kid).toBe(rotated.current.kid);
    expect(await verifyAccessToken(keys, fresh, T0 + 1000)).toBeNull();
  });
});

describe("canonical timestamps", () => {
  it.each([
    ["2026-10-09T07:00:00.123456Z", "2026-10-09T07:00:00.123456Z"],
    ["2026-10-09T07:00:00Z", "2026-10-09T07:00:00.000000Z"],
    ["2026-10-09 07:00Z", "2026-10-09T07:00:00.000000Z"],
    ["2026-10-09T07:00:00.1Z", "2026-10-09T07:00:00.100000Z"],
    ["2026-10-09T07:00:00.123456789Z", "2026-10-09T07:00:00.123456Z"],
    ["2026-10-08T05:50:12.500000+02:00", "2026-10-08T03:50:12.500000Z"],
    ["2026-10-08T05:50:12.500000+0200", "2026-10-08T03:50:12.500000Z"],
    ["2026-01-01T00:30:00.000001+01:00", "2025-12-31T23:30:00.000001Z"],
    ["2026-12-31T23:30:00.999999-01:00", "2027-01-01T00:30:00.999999Z"],
    ["2028-02-29T00:00:00z", "2028-02-29T00:00:00.000000Z"],
    ["1900-01-01T00:00:00Z", "1900-01-01T00:00:00.000000Z"],
    ["9999-12-31T23:59:59.999999Z", "9999-12-31T23:59:59.999999Z"],
  ])("%s → %s", (input, expected) => {
    expect(canonicalTimestamp(input)).toBe(expected);
  });

  it.each([
    "2026-10-09",
    "2026-10-09T07:00:00",
    "2026-13-01T00:00:00Z",
    "2026-02-29T00:00:00Z",
    "2026-10-32T00:00:00Z",
    "2026-10-09T24:00:00Z",
    "2026-10-09T07:60:00Z",
    "2026-10-09T07:00:60Z",
    "1899-12-31T23:59:59Z",
    "9999-12-31T23:59:59-01:00",
    "2026-10-09T07:00:00.Z",
    "2026-10-09T07:00:00+24:00",
    " 2026-10-09T07:00:00Z",
    "2026-10-09T07:00:00Z ",
    "2026-10-09T07:00:00.1234567890123Z",
  ])("rejects %s", (input) => {
    expect(canonicalTimestamp(input)).toBeNull();
  });

  it("formats ms epochs canonically", () => {
    expect(canonicalFromMs(T0 + 123)).toBe("2026-10-09T12:00:00.123000Z");
  });
});

describe("Apple key handling", () => {
  it("parses the .p8 PEM in every accepted form and signs a verifiable ES256 client secret", async () => {
    const ec = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", ec.privateKey)) as ArrayBuffer);
    const p = pem(der.buffer);
    const body = p.split("\n").filter((l) => !l.startsWith("-----")).join("");
    for (const variant of [p, p.replace(/\n/g, "\r\n"), p.replace(/\n/g, "\\n"), body, `  ${body}\n`]) {
      expect(appleKeyDer(variant)).toEqual(der);
    }
    const deps = makeDeps();
    const env = testEnv({ APPLE_TEAM_ID: "TEAM123456", APPLE_KEY_ID: "KEY1234567", APPLE_PRIVATE_KEY: p.replace(/\n/g, "\\n") });
    const secret = (await appleClientSecret(env, deps, "com.example.web"))!;
    const jwt = decodeJwt(secret)!;
    expect(jwt.header).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(jwt.payload).toEqual({ iss: "TEAM123456", iat: T0 / 1000, exp: T0 / 1000 + 300, aud: "https://appleid.apple.com", sub: "com.example.web" });
    expect(jwt.signature.byteLength).toBe(64);
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, ec.publicKey, jwt.signature, utf8(jwt.signingInput))).toBe(true);
    // Cached for a few minutes, then re-signed.
    expect(await appleClientSecret(env, deps, "com.example.web")).toBe(secret);
    deps.clock.advance(241_000);
    expect(await appleClientSecret(env, deps, "com.example.web")).not.toBe(secret);
  });

  it("disables Apple web for an unparsable key and logs once without the key", async () => {
    const deps = makeDeps();
    const bad = "-----BEGIN PRIVATE KEY-----\nbm90IGEga2V5\n-----END PRIVATE KEY-----";
    const env = testEnv({ APPLE_SERVICES_ID: "s", APPLE_TEAM_ID: "t", APPLE_KEY_ID: "k", APPLE_PRIVATE_KEY: bad });
    expect(await appleSigningKey(env, deps)).toBeNull();
    expect((await providerFlags(env, deps)).apple.web).toBe(false);
    expect(await appleSigningKey(env, deps)).toBeNull();
    const logged = deps.logs.filter((l) => l.event === "apple_private_key_invalid");
    expect(logged.length).toBe(1);
    expect(JSON.stringify(deps.logs)).not.toContain("bm90IGEga2V5");
  });

  it("seals Apple refresh tokens with AES-GCM and unseals with the current or previous key", async () => {
    const deps = makeDeps();
    const keys = (await loadKeys(testEnv()))!;
    const sealed = await sealAppleToken(keys, deps, { client_id: "c", refresh_token: "r.secret" });
    expect(sealed).not.toContain("secret");
    expect(await unsealAppleToken(keys, sealed)).toEqual({ client_id: "c", refresh_token: "r.secret" });
    const rotated = (await loadKeys(testEnv({ SESSION_SIGNING_KEY: "m".repeat(40), SESSION_SIGNING_KEY_PREVIOUS: testEnv().SESSION_SIGNING_KEY })))!;
    expect(await unsealAppleToken(rotated, sealed)).toEqual({ client_id: "c", refresh_token: "r.secret" });
    const other = (await loadKeys(testEnv({ SESSION_SIGNING_KEY: "o".repeat(40) })))!;
    expect(await unsealAppleToken(other, sealed)).toBeNull();
    expect(await unsealAppleToken(keys, sealed.slice(0, -2) + "AA")).toBeNull();
  });

  it("ES256 signatures are raw r‖s (64 bytes)", async () => {
    const ec = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const jwt = decodeJwt(await signEs256(ec.privateKey, { alg: "ES256" }, { a: 1 }))!;
    expect(jwt.signature.byteLength).toBe(64);
  });
});

describe("misc", () => {
  it("sanitizes provider strings", () => {
    expect(sanitizeText("  Marcel\u0000 Muster\u0007 ", 100)).toBe("Marcel Muster");
    expect(sanitizeText("\u0001\u0002", 100)).toBeNull();
    expect(sanitizeText(42, 100)).toBeNull();
    expect(sanitizeText("abcdef", 3)).toBe("abc");
    expect(sanitizeText("ab😀", 3)).toBe("ab");
    expect(sanitizeText("a\uD800b", 10)).toBe("ab");
  });

  it("compares app versions", () => {
    expect(versionBelow([1, 0, 0], [1, 0, 1])).toBe(true);
    expect(versionBelow([1, 2, 0], [1, 10, 0])).toBe(true);
    expect(versionBelow([2, 0, 0], [1, 9, 9])).toBe(false);
    expect(versionBelow([1, 0, 0], [1, 0, 0])).toBe(false);
  });
});
