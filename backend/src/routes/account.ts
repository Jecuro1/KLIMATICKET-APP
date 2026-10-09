// GET/PATCH /v1/me and POST /v1/account/delete (docs/CLOUDFLARE_BACKEND.md §3.2, §3.9).
import type { Env } from "../env";
import type { Ctx, Deps } from "../deps";
import { revokeAppleTokens } from "../apple";
import { ApiError, json, readJsonObject, type RequestInfo } from "../http";
import { authenticate, loadUser } from "../sessions";
import { enforceLimit } from "./token";

const CONTROL_RE = /[\u0000-\u001F\u007F-\u009F]/g;

export async function getMe(request: Request, env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  const auth = await authenticate(request, env, deps);
  const user = await loadUser(env.DB, auth.userId, auth.provider, auth.subject);
  if (!user) throw new ApiError(401, "invalid_token", "The account no longer exists.");
  const identities = await env.DB.prepare("SELECT provider, email FROM identities WHERE user_id = ?1 ORDER BY created_at, provider")
    .bind(auth.userId)
    .all<{ provider: string; email: string | null }>();
  return json(info, { user, identities: identities.results.map((r) => ({ provider: r.provider, email: r.email ?? null })) });
}

export async function patchMe(request: Request, env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  const auth = await authenticate(request, env, deps);
  const body = await readJsonObject(request);
  if (!Object.hasOwn(body, "display_name")) throw new ApiError(400, "invalid_request", "display_name is required.");
  const raw = body.display_name;
  let displayName: string | null;
  if (raw === null) {
    displayName = null;
  } else if (typeof raw === "string") {
    displayName = raw.replace(CONTROL_RE, "").trim();
    if (displayName.length < 1 || displayName.length > 100) {
      throw new ApiError(400, "invalid_request", "display_name must be 1–100 characters (or null).");
    }
  } else {
    throw new ApiError(400, "invalid_request", "display_name must be a string or null.");
  }
  const now = deps.now();
  await env.DB.prepare(
    `INSERT INTO profiles (user_id, display_name, avatar_url, created_at, updated_at) VALUES (?1, ?2, NULL, ?3, ?3)
     ON CONFLICT (user_id) DO UPDATE SET display_name = excluded.display_name, updated_at = excluded.updated_at`,
  )
    .bind(auth.userId, displayName, now)
    .run();
  const user = await loadUser(env.DB, auth.userId, auth.provider, auth.subject);
  if (!user) throw new ApiError(401, "invalid_token", "The account no longer exists.");
  return json(info, { user });
}

export async function deleteAccount(request: Request, env: Env, ctx: Ctx, deps: Deps, info: RequestInfo): Promise<Response> {
  const auth = await authenticate(request, env, deps);
  await enforceLimit(env, auth.keys, deps, "account_delete", auth.userId);
  await readJsonObject(request, undefined, true);
  const db = env.DB;
  const uid = auth.userId;

  const sealed = await db
    .prepare("SELECT provider_refresh_token FROM identities WHERE user_id = ?1 AND provider = 'apple' AND provider_refresh_token IS NOT NULL")
    .bind(uid)
    .all<{ provider_refresh_token: string }>();

  const del = (sql: string) => db.prepare(sql).bind(uid);
  await db.batch([
    del("DELETE FROM tickets WHERE user_id = ?1"),
    del("DELETE FROM trips WHERE user_id = ?1"),
    del("DELETE FROM favorite_routes WHERE user_id = ?1"),
    del("DELETE FROM benefits WHERE user_id = ?1"),
    del("DELETE FROM refresh_tokens WHERE session_id IN (SELECT id FROM sessions WHERE user_id = ?1)"),
    del("DELETE FROM sessions WHERE user_id = ?1"),
    del("DELETE FROM auth_codes WHERE user_id = ?1"),
    del("DELETE FROM identities WHERE user_id = ?1"),
    del("DELETE FROM profiles WHERE user_id = ?1"),
    del("DELETE FROM users WHERE id = ?1"),
  ]);
  deps.log({ event: "account_deleted", request_id: info.requestId });

  const tokens = sealed.results.map((r) => r.provider_refresh_token);
  if (tokens.length > 0) ctx.waitUntil(revokeAppleTokens(env, deps, auth.keys, tokens));
  return json(info, { deleted: true });
}
