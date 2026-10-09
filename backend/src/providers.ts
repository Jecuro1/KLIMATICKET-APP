// OIDC providers (docs/CLOUDFLARE_BACKEND.md §2.2, §2.9). Endpoints are hard-coded (no discovery at runtime).
import type { Env } from "./env";
import type { Deps } from "./deps";
import { base64Decode, sha256Base64url, signEs256 } from "./crypto";
import { isUsableSecret } from "./keys";

export type ProviderName = "google" | "microsoft" | "apple";
export const PROVIDERS: readonly ProviderName[] = ["google", "microsoft", "apple"];

export function isProviderName(s: string): s is ProviderName {
  return (PROVIDERS as readonly string[]).includes(s);
}

export interface ProviderSpec {
  name: ProviderName;
  authorizeUrl: string;
  tokenUrl: string;
  jwksUrl: string;
  scope: string;
  /** PKCE towards the provider (Google, Microsoft). */
  pkce: boolean;
  callbackMethod: "GET" | "POST";
  extraAuthorizeParams: Record<string, string>;
}

export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

export const SPECS: Record<ProviderName, ProviderSpec> = {
  google: {
    name: "google",
    authorizeUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenUrl: "https://oauth2.googleapis.com/token",
    jwksUrl: "https://www.googleapis.com/oauth2/v3/certs",
    scope: "openid email profile",
    pkce: true,
    callbackMethod: "GET",
    extraAuthorizeParams: { prompt: "select_account", access_type: "online" },
  },
  microsoft: {
    name: "microsoft",
    authorizeUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
    tokenUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
    jwksUrl: "https://login.microsoftonline.com/common/discovery/v2.0/keys",
    scope: "openid email profile",
    pkce: true,
    callbackMethod: "GET",
    extraAuthorizeParams: { prompt: "select_account", response_mode: "query" },
  },
  apple: {
    name: "apple",
    authorizeUrl: "https://appleid.apple.com/auth/authorize",
    tokenUrl: "https://appleid.apple.com/auth/token",
    jwksUrl: "https://appleid.apple.com/auth/keys",
    scope: "name email",
    pkce: false,
    callbackMethod: "POST",
    extraAuthorizeParams: { response_mode: "form_post" },
  },
};

function present(v: string | undefined): v is string {
  return typeof v === "string" && v.trim().length > 0;
}

// ---------------------------------------------------------------------------------------------------------------
// Apple private key (.p8) parsing and client secret
// ---------------------------------------------------------------------------------------------------------------

const appleKeyCache = new Map<string, Promise<CryptoKey | null>>();
const appleKeyErrorsLogged = new Set<string>();

/** Accepts the whole .p8 PEM (real newlines, "\n" escapes, CRLF) or the bare base64 body. */
export function appleKeyDer(raw: string): Uint8Array<ArrayBuffer> | null {
  const body = raw
    .replace(/\\r/g, "\n")
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  if (body.length === 0) return null;
  return base64Decode(body);
}

/** The imported ECDSA P-256 key, or null when APPLE_PRIVATE_KEY is missing or does not parse (logged once). */
export function appleSigningKey(env: Env, deps: Deps): Promise<CryptoKey | null> {
  const raw = env.APPLE_PRIVATE_KEY;
  if (!present(raw)) return Promise.resolve(null);
  let entry = appleKeyCache.get(raw);
  if (!entry) {
    if (appleKeyCache.size > 8) appleKeyCache.clear();
    entry = (async () => {
      const der = appleKeyDer(raw);
      if (!der) throw new Error("not base64");
      return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
    })().catch(async (err: unknown) => {
      const fingerprint = (await sha256Base64url(raw)).slice(0, 8);
      if (!appleKeyErrorsLogged.has(fingerprint)) {
        appleKeyErrorsLogged.add(fingerprint);
        // Never log the key itself – only that it is unusable.
        deps.log({ event: "apple_private_key_invalid", reason: err instanceof Error ? err.name : "unknown" });
      }
      return null;
    });
    appleKeyCache.set(raw, entry);
  }
  return entry;
}

