// Fixed-window rate limits in D1 (docs/CLOUDFLARE_BACKEND.md §2.8). Fails open when D1 fails.
import type { Deps } from "./deps";
import { base64urlEncode, hmacSign } from "./crypto";
import type { Keys } from "./keys";

export type LimitName = "auth_start" | "auth_callback" | "auth_token" | "auth_native" | "auth_logout" | "account_delete";

const MINUTE = 60_000;

export const LIMITS: Record<LimitName, { limit: number; windowMs: number }> = {
  auth_start: { limit: 30, windowMs: 10 * MINUTE },
  auth_callback: { limit: 30, windowMs: 10 * MINUTE },
  auth_token: { limit: 120, windowMs: 10 * MINUTE },
  auth_native: { limit: 20, windowMs: 10 * MINUTE },
  auth_logout: { limit: 60, windowMs: 10 * MINUTE },
  account_delete: { limit: 5, windowMs: 60 * MINUTE },
};

export interface RateDecision {
  allowed: boolean;
  /** Seconds until the window ends (for Retry-After). */
  retryAfter: number;
}

const HIT_SQL = `INSERT INTO rate_limits (bucket, window_start, count) VALUES (?1, ?2, 1)
ON CONFLICT (bucket) DO UPDATE SET
  count = CASE WHEN rate_limits.window_start = excluded.window_start THEN rate_limits.count + 1 ELSE 1 END,
  window_start = excluded.window_start
RETURNING count`;

export async function bucketFor(keys: Keys, name: LimitName, subject: string): Promise<string> {
  const mac = await hmacSign(keys.current.rateLimit, subject);
  return `${name}:${base64urlEncode(mac).slice(0, 22)}`;
}

/** Counts one hit for `subject` (IP or user id) and decides. */
export async function hit(db: D1Database, keys: Keys, deps: Deps, name: LimitName, subject: string): Promise<RateDecision> {
  const { limit, windowMs } = LIMITS[name];
  const now = deps.now();
  const windowStart = Math.floor(now / windowMs) * windowMs;
  const retryAfter = Math.max(1, Math.ceil((windowStart + windowMs - now) / 1000));
  try {
    const bucket = await bucketFor(keys, name, subject);
    const row = await db.prepare(HIT_SQL).bind(bucket, windowStart).first<{ count: number }>();
    const count = row?.count ?? 0;
    return { allowed: count <= limit, retryAfter };
  } catch (err) {
    deps.log({ event: "rate_limit_failed_open", limit: name, error: err instanceof Error ? err.name : "unknown" });
    return { allowed: true, retryAfter };
  }
}
