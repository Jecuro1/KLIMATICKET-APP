// POST /v1/auth/token (docs/CLOUDFLARE_BACKEND.md §2.3, §2.7) and POST /v1/auth/logout.
import type { Env } from "../env";
import type { Deps } from "../deps";
import { sha256Base64url, timingSafeEqualString } from "../crypto";
import { ApiError, clientIp, json, noContent, readFields, type RequestInfo } from "../http";
import type { Keys } from "../keys";
import { hit, type LimitName } from "../ratelimit";
import {
  REFRESH_TTL_MS,
  TOKEN_RE,
  bearerToken,
  hashToken,
  newSessionIds,
  randomToken,
  requireKeys,
  revokeSession,
  sessionStatements,
  tokenResponse,
  userAgent,
  verifyAccessToken,
  type TokenResponse,
} from "../sessions";

const VERIFIER_RE = /^[A-Za-z0-9._~-]{43,128}$/;
const GRACE_MS = 60_000;

function invalidGrant(description: string): ApiError {
  return new ApiError(400, "invalid_grant", description);
}

export function rateLimited(retryAfter: number): ApiError {
  return new ApiError(429, "rate_limited", "Too many requests.", {}, { "Retry-After": String(retryAfter) });
}

export async function enforceLimit(env: Env, keys: Keys, deps: Deps, name: LimitName, subject: string): Promise<void> {
  const decision = await hit(env.DB, keys, deps, name, subject);
  if (!decision.allowed) throw rateLimited(decision.retryAfter);
}

export async function tokenEndpoint(request: Request, env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  const keys = await requireKeys(env);
  await enforceLimit(env, keys, deps, "auth_token", clientIp(request));
  const fields = await readFields(request);
  const grant = fields.get("grant_type");
  if (!grant) throw new ApiError(400, "invalid_request", "grant_type is required.");
  if (grant === "authorization_code") return json(info, await redeemCode(request, env, deps, keys, fields));
  if (grant === "refresh_token") return json(info, await refreshGrant(env, deps, keys, fields));
  throw new ApiError(400, "unsupported_grant_type", "Only authorization_code and refresh_token are supported.");
}

// ---------------------------------------------------------------------------------------------------------------
// grant_type=authorization_code
// ---------------------------------------------------------------------------------------------------------------

interface CodeRow {
  user_id: string;
  provider: string;
  subject: string;
  code_challenge: string;
  redirect_uri: string;
  expires_at: number;
  used_at: number | null;
  session_id: string | null;
}

async function redeemCode(request: Request, env: Env, deps: Deps, keys: Keys, fields: Map<string, string>): Promise<TokenResponse> {
  const db = env.DB;
  const code = fields.get("code");
  const verifier = fields.get("code_verifier");
  const redirectUri = fields.get("redirect_uri");
  if (!code || !verifier || !redirectUri) throw new ApiError(400, "invalid_request", "code, code_verifier and redirect_uri are required.");
  if (!VERIFIER_RE.test(verifier)) throw new ApiError(400, "invalid_request", "code_verifier is malformed.");
  if (!TOKEN_RE.test(code)) throw invalidGrant("Unknown authorization code.");

  const codeHash = await hashToken(code);
  const now = deps.now();
  const row = await db.prepare("SELECT * FROM auth_codes WHERE code_hash = ?1").bind(codeHash).first<CodeRow>();
  if (!row || row.expires_at <= now) throw invalidGrant("Unknown or expired authorization code.");
  if (row.used_at !== null) {
    if (row.session_id) await revokeSession(db, row.session_id, "code_reuse", now).run();
    throw invalidGrant("The authorization code was already used.");
  }

  const challengeOk = timingSafeEqualString(await sha256Base64url(verifier), row.code_challenge);
  const redirectOk = redirectUri === row.redirect_uri;
  if (!challengeOk || !redirectOk) {
    // Any redemption attempt consumes the code.
    await db.prepare("UPDATE auth_codes SET used_at = ?2 WHERE code_hash = ?1 AND used_at IS NULL").bind(codeHash, now).run();
    throw invalidGrant(challengeOk ? "redirect_uri does not match." : "PKCE verification failed.");
  }

  const s = await newSessionIds(deps);
  const owner = { userId: row.user_id, provider: row.provider, subject: row.subject };
  const results = await db.batch([
    db.prepare("UPDATE auth_codes SET used_at = ?2, session_id = ?3 WHERE code_hash = ?1 AND used_at IS NULL").bind(codeHash, now, s.sessionId),
    ...sessionStatements(db, s, owner, now, userAgent(request), {
      sql: "SELECT 1 FROM auth_codes WHERE code_hash = ?8 AND session_id = ?9",
      args: [codeHash, s.sessionId],
    }),
  ]);
  if (results[1]?.meta.changes !== 1) {
    // A concurrent redemption won: the code was used twice → revoke what it issued.
    const winner = await db.prepare("SELECT session_id FROM auth_codes WHERE code_hash = ?1").bind(codeHash).first<{ session_id: string | null }>();
    if (winner?.session_id) await revokeSession(db, winner.session_id, "code_reuse", now).run();
    throw invalidGrant("The authorization code was already used.");
  }
  return tokenResponse(env, keys, s, owner, now);
}

