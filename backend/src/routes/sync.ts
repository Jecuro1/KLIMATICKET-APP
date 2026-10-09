// POST /v1/sync/push and GET /v1/sync/pull (docs/CLOUDFLARE_BACKEND.md §3.6, §3.7).
import type { Env } from "../env";
import type { Deps } from "../deps";
import { ApiError, MAX_PUSH_BODY_BYTES, checkContentLength, json, readJsonObject, type RequestInfo } from "../http";
import { authenticate } from "../sessions";
import { canonicalFromMs } from "../timestamps";
import { RESERVE_SQL, SCHEMAS, isSyncTable } from "../sync/schema";
import { prepareRows } from "../sync/validate";

export const PUSH_MAX_ROWS = 500;
export const PULL_MAX_LIMIT = 500;
const CLAMP_MS = 10 * 60_000;
const AFTER_RE = /^\d{1,15}$/;
const LIMIT_RE = /^\d{1,3}$/;

// ---------------------------------------------------------------------------------------------------------------
// Version gate (§3.1): only /v1/sync/*
// ---------------------------------------------------------------------------------------------------------------

function parseVersion(s: string | null | undefined): [number, number, number] | null {
  if (!s) return null;
  const m = /^(\d{1,6})(?:\.(\d{1,6}))?(?:\.(\d{1,6}))?$/.exec(s.trim());
  if (!m) return null;
  return [Number(m[1]), Number(m[2] ?? 0), Number(m[3] ?? 0)];
}

export function versionBelow(a: [number, number, number], b: [number, number, number]): boolean {
  for (let i = 0; i < 3; i++) {
    if (a[i]! !== b[i]!) return a[i]! < b[i]!;
  }
  return false;
}

function versionGate(request: Request, env: Env): void {
  const min = parseVersion(env.MIN_APP_VERSION);
  const app = parseVersion(request.headers.get("X-KB-App-Version"));
  if (min && app && versionBelow(app, min)) {
    throw new ApiError(426, "upgrade_required", "This app version is no longer supported.", {
      min_app_version: (env.MIN_APP_VERSION ?? "").trim(),
    });
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Push
// ---------------------------------------------------------------------------------------------------------------

function unknownTable(): ApiError {
  return new ApiError(400, "unknown_table", "Unknown sync table.");
}

export async function pushEndpoint(request: Request, env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  checkContentLength(request, MAX_PUSH_BODY_BYTES);
  versionGate(request, env);
  const auth = await authenticate(request, env, deps);
  const body = await readJsonObject(request, MAX_PUSH_BODY_BYTES);

  if (!isSyncTable(body.table)) throw unknownTable();
  const schema = SCHEMAS[body.table];
  const rawRows = body.rows;
  if (!Array.isArray(rawRows)) throw new ApiError(400, "invalid_request", "rows must be an array.");
  if (rawRows.length > PUSH_MAX_ROWS) {
    throw new ApiError(422, "too_many_rows", `At most ${PUSH_MAX_ROWS} rows per push.`, { max_rows: PUSH_MAX_ROWS });
  }

  const db = env.DB;
  if (rawRows.length === 0) {
    const current = await db.prepare("SELECT server_rev FROM sync_state WHERE id = 1").first<{ server_rev: number }>();
    return json(info, { applied: 0, skipped: 0, server_rev: current?.server_rev ?? 0 });
  }

  const now = deps.now();
  const { rows, received } = prepareRows(schema, rawRows, auth.userId, canonicalFromMs(now), canonicalFromMs(now + CLAMP_MS));
  const n = rows.length;
  let results: D1Result[];
  try {
    results = await db.batch([
      db.prepare(RESERVE_SQL).bind(n),
      db.prepare(schema.upsertSql).bind(auth.userId, JSON.stringify(rows), n),
    ]);
  } catch (err) {
    if (err instanceof Error && /FOREIGN KEY/i.test(err.message)) {
      // The user was deleted meanwhile.
      throw new ApiError(401, "invalid_token", "The account no longer exists.");
    }
    throw err;
  }
  const serverRev = (results[0]!.results[0] as { server_rev: number }).server_rev;
  const applied = results[1]!.meta.changes;
  return json(info, { applied, skipped: received - applied, server_rev: serverRev });
}

// ---------------------------------------------------------------------------------------------------------------
// Pull
// ---------------------------------------------------------------------------------------------------------------

export async function pullEndpoint(request: Request, env: Env, deps: Deps, info: RequestInfo): Promise<Response> {
  versionGate(request, env);
  const auth = await authenticate(request, env, deps);
  const q = new URL(request.url).searchParams;
  const table = q.get("table");
  if (!isSyncTable(table)) throw unknownTable();
  const schema = SCHEMAS[table];

  const afterRaw = q.get("after");
  if (afterRaw !== null && !AFTER_RE.test(afterRaw)) throw new ApiError(400, "invalid_request", "after must be a non-negative integer.");
  const after = afterRaw === null ? 0 : Number(afterRaw);
  const limitRaw = q.get("limit");
  let limit = PULL_MAX_LIMIT;
  if (limitRaw !== null) {
    limit = LIMIT_RE.test(limitRaw) ? Number(limitRaw) : 0;
    if (limit < 1 || limit > PULL_MAX_LIMIT) throw new ApiError(400, "invalid_request", `limit must be 1–${PULL_MAX_LIMIT}.`);
  }

  const result = await env.DB.prepare(schema.pullSql).bind(auth.userId, after, limit).all<Record<string, unknown>>();
  const rows = result.results;
  for (const row of rows) {
    for (const c of schema.boolColumns) row[c] = row[c] === 1;
  }
  const last = rows[rows.length - 1];
  const next = rows.length === limit && last ? (last.server_rev as number) : null;
  return json(info, { rows, next });
}
