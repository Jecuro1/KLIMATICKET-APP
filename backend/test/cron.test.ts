// Daily cleanup (docs/CLOUDFLARE_BACKEND.md §3.10).
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { runCleanup } from "../src/cron";
import { count, db, directSession, makeDeps, testEnv, uuid } from "./helpers";

const DAY = 86_400_000;

describe("cron cleanup", () => {
  it("removes expired auth state, old rate-limit windows, dead sessions and orphan users; keeps live data", async () => {
    const deps = makeDeps();
    const now = deps.now();
    const d = db();
    const live = await directSession(deps);
    const dead = await directSession(deps);
    const recentlyRevoked = await directSession(deps);
    await d.batch([
      // Revoked 31 days ago → removed with its refresh tokens; revoked yesterday → kept.
      d.prepare("UPDATE sessions SET revoked_at = ?2 WHERE id = ?1").bind(dead.sessionId, now - 31 * DAY),
      d.prepare("UPDATE sessions SET revoked_at = ?2 WHERE id = ?1").bind(recentlyRevoked.sessionId, now - DAY),
      d.prepare(
        `INSERT INTO auth_flows (id, provider, nonce, app_code_challenge, app_state, app_redirect_uri, created_at, expires_at)
         VALUES ('cron-old-flow', 'google', 'n', 'c', 's', 'r', 0, ?1), ('cron-new-flow', 'google', 'n', 'c', 's', 'r', 0, ?2)`,
      ).bind(now - 1, now + 60_000),
      d.prepare(
        `INSERT INTO auth_codes (code_hash, user_id, provider, subject, code_challenge, redirect_uri, created_at, expires_at)
         VALUES ('cron-old-code', ?1, 'google', 's', 'c', 'r', 0, ?2), ('cron-new-code', ?1, 'google', 's', 'c', 'r', 0, ?3)`,
      ).bind(live.userId, now - 1, now + 60_000),
      d.prepare("INSERT INTO apple_native_nonces (nonce_hash, expires_at) VALUES ('cron-old-nonce', ?1), ('cron-new-nonce', ?2)").bind(now - 1, now + 1),
      d.prepare("INSERT INTO rate_limits (bucket, window_start, count) VALUES ('cron:old', ?1, 3), ('cron:new', ?2, 3)").bind(now - DAY - 1, now - 1000),
      d.prepare("INSERT INTO refresh_tokens (token_hash, session_id, created_at, expires_at) VALUES ('cron-old-rt', ?1, 0, ?2)").bind(live.sessionId, now - DAY - 1),
    ]);
    const orphanOld = uuid();
    const orphanNew = uuid();
    await d.batch([
      d.prepare("INSERT INTO users (id, created_at, last_login_at) VALUES (?1, ?2, ?2)").bind(orphanOld, now - 2 * DAY),
      d.prepare("INSERT INTO users (id, created_at, last_login_at) VALUES (?1, ?2, ?2)").bind(orphanNew, now - 1000),
    ]);

    const result = await runCleanup(testEnv(), deps);
    expect(result).toMatchObject({ auth_flows: expect.any(Number), sessions: expect.any(Number) });
    const exists = (sql: string, ...args: unknown[]) => count(sql, ...args).then((n) => n > 0);
    expect(await exists("SELECT COUNT(*) AS n FROM auth_flows WHERE id = 'cron-old-flow'")).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM auth_flows WHERE id = 'cron-new-flow'")).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM auth_codes WHERE code_hash = 'cron-old-code'")).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM auth_codes WHERE code_hash = 'cron-new-code'")).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM apple_native_nonces WHERE nonce_hash = 'cron-old-nonce'")).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM apple_native_nonces WHERE nonce_hash = 'cron-new-nonce'")).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM rate_limits WHERE bucket = 'cron:old'")).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM rate_limits WHERE bucket = 'cron:new'")).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM refresh_tokens WHERE token_hash = 'cron-old-rt'")).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM sessions WHERE id = ?1", dead.sessionId)).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM refresh_tokens WHERE session_id = ?1", dead.sessionId)).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM sessions WHERE id = ?1", recentlyRevoked.sessionId)).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM sessions WHERE id = ?1", live.sessionId)).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM refresh_tokens WHERE session_id = ?1", live.sessionId)).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM users WHERE id = ?1", orphanOld)).toBe(false);
    expect(await exists("SELECT COUNT(*) AS n FROM users WHERE id = ?1", orphanNew)).toBe(true);
    expect(await exists("SELECT COUNT(*) AS n FROM users WHERE id = ?1", live.userId)).toBe(true);
    expect(deps.logs.some((l) => l.event === "cron_cleanup")).toBe(true);
  });

  it("removes sessions that expired more than 30 days ago", async () => {
    const deps = makeDeps();
    const s = await directSession(deps);
    await db().prepare("UPDATE sessions SET expires_at = ?2 WHERE id = ?1").bind(s.sessionId, deps.now() - 31 * DAY).run();
    await runCleanup(testEnv(), deps);
    expect(await count("SELECT COUNT(*) AS n FROM sessions WHERE id = ?1", s.sessionId)).toBe(0);
  });

  it("the scheduled handler runs the cleanup", async () => {
    await db().prepare("INSERT INTO auth_flows (id, provider, nonce, app_code_challenge, app_state, app_redirect_uri, created_at, expires_at) VALUES ('cron-sched', 'google', 'n', 'c', 's', 'r', 0, 1)").run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "23 3 * * *", scheduledTime: Date.now() }), testEnv(), ctx);
    await waitOnExecutionContext(ctx);
    expect(await count("SELECT COUNT(*) AS n FROM auth_flows WHERE id = 'cron-sched'")).toBe(0);
  });
});