// ---------------------------------------------------------------------------------------------------------------
// grant_type=refresh_token (rotation, 60 s grace, reuse detection)
// ---------------------------------------------------------------------------------------------------------------

interface RefreshRow {
  session_id: string;
  expires_at: number;
  used_at: number | null;
  replaced_by: string | null;
  revoked_at: number | null;
  user_id: string;
  provider: string;
  subject: string;
  session_revoked_at: number | null;
  session_expires_at: number;
  successor_used_at: number | null;
  successor_revoked_at: number | null;
}

const REFRESH_LOOKUP = `
SELECT rt.session_id, rt.expires_at, rt.used_at, rt.replaced_by, rt.revoked_at,
       s.user_id, s.provider, s.subject, s.revoked_at AS session_revoked_at, s.expires_at AS session_expires_at,
       succ.used_at AS successor_used_at, succ.revoked_at AS successor_revoked_at
FROM refresh_tokens rt
JOIN sessions s ON s.id = rt.session_id
LEFT JOIN refresh_tokens succ ON succ.token_hash = rt.replaced_by
WHERE rt.token_hash = ?1`;

// ?1 new hash, ?2 session id, ?3 now, ?4 expires, ?5 old hash
const INSERT_SUCCESSOR = `
INSERT INTO refresh_tokens (token_hash, session_id, created_at, expires_at)
SELECT ?1, ?2, ?3, ?4
WHERE EXISTS (SELECT 1 FROM refresh_tokens WHERE token_hash = ?5 AND replaced_by = ?1)
  AND EXISTS (SELECT 1 FROM sessions WHERE id = ?2 AND revoked_at IS NULL)`;

// ?1 session id, ?2 now, ?3 expires, ?4 new hash
const SLIDE_SESSION = `
UPDATE sessions SET last_refreshed_at = ?2, expires_at = ?3
WHERE id = ?1 AND revoked_at IS NULL AND EXISTS (SELECT 1 FROM refresh_tokens WHERE token_hash = ?4)`;

