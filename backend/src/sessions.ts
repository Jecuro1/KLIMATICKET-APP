// Sessions, access tokens (HS256 JWT), refresh tokens and the user object (docs/CLOUDFLARE_BACKEND.md §2.6, §2.7).
import type { Env } from "./env";
import type { Deps } from "./deps";
import { base64urlEncode, decodeJwt, sha256Base64url, signHs256, verifyHs256 } from "./crypto";
import { ApiError } from "./http";
import { loadKeys, type Keys } from "./keys";
import { canonicalFromMs } from "./timestamps";

export const ACCESS_TOKEN_TTL_S = 900;
export const REFRESH_TTL_MS = 60 * 24 * 60 * 60 * 1000;
export const ISSUER = "klimabilanz-api";
export const AUDIENCE = "klimabilanz-ios";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SID_RE = /^[A-Za-z0-9_-]{16,64}$/;
export const TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

export function notConfigured(): ApiError {
  return new ApiError(503, "server_not_configured", "SESSION_SIGNING_KEY is missing or too short.");
}

export async function requireKeys(env: Env): Promise<Keys> {
  const keys = await loadKeys(env);
  if (!keys) throw notConfigured();
  return keys;
}

export function randomToken(deps: Deps, bytes = 32): string {
  return base64urlEncode(deps.randomBytes(bytes));
}

export function hashToken(token: string): Promise<string> {
  return sha256Base64url(token);
}

// ---------------------------------------------------------------------------------------------------------------
// Access tokens
// ---------------------------------------------------------------------------------------------------------------

export async function signAccessToken(keys: Keys, userId: string, sessionId: string, nowMs: number): Promise<string> {
  const iat = Math.floor(nowMs / 1000);
  return signHs256(
    keys.current.access,
    { alg: "HS256", typ: "JWT", kid: keys.current.kid },
    { iss: ISSUER, aud: AUDIENCE, sub: userId, sid: sessionId, iat, exp: iat + ACCESS_TOKEN_TTL_S, v: 1 },
  );
}

export interface AccessClaims {
  userId: string;
  sessionId: string;
}

/** Verifies an access token. `allowExpired` is only for logout (a valid signature is still required). */
export async function verifyAccessToken(keys: Keys, token: string, nowMs: number, allowExpired = false): Promise<AccessClaims | null> {
  const jwt = decodeJwt(token);
  if (!jwt) return null;
  if (jwt.header.alg !== "HS256" || typeof jwt.header.kid !== "string") return null;
  const set = jwt.header.kid === keys.current.kid ? keys.current : jwt.header.kid === keys.previous?.kid ? keys.previous : null;
  if (!set) return null;
  if (!(await verifyHs256(set.access, jwt))) return null;
  const { iss, aud, sub, sid, exp, iat } = jwt.payload;
  if (iss !== ISSUER || aud !== AUDIENCE) return null;
  if (typeof sub !== "string" || !UUID_RE.test(sub) || typeof sid !== "string" || !SID_RE.test(sid)) return null;
  if (typeof exp !== "number" || typeof iat !== "number") return null;
  const now = nowMs / 1000;
  if (!allowExpired && !(exp > now)) return null;
  if (iat > now + 60) return null;
  return { userId: sub, sessionId: sid };
}

export interface AuthContext {
  keys: Keys;
  userId: string;
  sessionId: string;
  provider: string;
  subject: string;
}

function invalidToken(description = "The access token is invalid or expired."): ApiError {
  return new ApiError(401, "invalid_token", description);
}

export function bearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  if (!header) return null;
  const m = /^Bearer[ ]+([A-Za-z0-9._-]+)\s*$/i.exec(header);
  return m ? m[1]! : null;
}

/** Bearer authentication: JWT check plus the session row on every request (logout/deletion act immediately). */
export async function authenticate(request: Request, env: Env, deps: Deps): Promise<AuthContext> {
  const keys = await requireKeys(env);
  const token = bearerToken(request);
  if (!token) throw invalidToken("Missing bearer token.");
  const now = deps.now();
  const claims = await verifyAccessToken(keys, token, now);
  if (!claims) throw invalidToken();
  const row = await env.DB.prepare(
    "SELECT provider, subject FROM sessions WHERE id = ?1 AND user_id = ?2 AND revoked_at IS NULL AND expires_at > ?3",
  )
    .bind(claims.sessionId, claims.userId, now)
    .first<{ provider: string; subject: string }>();
  if (!row) throw invalidToken("The session has ended.");
  return { keys, userId: claims.userId, sessionId: claims.sessionId, provider: row.provider, subject: row.subject };
}

// ---------------------------------------------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------------------------------------------

