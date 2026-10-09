// ID-token verification for every provider (docs/CLOUDFLARE_BACKEND.md §2.5).
import type { Deps } from "./deps";
import { decodeJwt, timingSafeEqualString, verifyRs256 } from "./crypto";
import { sanitizeText } from "./http";
import { APPLE_ISSUER, SPECS, type ProviderName } from "./providers";

export interface VerifiedIdentity {
  provider: ProviderName;
  subject: string;
  email: string | null;
  emailVerified: boolean;
  name: string | null;
  avatarUrl: string | null;
  /** The nonce claim (as sent). */
  nonce: string;
  /** Token expiry in ms. */
  expiresAt: number;
}

export class IdTokenError extends Error {
  constructor(readonly reason: string) {
    super(`id_token rejected: ${reason}`);
    this.name = "IdTokenError";
  }
}

export interface VerifyOptions {
  provider: ProviderName;
  /** Expected audience (client id / bundle id). */
  audience: string;
  expectedNonce: string;
}

const GUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const CONTROL_RE = /[\u0000-\u001F\u007F-\u009F]/;
const LEEWAY_MS = 60_000;
const MAX_AGE_MS = 10 * 60_000;

function isTrue(v: unknown): boolean {
  return v === true || v === "true";
}

function checkIssuer(provider: ProviderName, claims: Record<string, unknown>): void {
  const iss = claims.iss;
  switch (provider) {
    case "google":
      if (iss !== "https://accounts.google.com" && iss !== "accounts.google.com") throw new IdTokenError("iss");
      return;
    case "microsoft": {
      // /common: the issuer contains the tenant of the signed-in account; it must match the token's own tid.
      const tid = claims.tid;
      if (typeof tid !== "string" || !GUID_RE.test(tid)) throw new IdTokenError("iss");
      if (iss !== `https://login.microsoftonline.com/${tid}/v2.0`) throw new IdTokenError("iss");
      return;
    }
    case "apple":
      if (iss !== APPLE_ISSUER) throw new IdTokenError("iss");
      return;
  }
}

function checkAudience(claims: Record<string, unknown>, audience: string): void {
  const aud = claims.aud;
  if (typeof aud === "string") {
    if (aud !== audience) throw new IdTokenError("aud");
    return;
  }
  if (!Array.isArray(aud) || !aud.includes(audience)) throw new IdTokenError("aud");
  if (aud.length > 1 && claims.azp !== audience) throw new IdTokenError("azp");
}

function checkTimes(claims: Record<string, unknown>, now: number): number {
  const { exp, iat, nbf } = claims;
  if (typeof exp !== "number" || !Number.isFinite(exp) || exp * 1000 <= now - LEEWAY_MS) throw new IdTokenError("exp");
  if (typeof iat !== "number" || !Number.isFinite(iat) || iat * 1000 > now + LEEWAY_MS || iat * 1000 < now - MAX_AGE_MS) {
    throw new IdTokenError("iat");
  }
  if (nbf !== undefined && (typeof nbf !== "number" || !Number.isFinite(nbf) || nbf * 1000 > now + LEEWAY_MS)) {
    throw new IdTokenError("nbf");
  }
  return exp * 1000;
}

function httpsUrl(v: unknown): string | null {
  const s = sanitizeText(v, 2048);
  return s && s.startsWith("https://") ? s : null;
}

/**
 * Verifies signature (RS256 against the provider JWKS), iss, aud/azp, exp/iat/nbf, nonce and sub.
 * Throws IdTokenError (→ invalid_id_token) or JwksUnavailableError (→ provider_error / server_error).
 */
export async function verifyIdToken(token: string, opts: VerifyOptions, deps: Deps): Promise<VerifiedIdentity> {
  const jwt = decodeJwt(token);
  if (!jwt) throw new IdTokenError("malformed");
  const { header, payload: claims } = jwt;
  if (header.alg !== "RS256") throw new IdTokenError("alg");
  if (header.crit !== undefined) throw new IdTokenError("crit");
  const kid = header.kid;
  if (typeof kid !== "string" || kid.length === 0 || kid.length > 256) throw new IdTokenError("kid");

  const now = deps.now();
  const key = await deps.jwks.key(SPECS[opts.provider].jwksUrl, kid, deps.fetch, now);
  if (!key) throw new IdTokenError("kid");
  if (!(await verifyRs256(key, jwt))) throw new IdTokenError("signature");

  checkIssuer(opts.provider, claims);
  checkAudience(claims, opts.audience);
  const expiresAt = checkTimes(claims, now);

  const nonce = claims.nonce;
  if (typeof nonce !== "string" || !timingSafeEqualString(nonce, opts.expectedNonce)) throw new IdTokenError("nonce");

  const sub = claims.sub;
  if (typeof sub !== "string" || sub.length === 0 || sub.length > 255 || CONTROL_RE.test(sub)) throw new IdTokenError("sub");

  let email = sanitizeText(claims.email, 320);
  let emailVerified = false;
  let name: string | null = null;
  let avatarUrl: string | null = null;
  switch (opts.provider) {
    case "google":
      emailVerified = email !== null && claims.email_verified === true;
      name = sanitizeText(claims.name, 100);
      avatarUrl = httpsUrl(claims.picture);
      break;
    case "microsoft":
      // Microsoft e-mail claims are not verified unless xms_edov says so; preferred_username is display only.
      emailVerified = email !== null && isTrue(claims.xms_edov);
      if (email === null) email = sanitizeText(claims.preferred_username, 320);
      name = sanitizeText(claims.name, 100);
      break;
    case "apple":
      emailVerified = email !== null && isTrue(claims.email_verified);
      break;
  }
  return { provider: opts.provider, subject: sub, email, emailVerified, name, avatarUrl, nonce, expiresAt };
}