async function refreshGrant(env: Env, deps: Deps, keys: Keys, fields: Map<string, string>): Promise<TokenResponse> {
  const db = env.DB;
  const token = fields.get("refresh_token");
  if (!token) throw new ApiError(400, "invalid_request", "refresh_token is required.");
  if (!TOKEN_RE.test(token)) throw invalidGrant("Unknown refresh token.");
  const oldHash = await hashToken(token);

  for (let attempt = 0; attempt < 3; attempt++) {
    const now = deps.now();
    const row = await db.prepare(REFRESH_LOOKUP).bind(oldHash).first<RefreshRow>();
    if (!row) throw invalidGrant("Unknown refresh token.");
    if (row.session_revoked_at !== null) throw invalidGrant("The session has ended.");
    if (row.session_expires_at <= now || row.expires_at <= now) throw invalidGrant("The refresh token has expired.");
    if (row.revoked_at !== null) {
      await revokeSession(db, row.session_id, "refresh_reuse", now).run();
      throw invalidGrant("Refresh token reuse detected.");
    }
    const owner = { userId: row.user_id, provider: row.provider, subject: row.subject };
    const nextToken = randomToken(deps);
    const nextHash = await hashToken(nextToken);
    const expires = now + REFRESH_TTL_MS;

    if (row.used_at === null) {
      // 3. Rotate.
      const results = await db.batch([
        db
          .prepare("UPDATE refresh_tokens SET used_at = ?2, replaced_by = ?3 WHERE token_hash = ?1 AND used_at IS NULL AND revoked_at IS NULL")
          .bind(oldHash, now, nextHash),
        db.prepare(INSERT_SUCCESSOR).bind(nextHash, row.session_id, now, expires, oldHash),
        db.prepare(SLIDE_SESSION).bind(row.session_id, now, expires, nextHash),
      ]);
      if (results[1]?.meta.changes === 1) {
        return tokenResponse(env, keys, { sessionId: row.session_id, refreshToken: nextToken }, owner, now);
      }
      continue; // a concurrent refresh won the race → re-read (step 4)
    }

    // 4. Already used: grace window for a lost response, otherwise reuse.
    const inGrace =
      now >= row.used_at &&
      now - row.used_at <= GRACE_MS &&
      row.replaced_by !== null &&
      row.successor_used_at === null &&
      row.successor_revoked_at === null;
    if (!inGrace) {
      await revokeSession(db, row.session_id, "refresh_reuse", now).run();
      throw invalidGrant("Refresh token reuse detected.");
    }
    const successor = row.replaced_by!;
    const results = await db.batch([
      db
        .prepare("UPDATE refresh_tokens SET revoked_at = ?2 WHERE token_hash = ?1 AND used_at IS NULL AND revoked_at IS NULL")
        .bind(successor, now),
      db
        .prepare(
          `UPDATE refresh_tokens SET replaced_by = ?3 WHERE token_hash = ?1 AND replaced_by = ?2
           AND EXISTS (SELECT 1 FROM refresh_tokens WHERE token_hash = ?2 AND used_at IS NULL AND revoked_at = ?4)`,
        )
        .bind(oldHash, successor, nextHash, now),
      db.prepare(INSERT_SUCCESSOR).bind(nextHash, row.session_id, now, expires, oldHash),
      db.prepare(SLIDE_SESSION).bind(row.session_id, now, expires, nextHash),
    ]);
    if (results[2]?.meta.changes === 1) {
      return tokenResponse(env, keys, { sessionId: row.session_id, refreshToken: nextToken }, owner, now);
    }
  }
  // Only reachable under heavy concurrent use of one token: transient, the client may retry.
  throw new ApiError(500, "server_error", "Concurrent refresh, please retry.");
}

// ---------------------------------------------------------------------------------------------------------------
// POST /v1/auth/logout – this device only, always 204
// ---------------------------------------------------------------------------------------------------------------

export async function logoutEndpoint(request: Request, env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  const keys = await requireKeys(env);
  await enforceLimit(env, keys, deps, "auth_logout", clientIp(request));
  const fields = await readFields(request, true);
  const db = env.DB;
  const now = deps.now();
  const statements: D1PreparedStatement[] = [];

  const refresh = fields.get("refresh_token");
  if (refresh && TOKEN_RE.test(refresh)) {
    statements.push(
      db
        .prepare(
          `UPDATE sessions SET revoked_at = ?2, revoked_reason = 'logout'
           WHERE revoked_at IS NULL AND id = (SELECT session_id FROM refresh_tokens WHERE token_hash = ?1)`,
        )
        .bind(await hashToken(refresh), now),
    );
  }
  const bearer = bearerToken(request);
  if (bearer) {
    const claims = await verifyAccessToken(keys, bearer, now, true);
    if (claims) {
      statements.push(
        db
          .prepare("UPDATE sessions SET revoked_at = ?3, revoked_reason = 'logout' WHERE id = ?1 AND user_id = ?2 AND revoked_at IS NULL")
          .bind(claims.sessionId, claims.userId, now),
      );
    }
  }
  if (statements.length > 0) await db.batch(statements);
  return noContent(info);
}
