// Refresh rotation, grace window, reuse detection, expiry, logout scope, native Sign in with Apple
// (docs/CLOUDFLARE_BACKEND.md §2.4, §2.7).
import { beforeAll, describe, expect, it } from "vitest";
import { decodeJwt, sha256Hex } from "../src/crypto";
import type { TokenResponse } from "../src/sessions";
import {
  ProviderWorld,
  TestCtx,
  bearer,
  call,
  count,
  db,
  directSession,
  expectError,
  get,
  hashToken,
  postForm,
  postJson,
  signInNative,
  signInWeb,
  unique,
  type TestDeps,
} from "./helpers";

let world: ProviderWorld;
let deps: TestDeps;

beforeAll(async () => {
  world = await ProviderWorld.create();
  deps = world.deps;
});

function refresh(token: string): Request {
  return postForm("/v1/auth/token", { grant_type: "refresh_token", refresh_token: token });
}

async function refreshOk(token: string): Promise<TokenResponse> {
  const res = await call(deps, refresh(token));
  expect(res.status).toBe(200);
  return (await res.json()) as TokenResponse;
}

async function me(accessToken: string): Promise<number> {
  return (await call(deps, get("/v1/me", bearer(accessToken)))).status;
}

async function sessionRow(accessToken: string) {
  const sid = decodeJwt(accessToken)!.payload.sid as string;
  return db().prepare("SELECT * FROM sessions WHERE id = ?1").bind(sid).first<Record<string, unknown>>();
}

