// Router, headers, origin policy, body limits, config/health, server_not_configured, version gate.
import { describe, expect, it } from "vitest";
import { exports } from "cloudflare:workers";
import type { Env } from "../src/env";
import { BASE, bearer, call, directSession, expectError, get, makeDeps, postJson, testEnv } from "./helpers";

const SECURITY = {
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "x-kb-api": "1",
  "strict-transport-security": "max-age=31536000",
};

function expectSecurityHeaders(res: Response): void {
  for (const [k, v] of Object.entries(SECURITY)) expect(res.headers.get(k), k).toBe(v);
  expect(res.headers.get("x-request-id")).toMatch(/^[A-Za-z0-9-]{1,64}$/);
  expect(res.headers.get("access-control-allow-origin")).toBeNull();
}

describe("routing and headers", () => {
  it("health answers ok through the real Worker export", async () => {
    const res = await exports.default.fetch(new Request(`${BASE}/v1/health`));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expectSecurityHeaders(res);
  });

  it("health reports 503 when D1 fails", async () => {
    const deps = makeDeps();
    const broken = { prepare: () => ({ first: async () => { throw new Error("D1 down"); } }) } as unknown as D1Database;
    const res = await call(deps, get("/v1/health"), { DB: broken });
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ ok: false });
  });

  it("uses cf-ray as request id", async () => {
    const res = await call(makeDeps(), get("/v1/health", { "cf-ray": "8a1b2c3d4e5f-VIE" }));
    expect(res.headers.get("x-request-id")).toBe("8a1b2c3d4e5f-VIE");
  });

  it("unknown paths → 404 not_found; wrong method → 405 with Allow", async () => {
    const deps = makeDeps();
    let res = await call(deps, get("/v1/nope"));
    expectSecurityHeaders(res);
    await expectError(res, 404, "not_found");
    await expectError(await call(deps, get("/")), 404, "not_found");
    await expectError(await call(deps, get("/v1/health/")), 404, "not_found");
    await expectError(await call(deps, get("/v1/auth/facebook/start")), 404, "not_found");
    await expectError(await call(deps, postJson("/v1/account/link", {})), 404, "not_found");
    res = await call(deps, postJson("/v1/health", {}));
    expect(res.headers.get("allow")).toBe("GET");
    await expectError(res, 405, "method_not_allowed");
    res = await call(deps, get("/v1/auth/apple/callback"));
    expect(res.headers.get("allow")).toBe("POST");
    await expectError(res, 405, "method_not_allowed");
    res = await call(deps, postJson("/v1/auth/google/callback", {}));
    expect(res.headers.get("allow")).toBe("GET");
    res = await call(deps, new Request(`${BASE}/v1/me`, { method: "DELETE" }));
    expect(res.headers.get("allow")).toBe("GET, PATCH");
  });

  it("rejects OPTIONS everywhere and Origin on API endpoints (no CORS)", async () => {
    const deps = makeDeps();
    for (const path of ["/v1/health", "/v1/sync/push", "/v1/nope"]) {
      const res = await call(deps, new Request(`${BASE}${path}`, { method: "OPTIONS", headers: { Origin: "https://evil.test" } }));
      expectSecurityHeaders(res);
      await expectError(res, 403, "origin_not_allowed");
    }
    for (const req of [
      get("/v1/config", { Origin: "https://evil.test" }),
      get("/v1/me", { Origin: "null" }),
      postJson("/v1/sync/push", { table: "trips", rows: [] }, { Origin: "https://evil.test" }),
      postJson("/v1/auth/token", { grant_type: "refresh_token" }, { Origin: "https://evil.test" }),
    ]) {
      await expectError(await call(deps, req), 403, "origin_not_allowed");
    }
  });

  it("errors carry the OAuth-style body", async () => {
    const res = await call(makeDeps(), get("/v1/me"));
    expect(res.headers.get("www-authenticate")).toBe('Bearer error="invalid_token"');
    const body = await expectError(res, 401, "invalid_token");
    expect(Object.keys(body).sort()).toEqual(["error", "error_description", "request_id"]);
  });
});

