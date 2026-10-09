// POST /v1/auth/apple/native – native Sign in with Apple for signed builds (docs/CLOUDFLARE_BACKEND.md §2.4).
import type { Env } from "../env";
import type { Ctx, Deps } from "../deps";
import { findOrCreateUser, storeSealedToken } from "../accounts";
import { exchangeNativeCode, sealAppleToken } from "../apple";
import { sha256Hex } from "../crypto";
import { ApiError, clientIp, json, readJsonObject, sanitizeText, type RequestInfo } from "../http";
import { JwksUnavailableError } from "../jwks";
import { IdTokenError, verifyIdToken } from "../oidc";
import { newSessionIds, requireKeys, sessionStatements, tokenResponse, userAgent } from "../sessions";
import { enforceLimit } from "./token";

const CONTROL_RE = /[\u0000-\u001F\u007F]/;

function optionalString(body: Record<string, unknown>, key: string, max: number): string | null {
  const v = body[key];
  if (v === undefined || v === null || v === "") return null;
  if (typeof v !== "string" || v.length > max) throw new ApiError(400, "invalid_request", `${key} is invalid.`);
  return v;
}

export async function appleNativeEndpoint(request: Request, env: Env, ctx: Ctx, deps: Deps, info: RequestInfo): Promise<Response> {
  const keys = await requireKeys(env);
  const bundleId = env.APPLE_BUNDLE_ID?.trim();
  if (!bundleId) throw new ApiError(404, "provider_disabled", "Native Sign in with Apple is not configured.");
  await enforceLimit(env, keys, deps, "auth_native", clientIp(request));

  const body = await readJsonObject(request);
  const identityToken = body.identity_token;
  const rawNonce = body.raw_nonce;
  if (typeof identityToken !== "string" || identityToken.length === 0 || identityToken.length > 16_384) {
    throw new ApiError(400, "invalid_request", "identity_token is required.");
  }
  if (typeof rawNonce !== "string" || rawNonce.length === 0 || rawNonce.length > 512 || CONTROL_RE.test(rawNonce)) {
    throw new ApiError(400, "invalid_request", "raw_nonce is required.");
  }
  const authorizationCode = optionalString(body, "authorization_code", 4096);
  const fullName = sanitizeText(optionalString(body, "full_name", 1000), 100);

  let identity;
  try {
    identity = await verifyIdToken(identityToken, { provider: "apple", audience: bundleId, expectedNonce: await sha256Hex(rawNonce) }, deps);
  } catch (err) {
    if (err instanceof IdTokenError) {
      deps.log({ event: "id_token_rejected", request_id: info.requestId, provider: "apple_native", reason: err.reason });
      throw new ApiError(400, "invalid_grant", "The identity token was rejected.");
    }
    if (err instanceof JwksUnavailableError) throw new ApiError(500, "server_error", "Apple keys are unavailable, please retry.");
    throw err;
  }

  // Replay protection: each identity token nonce is accepted once.
  const replay = await env.DB.prepare("INSERT INTO apple_native_nonces (nonce_hash, expires_at) VALUES (?1, ?2) ON CONFLICT (nonce_hash) DO NOTHING")
    .bind(identity.nonce, identity.expiresAt)
    .run();
  if (replay.meta.changes !== 1) throw new ApiError(400, "invalid_grant", "The identity token was already used.");

  const userId = await findOrCreateUser(env, deps, {
    provider: "apple",
    subject: identity.subject,
    email: identity.email,
    emailVerified: identity.emailVerified,
    name: fullName,
    avatarUrl: null,
  });
  const now = deps.now();
  const s = await newSessionIds(deps);
  const owner = { userId, provider: "apple", subject: identity.subject };
  await env.DB.batch(sessionStatements(env.DB, s, owner, now, userAgent(request)));
  const response = await tokenResponse(env, keys, s, owner, now);

  if (authorizationCode) {
    // Best effort: a refresh token lets account deletion revoke the Apple authorization (§2.9).
    ctx.waitUntil(
      (async () => {
        try {
          const refresh = await exchangeNativeCode(env, deps, authorizationCode);
          if (!refresh) return;
          const sealed = await sealAppleToken(keys, deps, { client_id: bundleId, refresh_token: refresh });
          await storeSealedToken(env.DB, identity.subject, sealed);
        } catch (err) {
          deps.log({ event: "apple_native_exchange_failed", error: err instanceof Error ? err.name : "unknown" });
        }
      })(),
    );
  }
  return json(info, response);
}
