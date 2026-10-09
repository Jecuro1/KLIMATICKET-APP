// Rate limits (docs/CLOUDFLARE_BACKEND.md §2.8): fixed windows in D1, 429 + Retry-After, app redirects on
// /start and /callback, per-user account deletion limit, fail open.
import { beforeAll, describe, expect, it } from "vitest";
import { loadKeys } from "../src/keys";
import { LIMITS, bucketFor } from "../src/ratelimit";
import {
  ProviderWorld,
  appPkce,
  bearer,
  call,
  db,
  directSession,
  expectError,
  get,
  postForm,
  postJson,
  startUrl,
  testEnv,
  unique,
  uniqueIp,
  type TestDeps,
} from "./helpers";

let world: ProviderWorld;
let deps: TestDeps;

beforeAll(async () => {
  world = await ProviderWorld.create();
  deps = world.deps;
});

function tokenAttempt(ip: string): Request {
  return postForm("/v1/auth/token", { grant_type: "refresh_token", refresh_token: "A".repeat(43) }, { "CF-Connecting-IP": ip });
}

describe("rate limits", () => {
  it("auth_token: 120 per 10 minutes per IP, then 429 with Retry-After; resets in the next window", async () => {
    // Align to the start of a window so the whole test stays inside it.
    const w = LIMITS.auth_token.windowMs;
    deps.clock.t = Math.ceil(deps.clock.t / w) * w + 1000;
    const ip = uniqueIp();
    for (let i = 0; i < 120; i++) {
      const res = await call(deps, tokenAttempt(ip));
      expect(res.status).toBe(400);
    }
    const limited = await call(deps, tokenAttempt(ip));
    await expectError(limited, 429, "rate_limited");
    expect(limited.headers.get("Retry-After")).toBe(String((w - 1000) / 1000));
    // Another IP is not affected.
    expect((await call(deps, tokenAttempt(uniqueIp()))).status).toBe(400);
    // Next window.
    deps.clock.advance(w);
    expect((await call(deps, tokenAttempt(ip))).status).toBe(400);
  });

  it("auth_start: the 31st start redirects to the app with error=rate_limited", async () => {
    const ip = uniqueIp();
    const pk = await appPkce();
    const w = LIMITS.auth_start.windowMs;
    deps.clock.t = Math.ceil(deps.clock.t / w) * w + 1000;
    for (let i = 0; i < 30; i++) {
      const res = await call(deps, get(startUrl("google", pk), { "CF-Connecting-IP": ip }), world.env());
      expect(new URL(res.headers.get("Location")!).hostname).toBe("accounts.google.com");
    }
    const res = await call(deps, get(startUrl("google", pk), { "CF-Connecting-IP": ip }), world.env());
    expect(res.status).toBe(302);
    const app = new URL(res.headers.get("Location")!);
    expect(app.protocol).toBe("klimabilanz:");
    expect(app.searchParams.get("error")).toBe("rate_limited");
    expect(app.searchParams.get("state")).toBe(pk.state);
    expect(res.headers.get("Retry-After")).toBeTruthy();
  });

  it("auth_callback: over the limit → app redirect (known flow) or 429 page (unknown flow)", async () => {
    const ip = uniqueIp();
    const keys = (await loadKeys(testEnv()))!;
    const w = LIMITS.auth_callback.windowMs;
    const windowStart = Math.floor(deps.now() / w) * w;
    await db()
      .prepare("INSERT OR REPLACE INTO rate_limits (bucket, window_start, count) VALUES (?1, ?2, 30)")
      .bind(await bucketFor(keys, "auth_callback", ip), windowStart)
      .run();
    const pk = await appPkce();
    const start = await call(deps, get(startUrl("google", pk)), world.env());
    const { code, state } = world.authorize(start.headers.get("Location")!, unique("sub"));
    const res = await call(deps, get(`/v1/auth/google/callback?${new URLSearchParams({ code, state })}`, { "CF-Connecting-IP": ip }), world.env());
    expect(new URL(res.headers.get("Location")!).searchParams.get("error")).toBe("rate_limited");
    const unknown = await call(deps, get(`/v1/auth/google/callback?state=${"B".repeat(43)}`, { "CF-Connecting-IP": ip }), world.env());
    expect(unknown.status).toBe(429);
    expect(unknown.headers.get("Retry-After")).toBeTruthy();
  });

  it("auth_native (20) and auth_logout (60) per IP", async () => {
    const ip = uniqueIp();
    for (let i = 0; i < 20; i++) {
      const res = await call(deps, postJson("/v1/auth/apple/native", { identity_token: "a.b.c", raw_nonce: "n" }, { "CF-Connecting-IP": ip }), world.env());
      expect(res.status).toBe(400);
    }
    await expectError(
      await call(deps, postJson("/v1/auth/apple/native", { identity_token: "a.b.c", raw_nonce: "n" }, { "CF-Connecting-IP": ip }), world.env()),
      429,
      "rate_limited",
    );
    for (let i = 0; i < 60; i++) {
      expect((await call(deps, postJson("/v1/auth/logout", {}, { "CF-Connecting-IP": ip }))).status).toBe(204);
    }
    await expectError(await call(deps, postJson("/v1/auth/logout", {}, { "CF-Connecting-IP": ip })), 429, "rate_limited");
  });

  it("account_delete: 5 per hour per user", async () => {
    const s = await directSession(deps);
    const keys = (await loadKeys(testEnv()))!;
    const w = LIMITS.account_delete.windowMs;
    await db()
      .prepare("INSERT OR REPLACE INTO rate_limits (bucket, window_start, count) VALUES (?1, ?2, 5)")
      .bind(await bucketFor(keys, "account_delete", s.userId), Math.floor(deps.now() / w) * w)
      .run();
    await expectError(await call(deps, postJson("/v1/account/delete", {}, bearer(s.accessToken))), 429, "rate_limited");
    expect((await call(deps, get("/v1/me", bearer(s.accessToken)))).status).toBe(200);
  });

  it("buckets are HMACs of the subject (no raw IPs stored)", async () => {
    const ip = "203.0.113.99";
    await call(deps, tokenAttempt(ip));
    const rows = await db().prepare("SELECT bucket FROM rate_limits").all<{ bucket: string }>();
    expect(rows.results.some((r) => r.bucket.includes(ip))).toBe(false);
    expect(rows.results.every((r) => /^[a-z_]+:[A-Za-z0-9_-]{22}$/.test(r.bucket))).toBe(true);
  });

  it("fails open (and logs) when the limiter's D1 write fails", async () => {
    const real = db();
    const flaky = new Proxy(real, {
      get(target, prop, receiver) {
        if (prop === "prepare") {
          return (sql: string) => {
            if (sql.includes("rate_limits")) throw new Error("D1 overloaded");
            return target.prepare(sql);
          };
        }
        const v = Reflect.get(target, prop, receiver);
        return typeof v === "function" ? v.bind(target) : v;
      },
    });
    const d = world.freshDeps();
    const res = await call(d, tokenAttempt(uniqueIp()), { DB: flaky });
    await expectError(res, 400, "invalid_grant");
    expect(d.logs.some((l) => l.event === "rate_limit_failed_open")).toBe(true);
  });
});
