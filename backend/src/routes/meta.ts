// GET /v1/health and GET /v1/config (docs/CLOUDFLARE_BACKEND.md §3.2, §3.3).
import type { Env } from "../env";
import type { Deps } from "../deps";
import { MAX_PUSH_BODY_BYTES, json, type RequestInfo } from "../http";
import { providerFlags } from "../providers";
import { SYNC_TABLES } from "../sync/schema";
import { canonicalFromMs } from "../timestamps";
import { PULL_MAX_LIMIT, PUSH_MAX_ROWS } from "./sync";

export async function health(env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  try {
    const row = await env.DB.prepare("SELECT server_rev FROM sync_state WHERE id = 1").first<{ server_rev: number }>();
    if (row) return json(info, { ok: true });
  } catch (err) {
    deps.log({ event: "health_db_failed", request_id: info.requestId, error: err instanceof Error ? err.name : "unknown" });
  }
  info.errorCode = "unhealthy";
  return json(info, { ok: false }, 503);
}

export async function config(env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  return json(info, {
    api_version: 1,
    providers: await providerFlags(env, deps),
    min_app_version: (env.MIN_APP_VERSION ?? "").trim() || "1.0.0",
    sync_tables: [...SYNC_TABLES],
    limits: { push_max_rows: PUSH_MAX_ROWS, pull_max_limit: PULL_MAX_LIMIT, max_body_bytes: MAX_PUSH_BODY_BYTES },
    server_time: canonicalFromMs(deps.now()),
  });
}