interface CachedSecret {
  value: string;
  iat: number;
}
// Keyed by the imported key object, so a changed APPLE_PRIVATE_KEY never reuses a secret signed with the old key.
const clientSecretCache = new WeakMap<CryptoKey, Map<string, CachedSecret>>();
const CLIENT_SECRET_LIFETIME_S = 300;
const CLIENT_SECRET_REUSE_S = 240;

/** ES256 client secret for `clientId` (Services ID for web, bundle id for native). Cached ≤ 4 min. */
export async function appleClientSecret(env: Env, deps: Deps, clientId: string): Promise<string | null> {
  if (!present(env.APPLE_TEAM_ID) || !present(env.APPLE_KEY_ID)) return null;
  const key = await appleSigningKey(env, deps);
  if (!key) return null;
  const now = Math.floor(deps.now() / 1000);
  const cacheKey = `${clientId}\u0000${env.APPLE_TEAM_ID}\u0000${env.APPLE_KEY_ID}`;
  let perKey = clientSecretCache.get(key);
  if (!perKey) {
    perKey = new Map();
    clientSecretCache.set(key, perKey);
  }
  const cached = perKey.get(cacheKey);
  if (cached && now >= cached.iat && now - cached.iat < CLIENT_SECRET_REUSE_S) return cached.value;
  const value = await signEs256(
    key,
    { alg: "ES256", kid: env.APPLE_KEY_ID.trim() },
    { iss: env.APPLE_TEAM_ID.trim(), iat: now, exp: now + CLIENT_SECRET_LIFETIME_S, aud: APPLE_ISSUER, sub: clientId },
  );
  if (perKey.size > 8) perKey.clear();
  perKey.set(cacheKey, { value, iat: now });
  return value;
}

// ---------------------------------------------------------------------------------------------------------------
// Enablement (§2.2) – also the source of GET /v1/config
// ---------------------------------------------------------------------------------------------------------------

export interface ProviderFlags {
  google: { web: boolean };
  microsoft: { web: boolean };
  apple: { web: boolean; native: boolean };
}

export async function providerFlags(env: Env, deps: Deps): Promise<ProviderFlags> {
  if (!isUsableSecret(env.SESSION_SIGNING_KEY)) {
    return { google: { web: false }, microsoft: { web: false }, apple: { web: false, native: false } };
  }
  const appleKeyFields = present(env.APPLE_SERVICES_ID) && present(env.APPLE_TEAM_ID) && present(env.APPLE_KEY_ID);
  const appleWeb = appleKeyFields && (await appleSigningKey(env, deps)) !== null;
  return {
    google: { web: present(env.GOOGLE_CLIENT_ID) && present(env.GOOGLE_CLIENT_SECRET) },
    microsoft: { web: present(env.MICROSOFT_CLIENT_ID) && present(env.MICROSOFT_CLIENT_SECRET) },
    apple: { web: appleWeb, native: present(env.APPLE_BUNDLE_ID) },
  };
}

export async function isWebEnabled(env: Env, deps: Deps, provider: ProviderName): Promise<boolean> {
  const flags = await providerFlags(env, deps);
  return flags[provider].web;
}

/** OAuth client id of the web flow. */
export function webClientId(env: Env, provider: ProviderName): string {
  switch (provider) {
    case "google":
      return env.GOOGLE_CLIENT_ID!.trim();
    case "microsoft":
      return env.MICROSOFT_CLIENT_ID!.trim();
    case "apple":
      return env.APPLE_SERVICES_ID!.trim();
  }
}

export async function webClientSecret(env: Env, deps: Deps, provider: ProviderName): Promise<string | null> {
  switch (provider) {
    case "google":
      return env.GOOGLE_CLIENT_SECRET?.trim() || null;
    case "microsoft":
      return env.MICROSOFT_CLIENT_SECRET?.trim() || null;
    case "apple":
      return appleClientSecret(env, deps, webClientId(env, "apple"));
  }
}