export interface NewSession {
  sessionId: string;
  refreshToken: string;
  refreshHash: string;
}

export async function newSessionIds(deps: Deps): Promise<NewSession> {
  const refreshToken = randomToken(deps);
  return { sessionId: randomToken(deps, 16), refreshToken, refreshHash: await hashToken(refreshToken) };
}

export function userAgent(request: Request): string | null {
  const ua = request.headers.get("User-Agent");
  return ua ? ua.replace(/[\u0000-\u001F\u007F]/g, "").slice(0, 200) : null;
}

/**
 * INSERT statements for a session and its first refresh token. With `guard`, the session row is only written when
 * the guard SQL (bound with `guardArgs`) matches – the concurrent-redemption guard of §2.3.
 */
export function sessionStatements(
  db: D1Database,
  s: NewSession,
  owner: { userId: string; provider: string; subject: string },
  now: number,
  ua: string | null,
  guard?: { sql: string; args: unknown[] },
): D1PreparedStatement[] {
  const expires = now + REFRESH_TTL_MS;
  const sessionInsert = guard
    ? db
        .prepare(
          `INSERT INTO sessions (id, user_id, provider, subject, created_at, last_refreshed_at, expires_at, user_agent)
           SELECT ?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7 WHERE EXISTS (${guard.sql})`,
        )
        .bind(s.sessionId, owner.userId, owner.provider, owner.subject, now, expires, ua, ...guard.args)
    : db
        .prepare(
          `INSERT INTO sessions (id, user_id, provider, subject, created_at, last_refreshed_at, expires_at, user_agent)
           VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7)`,
        )
        .bind(s.sessionId, owner.userId, owner.provider, owner.subject, now, expires, ua);
  const tokenInsert = db
    .prepare(
      `INSERT INTO refresh_tokens (token_hash, session_id, created_at, expires_at)
       SELECT ?1, ?2, ?3, ?4 WHERE EXISTS (SELECT 1 FROM sessions WHERE id = ?2)`,
    )
    .bind(s.refreshHash, s.sessionId, now, expires);
  return [sessionInsert, tokenInsert];
}

export function revokeSession(db: D1Database, sessionId: string, reason: string, now: number): D1PreparedStatement {
  return db
    .prepare("UPDATE sessions SET revoked_at = ?2, revoked_reason = ?3 WHERE id = ?1 AND revoked_at IS NULL")
    .bind(sessionId, now, reason);
}

// ---------------------------------------------------------------------------------------------------------------
// User object
// ---------------------------------------------------------------------------------------------------------------

export interface UserObject {
  id: string;
  email: string | null;
  email_verified: boolean;
  display_name: string | null;
  avatar_url: string | null;
  provider: string;
  created_at: string;
}

export async function loadUser(db: D1Database, userId: string, provider: string, subject: string): Promise<UserObject | null> {
  const row = await db
    .prepare(
      `SELECT u.id, u.created_at, p.display_name, p.avatar_url, i.email, i.email_verified
       FROM users u
       LEFT JOIN profiles p ON p.user_id = u.id
       LEFT JOIN identities i ON i.provider = ?2 AND i.subject = ?3 AND i.user_id = u.id
       WHERE u.id = ?1`,
    )
    .bind(userId, provider, subject)
    .first<{
      id: string;
      created_at: number;
      display_name: string | null;
      avatar_url: string | null;
      email: string | null;
      email_verified: number | null;
    }>();
  if (!row) return null;
  return {
    id: row.id,
    email: row.email ?? null,
    email_verified: row.email_verified === 1,
    display_name: row.display_name ?? null,
    avatar_url: row.avatar_url ?? null,
    provider,
    created_at: canonicalFromMs(row.created_at),
  };
}

export interface TokenResponse {
  access_token: string;
  token_type: "Bearer";
  expires_in: number;
  refresh_token: string;
  refresh_token_expires_in: number;
  user: UserObject;
}

export async function tokenResponse(
  env: Env,
  keys: Keys,
  s: { sessionId: string; refreshToken: string },
  owner: { userId: string; provider: string; subject: string },
  now: number,
): Promise<TokenResponse> {
  const user = await loadUser(env.DB, owner.userId, owner.provider, owner.subject);
  if (!user) throw new ApiError(400, "invalid_grant", "The account no longer exists.");
  return {
    access_token: await signAccessToken(keys, owner.userId, s.sessionId, now),
    token_type: "Bearer",
    expires_in: ACCESS_TOKEN_TTL_S,
    refresh_token: s.refreshToken,
    refresh_token_expires_in: REFRESH_TTL_MS / 1000,
    user,
  };
}
