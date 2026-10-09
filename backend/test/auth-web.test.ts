// Browser flow: /start → provider → /callback → /token (docs/CLOUDFLARE_BACKEND.md §2.3, §2.5, §2.6).
import { beforeAll, describe, expect, it } from "vitest";
import { decodeJwt } from "../src/crypto";
import type { ProviderName } from "../src/providers";
import {
  APP_REDIRECT,
  BASE,
  FakeIdp,
  MS_TENANT,
  ProviderWorld,
  appPkce,
  bearer,
  call,
  callbackRequest,
  count,
  db,
  expectError,
  get,
  postForm,
  signInWeb,
  startUrl,
  unique,
  uniqueIp,
  type TestDeps,
  type TokenMutation,
} from "./helpers";

let world: ProviderWorld;
let deps: TestDeps;

beforeAll(async () => {
  world = await ProviderWorld.create();
  deps = world.deps;
});

/** start + provider authorize + callback; returns the app redirect URL (no token exchange). */
async function toCallback(
  p: ProviderName,
  mutation: TokenMutation = {},
  extra: Record<string, string> = {},
): Promise<{ res: Response; app: URL | null; pk: Awaited<ReturnType<typeof appPkce>>; state: string; code: string }> {
  const pk = await appPkce();
  const ip = uniqueIp();
  const start = await call(deps, get(startUrl(p, pk), { "CF-Connecting-IP": ip }), world.env());
  expect(start.status).toBe(302);
  const { code, state } = world.authorize(start.headers.get("Location")!, unique("sub"), mutation);
  const res = await call(deps, callbackRequest(p, { code, state, ...extra }, { "CF-Connecting-IP": ip }), world.env());
  const loc = res.headers.get("Location");
  return { res, app: loc ? new URL(loc) : null, pk, state, code };
}

function tokenRequest(code: string, verifier: string, redirect = APP_REDIRECT): Request {
  return postForm("/v1/auth/token", { grant_type: "authorization_code", code, code_verifier: verifier, redirect_uri: redirect }, {
    "CF-Connecting-IP": uniqueIp(),
  });
}