describe("refresh token rotation", () => {
  it("rotates: new pair works, session slides, old token is marked used", async () => {
    const s = await directSession(deps);
    deps.clock.advance(10 * 60_000);
    const next = await refreshOk(s.refreshToken);
    expect(next.refresh_token).not.toBe(s.refreshToken);
    expect(next.user.id).toBe(s.userId);
    expect(await me(next.access_token)).toBe(200);
    const old = await db().prepare("SELECT used_at, replaced_by FROM refresh_tokens WHERE token_hash = ?1").bind(await hashToken(s.refreshToken)).first();
    expect(old).toEqual({ used_at: deps.now(), replaced_by: await hashToken(next.refresh_token) });
    const row = await sessionRow(next.access_token);
    expect(row!.expires_at).toBe(deps.now() + 60 * 86_400_000);
    expect(row!.last_refreshed_at).toBe(deps.now());
    // The successor rotates again.
    const third = await refreshOk(next.refresh_token);
    expect(await me(third.access_token)).toBe(200);
  });

  it("grace window: a retried refresh within 60 s gets a fresh successor and revokes the lost one", async () => {
    const s = await directSession(deps);
    const lost = await refreshOk(s.refreshToken); // response "lost"
    deps.clock.advance(30_000);
    const retry = await refreshOk(s.refreshToken);
    expect(retry.refresh_token).not.toBe(lost.refresh_token);
    expect(await me(retry.access_token)).toBe(200);
    const lostRow = await db().prepare("SELECT revoked_at FROM refresh_tokens WHERE token_hash = ?1").bind(await hashToken(lost.refresh_token)).first();
    expect(lostRow).toEqual({ revoked_at: deps.now() });
    // The client continues with the reissued token.
    const later = await refreshOk(retry.refresh_token);
    expect(await me(later.access_token)).toBe(200);
  });

  it("a token revoked by a grace reissue that comes back later revokes the family", async () => {
    const s = await directSession(deps);
    const lost = await refreshOk(s.refreshToken);
    const retry = await refreshOk(s.refreshToken);
    await expectError(await call(deps, refresh(lost.refresh_token)), 400, "invalid_grant");
    expect(await me(retry.access_token)).toBe(401);
    expect((await sessionRow(retry.access_token))!.revoked_reason).toBe("refresh_reuse");
  });

  it("reuse after the grace window revokes the whole session", async () => {
    const s = await directSession(deps);
    const next = await refreshOk(s.refreshToken);
    deps.clock.advance(61_000);
    await expectError(await call(deps, refresh(s.refreshToken)), 400, "invalid_grant");
    expect(await me(next.access_token)).toBe(401);
    await expectError(await call(deps, refresh(next.refresh_token)), 400, "invalid_grant");
    expect((await sessionRow(next.access_token))!.revoked_reason).toBe("refresh_reuse");
  });

  it("reuse when the successor was already used revokes the session (even inside 60 s)", async () => {
    const s = await directSession(deps);
    const a = await refreshOk(s.refreshToken);
    const b = await refreshOk(a.refresh_token);
    await expectError(await call(deps, refresh(s.refreshToken)), 400, "invalid_grant");
    expect(await me(b.access_token)).toBe(401);
  });

  it("two concurrent refreshes with one token both succeed; only the later successor stays valid", async () => {
    const s = await directSession(deps);
    const results = await Promise.all([call(deps, refresh(s.refreshToken)), call(deps, refresh(s.refreshToken))]);
    expect(results.map((r) => r.status)).toEqual([200, 200]);
    const tokens = (await Promise.all(results.map((r) => r.json()))) as TokenResponse[];
    const states = await Promise.all(
      tokens.map(async (t) =>
        db().prepare("SELECT revoked_at FROM refresh_tokens WHERE token_hash = ?1").bind(await hashToken(t.refresh_token)).first<{ revoked_at: number | null }>(),
      ),
    );
    expect(states.filter((r) => r!.revoked_at === null).length).toBe(1);
    expect(await count("SELECT COUNT(*) AS n FROM sessions WHERE id = ?1 AND revoked_at IS NULL", s.sessionId)).toBe(1);
  });

  it("expired sessions and tokens → invalid_grant; the session slides on every refresh", async () => {
    const s = await directSession(deps);
    deps.clock.advance(59 * 86_400_000);
    const next = await refreshOk(s.refreshToken); // slides to now + 60 d
    deps.clock.advance(59 * 86_400_000);
    const again = await refreshOk(next.refresh_token);
    expect(await me(again.access_token)).toBe(200);
    deps.clock.advance(60 * 86_400_000 + 1);
    await expectError(await call(deps, refresh(again.refresh_token)), 400, "invalid_grant");
  });

  it("access tokens expire after 15 minutes (refresh still works)", async () => {
    const s = await directSession(deps);
    deps.clock.advance(15 * 60_000);
    expect(await me(s.accessToken)).toBe(401);
    const next = await refreshOk(s.refreshToken);
    expect(await me(next.access_token)).toBe(200);
  });

  it("unknown or malformed refresh tokens → invalid_grant; missing → invalid_request", async () => {
    await expectError(await call(deps, refresh("A".repeat(43))), 400, "invalid_grant");
    await expectError(await call(deps, refresh("short")), 400, "invalid_grant");
    await expectError(await call(deps, postForm("/v1/auth/token", { grant_type: "refresh_token" })), 400, "invalid_request");
  });

  it("access tokens of a revoked session die immediately", async () => {
    const s = await directSession(deps);
    expect(await me(s.accessToken)).toBe(200);
    await db().prepare("UPDATE sessions SET revoked_at = ?2 WHERE id = ?1").bind(s.sessionId, deps.now()).run();
    expect(await me(s.accessToken)).toBe(401);
  });

  it("rejects tampered access tokens and wrong schemes", async () => {
    const s = await directSession(deps);
    const [h, p] = s.accessToken.split(".");
    expect(await me(`${h}.${p}.AAAA`)).toBe(401);
    expect((await call(deps, get("/v1/me", { Authorization: `Basic ${s.accessToken}` }))).status).toBe(401);
    expect((await call(deps, get("/v1/me", { Authorization: `bearer ${s.accessToken}` }))).status).toBe(200);
  });
});

describe("logout", () => {
  it("revokes only this device's session (refresh token)", async () => {
    const sub = unique("sub");
    const phone = await signInWeb(world, deps, "google", { sub });
    const tablet = await signInWeb(world, deps, "google", { sub });
    expect(phone.tokens.user.id).toBe(tablet.tokens.user.id);
    const res = await call(deps, postForm("/v1/auth/logout", { refresh_token: phone.tokens.refresh_token }));
    expect(res.status).toBe(204);
    expect(res.headers.get("X-KB-API")).toBe("1");
    expect(await me(phone.tokens.access_token)).toBe(401);
    await expectError(await call(deps, refresh(phone.tokens.refresh_token)), 400, "invalid_grant");
    expect(await me(tablet.tokens.access_token)).toBe(200);
    expect((await sessionRow(phone.tokens.access_token))!.revoked_reason).toBe("logout");
  });

  it("accepts a bearer token, even an expired one with a valid signature", async () => {
    const s = await directSession(deps);
    deps.clock.advance(16 * 60_000);
    const res = await call(deps, new Request("https://api.test/v1/auth/logout", { method: "POST", headers: bearer(s.accessToken) }));
    expect(res.status).toBe(204);
    await expectError(await call(deps, refresh(s.refreshToken)), 400, "invalid_grant");
  });

  it("answers 204 for unknown tokens, JSON bodies and empty bodies", async () => {
    expect((await call(deps, postForm("/v1/auth/logout", { refresh_token: "A".repeat(43) }))).status).toBe(204);
    expect((await call(deps, postJson("/v1/auth/logout", { refresh_token: "nope" }))).status).toBe(204);
    expect((await call(deps, new Request("https://api.test/v1/auth/logout", { method: "POST" }))).status).toBe(204);
    expect((await call(deps, postJson("/v1/auth/logout", "", bearer("x.y.z")))).status).toBe(204);
  });
});

