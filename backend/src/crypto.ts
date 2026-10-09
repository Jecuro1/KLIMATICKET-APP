// Crypto helpers (WebCrypto only): base64url, SHA-256, HMAC, HKDF, HS256/RS256/ES256 JWS, AES-256-GCM, constant-time
// compare. docs/CLOUDFLARE_BACKEND.md §2.5, §2.7, §2.9.

const encoder = new TextEncoder();
const strictDecoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });

export function utf8(s: string): Uint8Array<ArrayBuffer> {
  return encoder.encode(s) as Uint8Array<ArrayBuffer>;
}

export function fromUtf8(bytes: Uint8Array): string {
  return strictDecoder.decode(bytes);
}

const BASE64URL_RE = /^[A-Za-z0-9_-]*$/;
const BASE64_RE = /^[A-Za-z0-9+/]*={0,2}$/;

export function base64urlEncode(bytes: Uint8Array | ArrayBuffer): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (let i = 0; i < view.length; i += 0x8000) {
    binary += String.fromCharCode(...view.subarray(i, i + 0x8000));
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Decodes unpadded base64url. Returns null for anything that is not canonical base64url. */
export function base64urlDecode(s: string): Uint8Array<ArrayBuffer> | null {
  if (!BASE64URL_RE.test(s) || s.length % 4 === 1) return null;
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return base64Decode(padded);
}

/** Decodes standard (padded or unpadded) base64. Returns null on invalid input. */
export function base64Decode(s: string): Uint8Array<ArrayBuffer> | null {
  if (!BASE64_RE.test(s)) return null;
  let binary: string;
  try {
    binary = atob(s);
  } catch {
    return null;
  }
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export async function sha256(data: Uint8Array<ArrayBuffer> | string): Promise<Uint8Array<ArrayBuffer>> {
  const bytes = typeof data === "string" ? utf8(data) : data;
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

/** base64url(SHA-256(utf8(s))) – used for token/code hashes and PKCE S256. */
export async function sha256Base64url(s: string): Promise<string> {
  return base64urlEncode(await sha256(s));
}

export async function sha256Hex(s: string): Promise<string> {
  const digest = await sha256(s);
  let hex = "";
  for (const b of digest) hex += b.toString(16).padStart(2, "0");
  return hex;
}

/** Constant-time string comparison (length is not secret: every compared value has a fixed public length). */
export function timingSafeEqualString(a: string, b: string): boolean {
  const x = utf8(a);
  const y = utf8(b);
  if (x.byteLength !== y.byteLength) return false;
  return crypto.subtle.timingSafeEqual(x, y);
}

export async function hkdf(ikm: Uint8Array<ArrayBuffer>, salt: string, info: string, bytes: number): Promise<Uint8Array<ArrayBuffer>> {
  const base = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: utf8(salt), info: utf8(info) }, base, bytes * 8);
  return new Uint8Array(bits);
}

export function importHmacKey(raw: Uint8Array<ArrayBuffer>): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function hmacSign(key: CryptoKey, data: string): Promise<Uint8Array<ArrayBuffer>> {
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, utf8(data)));
}

// ---------------------------------------------------------------------------------------------------------------
// JWS compact serialization
// ---------------------------------------------------------------------------------------------------------------

export interface DecodedJwt {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  signingInput: string;
  signature: Uint8Array<ArrayBuffer>;
}

const MAX_JWT_LENGTH = 16_384;

function parseJsonObject(bytes: Uint8Array): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(fromUtf8(bytes));
    return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** Splits and decodes a JWS compact JWT without verifying it. Returns null when it is malformed. */
export function decodeJwt(token: string): DecodedJwt | null {
  if (typeof token !== "string" || token.length === 0 || token.length > MAX_JWT_LENGTH) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, s] = parts as [string, string, string];
  const headerBytes = base64urlDecode(h);
  const payloadBytes = base64urlDecode(p);
  const signature = base64urlDecode(s);
  if (!headerBytes || !payloadBytes || !signature || h.length === 0 || p.length === 0) return null;
  const header = parseJsonObject(headerBytes);
  const payload = parseJsonObject(payloadBytes);
  if (!header || !payload) return null;
  return { header, payload, signingInput: `${h}.${p}`, signature };
}

function encodeSegment(value: unknown): string {
  return base64urlEncode(utf8(JSON.stringify(value)));
}

export async function signHs256(key: CryptoKey, header: Record<string, unknown>, payload: Record<string, unknown>): Promise<string> {
  const input = `${encodeSegment(header)}.${encodeSegment(payload)}`;
  return `${input}.${base64urlEncode(await hmacSign(key, input))}`;
}

export async function verifyHs256(key: CryptoKey, jwt: DecodedJwt): Promise<boolean> {
  if (jwt.signature.byteLength !== 32) return false;
  return crypto.subtle.verify("HMAC", key, jwt.signature, utf8(jwt.signingInput));
}

export async function signEs256(key: CryptoKey, header: Record<string, unknown>, payload: Record<string, unknown>): Promise<string> {
  const input = `${encodeSegment(header)}.${encodeSegment(payload)}`;
  // WebCrypto ECDSA output is IEEE P1363 (r‖s, 64 bytes for P-256) – exactly the JWS ES256 format.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(input));
  return `${input}.${base64urlEncode(sig)}`;
}

export function importRsaJwk(jwk: { n: string; e: string }): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "jwk",
    { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

export function verifyRs256(key: CryptoKey, jwt: DecodedJwt): Promise<boolean> {
  return crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, jwt.signature, utf8(jwt.signingInput));
}

// ---------------------------------------------------------------------------------------------------------------
// AES-256-GCM sealing (Apple refresh tokens, §2.9)
// ---------------------------------------------------------------------------------------------------------------

export function importAesKey(raw: Uint8Array<ArrayBuffer>): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

/** base64url(iv ‖ ciphertext ‖ tag) with a random 12-byte IV. */
export async function seal(key: CryptoKey, plaintext: string, iv: Uint8Array<ArrayBuffer>): Promise<string> {
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, utf8(plaintext)));
  const out = new Uint8Array(iv.byteLength + ct.byteLength);
  out.set(iv, 0);
  out.set(ct, iv.byteLength);
  return base64urlEncode(out);
}

export async function unseal(key: CryptoKey, sealed: string): Promise<string | null> {
  const bytes = base64urlDecode(sealed);
  if (!bytes || bytes.byteLength < 12 + 16) return null;
  try {
    const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12) }, key, bytes.slice(12));
    return fromUtf8(new Uint8Array(pt));
  } catch {
    return null;
  }
}