describe("GET /v1/auth/{provider}/start", () => {
  it("redirects to Google with state, nonce, PKCE S256 and the documented extras", async () => {
    const pk = await appPkce();
    const res = await call(deps, get(startUrl("google", pk)), world.env());
    expect(res.status).toBe(302);
    const loc = res.headers.get("Location")!;
    expect(loc).not.toContain("+");
    const url = new URL(loc);
    expect(url.origin + url.pathname).toBe("https://accounts.google.com/o/oauth2/v2/auth");
    const q = Object.fromEntries(url.searchParams);
    expect(q).toMatchObject({
      client_id: world.secrets.GOOGLE_CLIENT_ID,
      redirect_uri: `${BASE}/v1/auth/google/callback`,
      response_type: "code",
      scope: "openid email profile",
      prompt: "select_account",
      access_type: "online",
      code_challenge_method: "S256",
    });
    expect(q.state).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(q.nonce).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(q.code_challenge).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(q.code_challenge).not.toBe(pk.challenge); // the provider PKCE is the Worker's own
    const flow = await db().prepare("SELECT * FROM auth_flows WHERE id = ?1").bind(q.state).first<Record<string, unknown>>();
    expect(flow).toMatchObject({ provider: "google", nonce: q.nonce, app_code_challenge: pk.challenge, app_state: pk.state, app_redirect_uri: APP_REDIRECT });
    expect(flow!.expires_at).toBe(deps.now() + 600_000);
  });

  it("Microsoft uses /common with response_mode=query; Apple uses form_post without PKCE", async () => {
    let url = new URL((await call(deps, get(startUrl("microsoft", await appPkce())), world.env())).headers.get("Location")!);
    expect(url.origin + url.pathname).toBe("https://login.microsoftonline.com/common/oauth2/v2.0/authorize");
    expect(url.searchParams.get("response_mode")).toBe("query");
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    url = new URL((await call(deps, get(startUrl("apple", await appPkce())), world.env())).headers.get("Location")!);
    expect(url.origin + url.pathname).toBe("https://appleid.apple.com/auth/authorize");
    expect(url.searchParams.get("response_mode")).toBe("form_post");
    expect(url.searchParams.get("scope")).toBe("name email");
    expect(url.searchParams.get("code_challenge")).toBeNull();
    const flow = await db().prepare("SELECT provider_code_verifier FROM auth_flows WHERE id = ?1").bind(url.searchParams.get("state")).first();
    expect(flow).toEqual({ provider_code_verifier: null });
  });

  it("uses PUBLIC_BASE_URL for the provider redirect URI when set", async () => {
    const res = await call(deps, get(startUrl("google", await appPkce())), world.env({ PUBLIC_BASE_URL: "https://api.example.at/" }));
    expect(new URL(res.headers.get("Location")!).searchParams.get("redirect_uri")).toBe("https://api.example.at/v1/auth/google/callback");
  });

  it("answers 400 HTML without a valid redirect_uri or state", async () => {
    const pk = await appPkce();
    const overrides: Record<string, string>[] = [
      { redirect_uri: "https://evil.test/cb" },
      { redirect_uri: "klimabilanz://other" },
      { state: "short" },
      { state: "bad state with spaces!" },
    ];
    for (const over of overrides) {
      const res = await call(deps, get(startUrl("google", pk, over)), world.env());
      expect(res.status).toBe(400);
      expect(res.headers.get("Content-Type")).toContain("text/html");
      expect(res.headers.get("Content-Security-Policy")).toContain("default-src 'none'");
      expect(res.headers.get("Location")).toBeNull();
    }
  });

  it("sends other errors back to the app (invalid_request, provider_disabled, server_error)", async () => {
    const pk = await appPkce();
    const expectAppError = (res: Response, code: string) => {
      expect(res.status).toBe(302);
      const url = new URL(res.headers.get("Location")!);
      expect(url.protocol).toBe("klimabilanz:");
      expect(url.searchParams.get("error")).toBe(code);
      expect(url.searchParams.get("state")).toBe(pk.state);
      expect(url.searchParams.get("error_description")).toBeTruthy();
    };
    expectAppError(await call(deps, get(startUrl("google", pk, { code_challenge_method: "plain" })), world.env()), "invalid_request");
    expectAppError(await call(deps, get(startUrl("google", pk, { code_challenge: "too-short" })), world.env()), "invalid_request");
    expectAppError(await call(deps, get(startUrl("google", pk)), { GOOGLE_CLIENT_ID: undefined }), "provider_disabled");
    expectAppError(await call(deps, get(startUrl("apple", pk)), world.env({ APPLE_PRIVATE_KEY: "broken" })), "provider_disabled");
    expectAppError(await call(deps, get(startUrl("google", pk)), world.env({ SESSION_SIGNING_KEY: undefined })), "server_error");
  });

  it("allows an Origin header (browser navigation)", async () => {
    const res = await call(deps, get(startUrl("google", await appPkce()), { Origin: "null" }), world.env());
    expect(res.status).toBe(302);
  });
});

