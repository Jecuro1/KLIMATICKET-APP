// Sub-keys derived from SESSION_SIGNING_KEY (docs/CLOUDFLARE_BACKEND.md §2.7). Cached per isolate.
import type { Env } from "./env";
import { base64urlEncode, hkdf, importAesKey, importHmacKey, sha256, utf8 } from "./crypto";

export interface KeySet {
  /** HS256 key for access tokens. */
  access: CryptoKey;
  /** JWT header kid: first 8 chars of base64url(SHA-256(raw HMAC key)). */
  kid: string;
  /** HMAC key for rate-limit buckets. */
  rateLimit: CryptoKey;
  /** AES-256-GCM key for sealed Apple refresh tokens. */
  seal: CryptoKey;
}

export interface Keys {
  current: KeySet;
  /** SESSION_SIGNING_KEY_PREVIOUS: only for verifying access tokens and unsealing. */
  previous: KeySet | null;
}

const MIN_SECRET_LENGTH = 32;
const SALT = "klimabilanz-api";

const cache = new Map<string, Promise<KeySet>>();

export function isUsableSecret(secret: string | undefined): secret is string {
  return typeof secret === "string" && secret.length >= MIN_SECRET_LENGTH;
}

async function derive(secret: string): Promise<KeySet> {
  const ikm = utf8(secret);
  const [accessRaw, rateRaw, sealRaw] = await Promise.all([
    hkdf(ikm, SALT, "access-token-v1", 32),
    hkdf(ikm, SALT, "rate-limit-v1", 32),
    hkdf(ikm, SALT, "apple-token-seal-v1", 32),
  ]);
  const [access, rateLimit, seal, fingerprint] = await Promise.all([
    importHmacKey(accessRaw),
    importHmacKey(rateRaw),
    importAesKey(sealRaw),
    sha256(accessRaw),
  ]);
  return { access, kid: base64urlEncode(fingerprint).slice(0, 8), rateLimit, seal };
}

function keySet(secret: string): Promise<KeySet> {
  let entry = cache.get(secret);
  if (!entry) {
    if (cache.size > 16) cache.clear();
    entry = derive(secret);
    cache.set(secret, entry);
    entry.catch(() => cache.delete(secret));
  }
  return entry;
}

/** The key set, or null when SESSION_SIGNING_KEY is missing or too short (→ 503 server_not_configured). */
export async function loadKeys(env: Env): Promise<Keys | null> {
  if (!isUsableSecret(env.SESSION_SIGNING_KEY)) return null;
  const current = await keySet(env.SESSION_SIGNING_KEY);
  const previous =
    isUsableSecret(env.SESSION_SIGNING_KEY_PREVIOUS) && env.SESSION_SIGNING_KEY_PREVIOUS !== env.SESSION_SIGNING_KEY
      ? await keySet(env.SESSION_SIGNING_KEY_PREVIOUS)
      : null;
  return { current, previous };
}