describe("body limits and media types", () => {
  it("413 on Content-Length above the limit and on streamed bodies above the limit", async () => {
    const deps = makeDeps();
    const s = await directSession(deps);
    // Declared length (push limit 1 MiB).
    let res = await call(
      deps,
      new Request(`${BASE}/v1/sync/push`, {
        method: "POST",
        headers: { ...bearer(s.accessToken), "Content-Type": "application/json", "Content-Length": "1048577" },
        body: "{}",
      }),
    );
    await expectError(res, 413, "payload_too_large");
    // Actual bytes (streamed without Content-Length).
    const big = JSON.stringify({ table: "trips", rows: [], pad: "x".repeat(1_048_600) });
    const stream = new ReadableStream({
      start(c) {
        c.enqueue(new TextEncoder().encode(big));
        c.close();
      },
    });
    res = await call(
      deps,
      new Request(`${BASE}/v1/sync/push`, { method: "POST", headers: { ...bearer(s.accessToken), "Content-Type": "application/json" }, body: stream }),
    );
    await expectError(res, 413, "payload_too_large");
    // 64 KiB on other endpoints.
    res = await call(deps, postJson("/v1/me", { display_name: "x".repeat(70_000) }, bearer(s.accessToken), "PATCH"));
    await expectError(res, 413, "payload_too_large");
  });

  it("415 without JSON content type, 400 on broken JSON or non-object bodies", async () => {
    const deps = makeDeps();
    const s = await directSession(deps);
    let res = await call(
      deps,
      new Request(`${BASE}/v1/sync/push`, { method: "POST", headers: { ...bearer(s.accessToken), "Content-Type": "text/plain" }, body: "{}" }),
    );
    await expectError(res, 415, "unsupported_media_type");
    res = await call(deps, postJson("/v1/sync/push", "{nope", bearer(s.accessToken)));
    await expectError(res, 400, "invalid_request");
    res = await call(deps, postJson("/v1/sync/push", "[1,2]", bearer(s.accessToken)));
    await expectError(res, 400, "invalid_request");
    res = await call(
      deps,
      new Request(`${BASE}/v1/auth/token`, { method: "POST", headers: { "Content-Type": "text/plain" }, body: "grant_type=refresh_token" }),
    );
    await expectError(res, 415, "unsupported_media_type");
    res = await call(deps, postJson("/v1/auth/token", { grant_type: 5 }));
    await expectError(res, 400, "invalid_request");
    res = await call(
      deps,
      new Request(`${BASE}/v1/auth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "grant_type=refresh_token&refresh_token=a&refresh_token=b",
      }),
    );
    await expectError(res, 400, "invalid_request");
  });
});

describe("GET /v1/config", () => {
  const all: Partial<Env> = {
    GOOGLE_CLIENT_ID: "g",
    GOOGLE_CLIENT_SECRET: "gs",
    MICROSOFT_CLIENT_ID: "m",
    MICROSOFT_CLIENT_SECRET: "ms",
    APPLE_BUNDLE_ID: "com.example.app",
  };

  async function cfg(over: Partial<Env>): Promise<Record<string, unknown>> {
    const res = await call(makeDeps(), get("/v1/config"), over);
    expect(res.status).toBe(200);
    return (await res.json()) as Record<string, unknown>;
  }

  it("reports versions, tables, limits and server time", async () => {
    const body = await cfg({});
    expect(body).toEqual({
      api_version: 1,
      providers: { google: { web: false }, microsoft: { web: false }, apple: { web: false, native: false } },
      min_app_version: "1.0.0",
      sync_tables: ["tickets", "trips", "favorite_routes", "benefits"],
      features: ["trip_via"],
      limits: { push_max_rows: 500, pull_max_limit: 500, max_body_bytes: 1048576 },
      server_time: "2026-10-09T12:00:00.000000Z",
    });
  });

  it("enables each provider only with its complete secret set", async () => {
    expect((await cfg(all)).providers).toEqual({
      google: { web: true },
      microsoft: { web: true },
      apple: { web: false, native: true },
    });
    expect((await cfg({ GOOGLE_CLIENT_ID: "g" })).providers).toMatchObject({ google: { web: false } });
    expect((await cfg({ GOOGLE_CLIENT_ID: "g", GOOGLE_CLIENT_SECRET: "  " })).providers).toMatchObject({ google: { web: false } });
    expect((await cfg({ MICROSOFT_CLIENT_SECRET: "ms" })).providers).toMatchObject({ microsoft: { web: false } });
    // Apple web needs all four values and a key that parses.
    const ec = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
    const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", ec.privateKey)) as ArrayBuffer);
    const b64 = btoa(String.fromCharCode(...der));
    const apple = { APPLE_SERVICES_ID: "s", APPLE_TEAM_ID: "t", APPLE_KEY_ID: "k", APPLE_PRIVATE_KEY: b64 };
    expect((await cfg(apple)).providers).toMatchObject({ apple: { web: true, native: false } });
    expect((await cfg({ ...apple, APPLE_KEY_ID: undefined })).providers).toMatchObject({ apple: { web: false } });
    expect((await cfg({ ...apple, APPLE_PRIVATE_KEY: "garbage!" })).providers).toMatchObject({ apple: { web: false } });
  });

  it("reports every provider disabled when SESSION_SIGNING_KEY is unusable", async () => {
    for (const key of [undefined, "short"]) {
      const body = await cfg({ ...all, SESSION_SIGNING_KEY: key });
      expect(body.providers).toEqual({ google: { web: false }, microsoft: { web: false }, apple: { web: false, native: false } });
    }
  });

  it("uses MIN_APP_VERSION", async () => {
    expect((await cfg({ MIN_APP_VERSION: "1.4.2" })).min_app_version).toBe("1.4.2");
  });
});

describe("server_not_configured", () => {
  it("answers 503 on auth and authenticated endpoints while health/config keep working", async () => {
    const deps = makeDeps();
    const over = { SESSION_SIGNING_KEY: undefined };
    for (const req of [
      postJson("/v1/auth/token", { grant_type: "refresh_token", refresh_token: "x" }),
      postJson("/v1/auth/logout", {}),
      postJson("/v1/auth/apple/native", {}),
      get("/v1/me", bearer("x.y.z")),
      postJson("/v1/sync/push", { table: "trips", rows: [] }, bearer("x.y.z")),
      get("/v1/sync/pull?table=trips", bearer("x.y.z")),
      postJson("/v1/account/delete", {}, bearer("x.y.z")),
    ]) {
      await expectError(await call(deps, req, over), 503, "server_not_configured");
    }
    expect((await call(deps, get("/v1/health"), over)).status).toBe(200);
    expect((await call(deps, get("/v1/config"), over)).status).toBe(200);
  });
});

describe("version gate (sync only)", () => {
  it("426 for apps below MIN_APP_VERSION; missing or unparsable versions pass", async () => {
    const deps = makeDeps();
    const s = await directSession(deps);
    const over = { MIN_APP_VERSION: "1.2.0" };
    const pull = (v?: string) =>
      call(deps, get("/v1/sync/pull?table=trips", { ...bearer(s.accessToken), ...(v ? { "X-KB-App-Version": v } : {}) }), over);
    const body = await expectError(await pull("1.1.9"), 426, "upgrade_required");
    expect(body.min_app_version).toBe("1.2.0");
    await expectError(await pull("1"), 426, "upgrade_required");
    expect((await pull("1.2")).status).toBe(200);
    expect((await pull("1.10.0")).status).toBe(200);
    expect((await pull()).status).toBe(200);
    expect((await pull("beta")).status).toBe(200);
    await expectError(
      await call(deps, postJson("/v1/sync/push", { table: "trips", rows: [] }, { ...bearer(s.accessToken), "X-KB-App-Version": "0.9" }), over),
      426,
      "upgrade_required",
    );
    // /v1/me is not gated.
    expect((await call(deps, get("/v1/me", { ...bearer(s.accessToken), "X-KB-App-Version": "0.1" }), over)).status).toBe(200);
  });
});

describe("environment", () => {
  it("the test env has the template vars", () => {
    const env = testEnv();
    expect(env.APP_REDIRECT_URIS).toBe("klimabilanz://auth-callback");
    expect(env.PUBLIC_BASE_URL).toBe("");
  });
});