describe("full sign-in", () => {
  it("Google: PKCE happy path issues a session and the documented token response", async () => {
    const { tokens, sub } = await signInWeb(world, deps, "google");
    expect(tokens).toMatchObject({ token_type: "Bearer", expires_in: 900, refresh_token_expires_in: 5184000 });
    expect(tokens.refresh_token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(tokens.user).toEqual({
      id: expect.stringMatching(/^[0-9a-f-]{36}$/),
      email: `${sub}@gmail.test`,
      email_verified: true,
      display_name: "Grete Google",
      avatar_url: "https://lh3.googleusercontent.test/a/photo",
      provider: "google",
      created_at: "2026-10-09T12:00:00.000000Z",
    });
    const jwt = decodeJwt(tokens.access_token)!;
    expect(jwt.header).toMatchObject({ alg: "HS256", typ: "JWT" });
    expect(jwt.payload).toMatchObject({ iss: "klimabilanz-api", aud: "klimabilanz-ios", sub: tokens.user.id, v: 1 });
    expect((jwt.payload.exp as number) - (jwt.payload.iat as number)).toBe(900);
    const me = await call(deps, get("/v1/me", bearer(tokens.access_token)), world.env());
    expect(me.status).toBe(200);
    expect(((await me.json()) as { user: { id: string } }).user.id).toBe(tokens.user.id);
    // Only hashes are stored.
    expect(await count("SELECT COUNT(*) AS n FROM refresh_tokens WHERE token_hash = ?1", tokens.refresh_token)).toBe(0);
  });

  it("Microsoft: issuer from the token's tenant; e-mail unverified unless xms_edov", async () => {
    const { tokens, sub } = await signInWeb(world, deps, "microsoft");
    expect(tokens.user).toMatchObject({ provider: "microsoft", email: `${sub}@outlook.test`, email_verified: false, display_name: "Mia Microsoft" });
    const verified = await signInWeb(world, deps, "microsoft", { mutation: { claims: { xms_edov: true } } });
    expect(verified.tokens.user.email_verified).toBe(true);
    const workTenant = "72f988bf-86f1-41af-91ab-2d7cd011db47";
    const work = await signInWeb(world, deps, "microsoft", {
      mutation: { claims: { tid: workTenant, iss: `https://login.microsoftonline.com/${workTenant}/v2.0`, email: undefined } },
    });
    expect(work.tokens.user.email).toBe(`${work.sub}@outlook.test`); // preferred_username, display only
    expect(work.tokens.user.email_verified).toBe(false);
  });

  it("Microsoft: rejects an issuer that does not match tid, and a non-GUID tid", async () => {
    for (const claims of [
      { tid: "72f988bf-86f1-41af-91ab-2d7cd011db47" },
      { tid: "common", iss: "https://login.microsoftonline.com/common/v2.0" },
      { iss: `https://sts.windows.net/${MS_TENANT}/` },
    ]) {
      const { app } = await toCallback("microsoft", { claims });
      expect(app!.searchParams.get("error")).toBe("invalid_id_token");
    }
  });

  it("Apple web: form_post callback with the user name, ES256 client secret, sealed refresh token", async () => {
    const user = JSON.stringify({ name: { firstName: "Anna", lastName: "Äpfel" }, email: "ignored@example.test" });
    const { tokens, sub } = await signInWeb(world, deps, "apple", { appleUser: user });
    expect(tokens.user).toMatchObject({ provider: "apple", email: `${sub}@privaterelay.appleid.test`, email_verified: true, display_name: "Anna Äpfel" });
    const identity = await db()
      .prepare("SELECT provider_refresh_token FROM identities WHERE provider = 'apple' AND subject = ?1")
      .bind(sub)
      .first<{ provider_refresh_token: string }>();
    expect(identity!.provider_refresh_token).toMatch(/^[A-Za-z0-9_-]{60,}$/);
    expect(identity!.provider_refresh_token).not.toContain("apple-refresh");
  });

  it("Apple callback: the 303 page links back to the app and carries the CSP", async () => {
    const { res, app } = await toCallback("apple");
    expect(res.status).toBe(303);
    expect(app!.searchParams.get("code")).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(res.headers.get("Content-Security-Policy")).toContain("frame-ancestors 'none'");
    const html = await res.text();
    expect(html).toContain("Zurück zur App");
    expect(html).toContain(`href="klimabilanz://auth-callback?code=`);
  });

  it("Apple callback: rejects foreign origins and non-form bodies; accepts Origin null / appleid", async () => {
    const pk = await appPkce();
    let res = await call(deps, postForm("/v1/auth/apple/callback", { state: "x" }, { Origin: "https://evil.test" }), world.env());
    expect(res.status).toBe(403);
    res = await call(
      deps,
      new Request(`${BASE}/v1/auth/apple/callback`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" }),
      world.env(),
    );
    expect(res.status).toBe(415);
    for (const origin of ["null", "https://appleid.apple.com"]) {
      const start = await call(deps, get(startUrl("apple", pk)), world.env());
      const { code, state } = world.authorize(start.headers.get("Location")!, unique("sub"));
      res = await call(deps, postForm("/v1/auth/apple/callback", { code, state }, { Origin: origin }), world.env());
      expect(res.status).toBe(303);
    }
  });

  it("existing identity: same user, profile only filled where empty, login timestamps updated", async () => {
    const sub = unique("sub");
    const first = await signInWeb(world, deps, "google", { sub, mutation: { claims: { name: undefined } } });
    expect(first.tokens.user.display_name).toBeNull();
    deps.clock.advance(60_000);
    const second = await signInWeb(world, deps, "google", { sub, mutation: { claims: { name: "Neu", email: `${sub}@new.test` } } });
    expect(second.tokens.user.id).toBe(first.tokens.user.id);
    expect(second.tokens.user.display_name).toBe("Neu");
    expect(second.tokens.user.email).toBe(`${sub}@new.test`);
    const third = await signInWeb(world, deps, "google", { sub, mutation: { claims: { name: "Anders" } } });
    expect(third.tokens.user.display_name).toBe("Neu");
    const u = await db().prepare("SELECT created_at, last_login_at FROM users WHERE id = ?1").bind(first.tokens.user.id).first<{ created_at: number; last_login_at: number }>();
    expect(u!.last_login_at).toBeGreaterThan(u!.created_at);
  });

  it("never merges accounts by e-mail", async () => {
    const email = `${unique("same")}@example.test`;
    const g = await signInWeb(world, deps, "google", { mutation: { claims: { email } } });
    const m = await signInWeb(world, deps, "microsoft", { mutation: { claims: { email, xms_edov: true } } });
    expect(g.tokens.user.id).not.toBe(m.tokens.user.id);
    expect(g.tokens.user.email).toBe(email);
    expect(m.tokens.user.email).toBe(email);
  });
});

describe("callback errors", () => {
  it("state replay: a flow is consumed exactly once", async () => {
    const pk = await appPkce();
    const start = await call(deps, get(startUrl("google", pk)), world.env());
    const { code, state } = world.authorize(start.headers.get("Location")!, unique("sub"));
    const first = await call(deps, callbackRequest("google", { code, state }), world.env());
    expect(first.status).toBe(302);
    const replay = await call(deps, callbackRequest("google", { code, state }), world.env());
    expect(replay.status).toBe(400);
    expect(replay.headers.get("Location")).toBeNull();
    expect(await replay.text()).toContain("Die Anmeldung ist abgelaufen");
  });

  it("expired flows, unknown state and a provider mismatch get the HTML page", async () => {
    const pk = await appPkce();
    const start = await call(deps, get(startUrl("google", pk)), world.env());
    const { code, state } = world.authorize(start.headers.get("Location")!, unique("sub"));
    deps.clock.advance(600_001);
    try {
      expect((await call(deps, callbackRequest("google", { code, state }), world.env())).status).toBe(400);
    } finally {
      deps.clock.advance(-600_001);
    }
    expect((await call(deps, callbackRequest("google", { code, state: "A".repeat(43) }), world.env())).status).toBe(400);
    expect((await call(deps, callbackRequest("google", { code }), world.env())).status).toBe(400);
    const msStart = await call(deps, get(startUrl("microsoft", pk)), world.env());
    const ms = world.authorize(msStart.headers.get("Location")!, unique("sub"));
    expect((await call(deps, callbackRequest("google", { code: ms.code, state: ms.state }), world.env())).status).toBe(400);
  });

  it("provider errors: cancel → access_denied, others → sanitized provider_error", async () => {
    for (const [p, error] of [
      ["google", "access_denied"],
      ["apple", "user_cancelled_authorize"],
    ] as const) {
      const pk = await appPkce();
      const start = await call(deps, get(startUrl(p, pk)), world.env());
      const state = new URL(start.headers.get("Location")!).searchParams.get("state")!;
      const res = await call(deps, callbackRequest(p, { state, error }), world.env());
      const app = new URL(res.headers.get("Location")!);
      expect(app.searchParams.get("error")).toBe("access_denied");
      expect(app.searchParams.get("state")).toBe(pk.state);
      expect(app.searchParams.get("error_description")).toBeNull();
    }
    const pk = await appPkce();
    const start = await call(deps, get(startUrl("microsoft", pk)), world.env());
    const state = new URL(start.headers.get("Location")!).searchParams.get("state")!;
    const res = await call(
      deps,
      callbackRequest("microsoft", { state, error: "server_error", error_description: `AADSTS50020:\u0007 ${"x".repeat(300)}` }),
      world.env(),
    );
    const app = new URL(res.headers.get("Location")!);
    expect(app.searchParams.get("error")).toBe("provider_error");
    const description = app.searchParams.get("error_description")!;
    expect(description.length).toBeLessThanOrEqual(200);
    expect(description).not.toMatch(/[\u0000-\u001f]/);
  });

  it("token endpoint failures → provider_error", async () => {
    expect((await toCallback("google", { tokenStatus: 500 })).app!.searchParams.get("error")).toBe("provider_error");
    expect((await toCallback("google", { omitIdToken: true })).app!.searchParams.get("error")).toBe("provider_error");
  });

  it("rejects id_tokens with a wrong nonce, iss, aud, alg, kid, signature or times", async () => {
    const stranger = await FakeIdp.create(world.google.kid); // same kid, different key
    const unknownKid = await FakeIdp.create();
    const now = Math.floor(deps.now() / 1000);
    const cases: [string, TokenMutation][] = [
      ["nonce", { claims: { nonce: "wrong-nonce" } }],
      ["no nonce", { claims: { nonce: undefined } }],
      ["iss", { claims: { iss: "https://evil.test" } }],
      ["aud", { claims: { aud: "someone-else" } }],
      ["aud array without azp", { claims: { aud: [world.secrets.GOOGLE_CLIENT_ID, "other"], azp: "other" } }],
      ["alg none", { header: { alg: "none" } }],
      ["alg HS256", { header: { alg: "HS256" } }],
      ["missing kid", { header: { kid: undefined } }],
      ["unknown kid", { signWith: unknownKid }],
      ["bad signature", { signWith: stranger }],
      ["expired", { claims: { exp: now - 61 } }],
      ["iat in the future", { claims: { iat: now + 120 } }],
      ["iat too old", { claims: { iat: now - 601, exp: now + 3600 } }],
      ["nbf in the future", { claims: { nbf: now + 120 } }],
      ["empty sub", { claims: { sub: "" } }],
      ["long sub", { claims: { sub: "s".repeat(256) } }],
      ["crit header", { header: { crit: ["exp"] } }],
      ["garbage", { raw: "not.a.jwt" }],
    ];
    for (const [name, mutation] of cases) {
      const { app } = await toCallback("google", mutation);
      expect(app!.searchParams.get("error"), name).toBe("invalid_id_token");
    }
    // Accepted edge cases: aud array with a matching azp, exp within the 60 s leeway, string iss without https.
    for (const claims of [
      { aud: [world.secrets.GOOGLE_CLIENT_ID, "other"], azp: world.secrets.GOOGLE_CLIENT_ID },
      { aud: [world.secrets.GOOGLE_CLIENT_ID] },
      { exp: now - 30 },
      { iss: "accounts.google.com" },
    ]) {
      const { app } = await toCallback("google", { claims });
      expect(app!.searchParams.get("error"), JSON.stringify(claims)).toBeNull();
    }
    // The log says why, without the token.
    const reasons = deps.logs.filter((l) => l.event === "id_token_rejected").map((l) => l.reason);
    expect(reasons).toEqual(expect.arrayContaining(["nonce", "iss", "aud", "azp", "alg", "kid", "signature", "exp", "iat", "nbf", "sub", "crit", "malformed"]));
  });

  it("refetches the JWKS at most once per minute for an unknown kid", async () => {
    const d = world.freshDeps();
    const unknown = await FakeIdp.create();
    const jwksCalls = () => d.net.callsTo("https://www.googleapis.com/oauth2/v3/certs").length;
    const before = jwksCalls();
    const run = async (m: TokenMutation = {}) => {
      const pk = await appPkce();
      const start = await call(d, get(startUrl("google", pk)), world.env());
      const { code, state } = world.authorize(start.headers.get("Location")!, unique("sub"), m);
      const res = await call(d, callbackRequest("google", { code, state }), world.env());
      return new URL(res.headers.get("Location")!).searchParams.get("error");
    };
    expect(await run()).toBeNull();
    expect(jwksCalls() - before).toBe(1);
    expect(await run()).toBeNull();
    expect(jwksCalls() - before).toBe(1); // cached
    expect(await run({ signWith: unknown })).toBe("invalid_id_token");
    expect(await run({ signWith: unknown })).toBe("invalid_id_token");
    expect(jwksCalls() - before).toBe(1); // within 60 s of the last fetch
    d.clock.advance(61_000);
    expect(await run({ signWith: unknown })).toBe("invalid_id_token");
    expect(jwksCalls() - before).toBe(2);
    d.clock.advance(-61_000);
  });

  it("JWKS unavailable → provider_error", async () => {
    const d = world.freshDeps();
    const saved = d.net.handlers.get("https://www.googleapis.com/oauth2/v3/certs")!;
    d.net.on("https://www.googleapis.com/oauth2/v3/certs", () => new Response("down", { status: 503 }));
    try {
      const pk = await appPkce();
      const start = await call(d, get(startUrl("google", pk)), world.env());
      const { code, state } = world.authorize(start.headers.get("Location")!, unique("sub"));
      const res = await call(d, callbackRequest("google", { code, state }), world.env());
      expect(new URL(res.headers.get("Location")!).searchParams.get("error")).toBe("provider_error");
    } finally {
      d.net.on("https://www.googleapis.com/oauth2/v3/certs", saved);
    }
  });
});

describe("POST /v1/auth/token (authorization_code)", () => {
  it("PKCE mismatch → invalid_grant and the code is consumed", async () => {
    const { app, pk } = await toCallback("google");
    const code = app!.searchParams.get("code")!;
    const wrong = await appPkce();
    await expectError(await call(deps, tokenRequest(code, wrong.verifier), world.env()), 400, "invalid_grant");
    await expectError(await call(deps, tokenRequest(code, pk.verifier), world.env()), 400, "invalid_grant");
  });

  it("redirect_uri mismatch → invalid_grant", async () => {
    const { app, pk } = await toCallback("google");
    const code = app!.searchParams.get("code")!;
    await expectError(await call(deps, tokenRequest(code, pk.verifier, "klimabilanz://other")), 400, "invalid_grant");
  });

  it("code reuse revokes the session it created", async () => {
    const { app, pk } = await toCallback("google");
    const code = app!.searchParams.get("code")!;
    const ok = await call(deps, tokenRequest(code, pk.verifier), world.env());
    expect(ok.status).toBe(200);
    const tokens = (await ok.json()) as { access_token: string; refresh_token: string };
    expect((await call(deps, get("/v1/me", bearer(tokens.access_token)))).status).toBe(200);
    await expectError(await call(deps, tokenRequest(code, pk.verifier), world.env()), 400, "invalid_grant");
    await expectError(await call(deps, get("/v1/me", bearer(tokens.access_token))), 401, "invalid_token");
    await expectError(
      await call(deps, postForm("/v1/auth/token", { grant_type: "refresh_token", refresh_token: tokens.refresh_token })),
      400,
      "invalid_grant",
    );
    const sid = decodeJwt(tokens.access_token)!.payload.sid;
    const s = await db().prepare("SELECT revoked_reason FROM sessions WHERE id = ?1").bind(sid).first();
    expect(s).toEqual({ revoked_reason: "code_reuse" });
  });

  it("two concurrent redemptions of one code: exactly one session, and it is revoked as code reuse", async () => {
    const { app, pk } = await toCallback("google");
    const code = app!.searchParams.get("code")!;
    const results = await Promise.all([call(deps, tokenRequest(code, pk.verifier)), call(deps, tokenRequest(code, pk.verifier))]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 400]);
    const winner = (await results.find((r) => r.status === 200)!.json()) as { access_token: string };
    const sid = decodeJwt(winner.access_token)!.payload.sid;
    const codeRow = await db().prepare("SELECT session_id FROM auth_codes WHERE session_id = ?1").bind(sid).first();
    expect(codeRow).toEqual({ session_id: sid });
    expect(await db().prepare("SELECT revoked_reason FROM sessions WHERE id = ?1").bind(sid).first()).toEqual({ revoked_reason: "code_reuse" });
  });

  it("an expired code → invalid_grant", async () => {
    const { app, pk } = await toCallback("google");
    deps.clock.advance(120_001);
    try {
      await expectError(await call(deps, tokenRequest(app!.searchParams.get("code")!, pk.verifier)), 400, "invalid_grant");
    } finally {
      deps.clock.advance(-120_001);
    }
  });

  it("accepts JSON bodies too; validates parameters", async () => {
    const { app, pk } = await toCallback("microsoft");
    const res = await call(
      deps,
      new Request(`${BASE}/v1/auth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify({ grant_type: "authorization_code", code: app!.searchParams.get("code"), code_verifier: pk.verifier, redirect_uri: APP_REDIRECT }),
      }),
    );
    expect(res.status).toBe(200);
    await expectError(await call(deps, postForm("/v1/auth/token", { grant_type: "authorization_code" })), 400, "invalid_request");
    await expectError(
      await call(deps, postForm("/v1/auth/token", { grant_type: "authorization_code", code: "x", code_verifier: "short", redirect_uri: APP_REDIRECT })),
      400,
      "invalid_request",
    );
    await expectError(
      await call(deps, postForm("/v1/auth/token", { grant_type: "authorization_code", code: "unknown", code_verifier: pk.verifier, redirect_uri: APP_REDIRECT })),
      400,
      "invalid_grant",
    );
    await expectError(await call(deps, postForm("/v1/auth/token", { grant_type: "password" })), 400, "unsupported_grant_type");
    await expectError(await call(deps, postForm("/v1/auth/token", {})), 400, "invalid_request");
  });

  it("logs never contain codes, tokens, verifiers or e-mails", async () => {
    const d = world.freshDeps();
    const { tokens, appCode, pkce, sub } = await signInWeb(world, d, "google");
    const logs = JSON.stringify(d.logs);
    for (const secret of [tokens.access_token, tokens.refresh_token, appCode, pkce.verifier, `${sub}@gmail.test`, world.secrets.GOOGLE_CLIENT_SECRET]) {
      expect(logs).not.toContain(secret);
    }
    expect(d.logs.some((l) => l.route === "auth_token" && l.status === 200)).toBe(true);
  });
});
