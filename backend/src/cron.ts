// Daily cleanup (docs/CLOUDFLARE_BACKEND.md §3.10). Every delete is bounded so one run stays within the limits.
import type { Env } from "./env";
import type { Deps } from "./deps";

const DAY = 24 * 60 * 60 * 1000;
export const CRON_BATCH_LIMIT = 5000;

export interface CronResult {
  auth_flows: number;
  auth_codes: number;
  apple_native_nonces: number;
  rate_limits: number;
  refresh_tokens: number;
  sessions: number;
  orphan_users: number;
}

export async function runCleanup(env: Env, deps: Deps): Promise<CronResult> {
  const db = env.DB;
  const now = deps.now();
  const L = CRON_BATCH_LIMIT;
  const results = await db.batch([
    db.prepare(`DELETE FROM auth_flows WHERE rowid IN (SELECT rowid FROM auth_flows WHERE expires_at < ?1 LIMIT ${L})`).bind(now),
    db.prepare(`DELETE FROM auth_codes WHERE rowid IN (SELECT rowid FROM auth_codes WHERE expires_at < ?1 LIMIT ${L})`).bind(now),
    db
      .prepare(`DELETE FROM apple_native_nonces WHERE rowid IN (SELECT rowid FROM apple_native_nonces WHERE expires_at < ?1 LIMIT ${L})`)
      .bind(now),
    db.prepare(`DELETE FROM rate_limits WHERE rowid IN (SELECT rowid FROM rate_limits WHERE window_start < ?1 LIMIT ${L})`).bind(now - DAY),
    db
      .prepare(`DELETE FROM refresh_tokens WHERE rowid IN (SELECT rowid FROM refresh_tokens WHERE expires_at < ?1 LIMIT ${L})`)
      .bind(now - DAY),
    // Revoked or expired for more than 30 days (cascades to their refresh tokens).
    db
      .prepare(
        `DELETE FROM sessions WHERE rowid IN (SELECT rowid FROM sessions
           WHERE (revoked_at IS NOT NULL AND revoked_at < ?1) OR expires_at < ?1 LIMIT ${L})`,
      )
      .bind(now - 30 * DAY),
    // Orphans from racing first logins (§2.6): users without identities, older than a day.
    db
      .prepare(
        `DELETE FROM users WHERE rowid IN (SELECT u.rowid FROM users u
           WHERE u.created_at < ?1 AND NOT EXISTS (SELECT 1 FROM identities i WHERE i.user_id = u.id) LIMIT ${L})`,
      )
      .bind(now - DAY),
  ]);
  const n = (i: number) => results[i]?.meta.changes ?? 0;
  const out: CronResult = {
    auth_flows: n(0),
    auth_codes: n(1),
    apple_native_nonces: n(2),
    rate_limits: n(3),
    refresh_tokens: n(4),
    sessions: n(5),
    orphan_users: n(6),
  };
  deps.log({ event: "cron_cleanup", ...out });
  return out;
}