describe("native Sign in with Apple", () => {
  it("signs in with nonce = SHA-256(raw_nonce), aud = bundle id; stores the first-login name", async () => {
    const { res, sub } = await signInNative(world, deps, { fullName: "  Nina Native " });
    expect(res.status).toBe(200);
    const tokens = (await res.json()) as TokenResponse;
    expect(tokens.user).toMatchObject({ provider: "apple", display_name: "Nina Native", email_verified: true, email: `${sub}@privaterelay.appleid.test` });
    expect(await me(tokens.access_token)).toBe(200);
    // Same Apple subject on the web → same account.
    const web = await signInWeb(world, deps, "apple", { sub });
    expect(web.tokens.user.id).toBe(tokens.user.id);
  });

  it("rejects a wrong nonce, the services id as audience, and replays", async () => {
    const sub = unique("asub");
    let r = await signInNative(world, deps, { sub, mutation: { claims: { nonce: "f".repeat(64) } } });
    await expectError(r.res, 400, "invalid_grant");
    r = await signInNative(world, deps, { sub, mutation: { claims: { aud: world.secrets.APPLE_SERVICES_ID } } });
    await expectError(r.res, 400, "invalid_grant");
    r = await signInNative(world, deps, { sub, mutation: { claims: { iss: "https://appleid.apple.com/" } } });
    await expectError(r.res, 400, "invalid_grant");

    // Replay: the very same identity token + raw nonce a second time.
    const ok = await signInNative(world, deps, { sub });
    expect(ok.res.status).toBe(200);
    const rawNonce = ok.rawNonce;
    const replayToken = await world.idToken("apple", sub, await sha256Hex(rawNonce), {}, world.secrets.APPLE_BUNDLE_ID);
    const replay = await call(deps, postJson("/v1/auth/apple/native", { identity_token: replayToken, raw_nonce: rawNonce }), world.env());
    await expectError(replay, 400, "invalid_grant");
    expect(await count("SELECT COUNT(*) AS n FROM apple_native_nonces WHERE nonce_hash = ?1", await sha256Hex(rawNonce))).toBe(1);
  });

  it("validates the body and is disabled without APPLE_BUNDLE_ID", async () => {
    await expectError(await call(deps, postJson("/v1/auth/apple/native", { raw_nonce: "x" }), world.env()), 400, "invalid_request");
    await expectError(await call(deps, postJson("/v1/auth/apple/native", { identity_token: "a.b.c" }), world.env()), 400, "invalid_request");
    await expectError(
      await call(deps, postJson("/v1/auth/apple/native", { identity_token: "a.b.c", raw_nonce: "n", full_name: 5 }), world.env()),
      400,
      "invalid_request",
    );
    await expectError(await call(deps, postJson("/v1/auth/apple/native", { identity_token: "a.b.c", raw_nonce: "n" }), world.env()), 400, "invalid_grant");
    await expectError(
      await call(deps, postJson("/v1/auth/apple/native", { identity_token: "a.b.c", raw_nonce: "n" }), world.env({ APPLE_BUNDLE_ID: undefined })),
      404,
      "provider_disabled",
    );
  });

  it("exchanges the authorization code in waitUntil and seals the Apple refresh token", async () => {
    const code = unique("native-code");
    world.nativeCodes.set(code, "apple-native-refresh-token");
    const ctx = new TestCtx();
    const { res, sub } = await signInNative(world, deps, { authorizationCode: code, ctx });
    expect(res.status).toBe(200);
    await ctx.drain();
    const row = await db()
      .prepare("SELECT provider_refresh_token FROM identities WHERE provider = 'apple' AND subject = ?1")
      .bind(sub)
      .first<{ provider_refresh_token: string | null }>();
    expect(row!.provider_refresh_token).toBeTruthy();
    expect(row!.provider_refresh_token).not.toContain("apple-native");
    // A failing exchange never fails the sign-in.
    const ctx2 = new TestCtx();
    const second = await signInNative(world, deps, { authorizationCode: "unknown-code", ctx: ctx2 });
    expect(second.res.status).toBe(200);
    await ctx2.drain();
  });
});
