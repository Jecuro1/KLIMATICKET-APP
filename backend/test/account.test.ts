// /v1/me, PATCH /v1/me, POST /v1/account/delete (docs/CLOUDFLARE_BACKEND.md §3.2, §3.9, §2.9).
import { beforeAll, describe, expect, it } from "vitest";
import { decodeJwt } from "../src/crypto";
import type { TokenResponse } from "../src/sessions";
import {
  APP_REDIRECT,
  ProviderWorld,
  TestCtx,
  appPkce,
  bearer,
  call,
  count,
  db,
  directSession,
  expectError,
  get,
  postForm,
  postJson,
  signInWeb,
  startUrl,
  unique,
  uuid,
  type TestDeps,
} from "./helpers";

let world: ProviderWorld;
let deps: TestDeps;

beforeAll(async () => {
  world = await ProviderWorld.create();
  deps = world.deps;
});

const DATA_TABLES = ["tickets", "trips", "favorite_routes", "benefits"] as const;

function sampleRows(): Record<(typeof DATA_TABLES)[number], Record<string, unknown>> {
  const t = "2026-10-01T00:00:00.000000Z";
  return {
    tickets: {
      id: uuid(), product_id: "p", name: "n", variant: "klassik", family: "oe", states: "", price: 1, start_date: t, end_date: t,
      holder_name: "", ticket_number: "", theme: "twilight", reminders: "", created_at: t, updated_at: t,
    },
    trips: {
      id: uuid(), date: t, from_name: "a", to_name: "b", mode: "train", distance_km: 1, fare_eur: 1, is_fare_manual: false,
      is_round_trip: false, travel_class: "second", companions: 0, states: "", note: "", created_at: t, updated_at: t,
    },
    favorite_routes: {
      id: uuid(), title: "", from_name: "a", to_name: "b", mode: "train", distance_km: 1, fare_eur: 1, is_round_trip: false,
      states: "", sort_index: 0, usage_count: 0, created_at: t, updated_at: t,
    },
    benefits: { id: uuid(), date: t, partner_id: "custom", title: "t", saved_eur: 1, note: "", created_at: t, updated_at: t },
  };
}

describe("GET/PATCH /v1/me", () => {
  it("returns the user of the current session and the linked identities", async () => {
    const { tokens, sub } = await signInWeb(world, deps, "google");
    const res = await call(deps, get("/v1/me", bearer(tokens.access_token)));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ user: tokens.user, identities: [{ provider: "google", email: `${sub}@gmail.test` }] });
  });

  it("updates, trims and clears display_name; validates input", async () => {
    const s = await directSession(deps);
    const patch = (body: unknown) => call(deps, postJson("/v1/me", body, bearer(s.accessToken), "PATCH"));
    let res = await patch({ display_name: "  Marcel  " });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { user: { display_name: string } }).user.display_name).toBe("Marcel");
    res = await patch({ display_name: null });
    expect(((await res.json()) as { user: { display_name: string | null } }).user.display_name).toBeNull();
    for (const bad of [{}, { display_name: "" }, { display_name: "   " }, { display_name: "x".repeat(101) }, { display_name: 5 }]) {
      await expectError(await patch(bad), 400, "invalid_request");
    }
    expect((await patch({ display_name: "x".repeat(100), other: 1 })).status).toBe(200);
    // The name shows up in later token responses.
    const refreshed = await call(deps, postForm("/v1/auth/token", { grant_type: "refresh_token", refresh_token: s.refreshToken }));
    expect(((await refreshed.json()) as TokenResponse).user.display_name).toBe("x".repeat(100));
  });
});

describe("POST /v1/account/delete", () => {
  it("removes every row of the user in every table, ends all sessions and revokes the Apple token", async () => {
    const sub = unique("asub");
    const phone = await signInWeb(world, deps, "apple", { sub, appleUser: JSON.stringify({ name: { firstName: "Del" } }) });
    const tablet = await signInWeb(world, deps, "apple", { sub });
    const uid = phone.tokens.user.id;
    const bystander = await directSession(deps);

    // Data in every table, an unredeemed app code and a pending one.
    const rows = sampleRows();
    for (const table of DATA_TABLES) {
      for (const s of [phone.tokens.access_token, bystander.accessToken]) {
        const res = await call(deps, postJson("/v1/sync/push", { table, rows: [rows[table]] }, bearer(s)));
        expect(res.status).toBe(200);
      }
    }
    const pk = await appPkce();
    const start = await call(deps, get(startUrl("apple", pk)), world.env());
    const { code, state } = world.authorize(start.headers.get("Location")!, sub);
    const cb = await call(deps, postForm("/v1/auth/apple/callback", { code, state }), world.env());
    expect(cb.status).toBe(303);
    const sealedCount = await count("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?1 AND provider_refresh_token IS NOT NULL", uid);
    expect(sealedCount).toBe(1);

    const ctx = new TestCtx();
    const before = world.revoked.length;
    const res = await call(deps, postJson("/v1/account/delete", {}, bearer(phone.tokens.access_token)), world.env(), ctx);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deleted: true });
    expect(ctx.promises.length).toBe(1);

    const sid = decodeJwt(tablet.tokens.access_token)!.payload.sid;
    for (const [sql, arg] of [
      ...DATA_TABLES.map((t) => [`SELECT COUNT(*) AS n FROM ${t} WHERE user_id = ?1`, uid] as const),
      ["SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?1", uid],
      ["SELECT COUNT(*) AS n FROM refresh_tokens WHERE session_id = ?1", sid],
      ["SELECT COUNT(*) AS n FROM auth_codes WHERE user_id = ?1", uid],
      ["SELECT COUNT(*) AS n FROM identities WHERE user_id = ?1", uid],
      ["SELECT COUNT(*) AS n FROM profiles WHERE user_id = ?1", uid],
      ["SELECT COUNT(*) AS n FROM users WHERE id = ?1", uid],
    ] as const) {
      expect(await count(sql, arg), sql).toBe(0);
    }
    // Other users are untouched.
    for (const table of DATA_TABLES) {
      expect(await count(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id = ?1`, bystander.userId)).toBe(1);
    }
    // Every device is signed out immediately.
    await expectError(await call(deps, get("/v1/me", bearer(phone.tokens.access_token))), 401, "invalid_token");
    await expectError(await call(deps, get("/v1/me", bearer(tablet.tokens.access_token))), 401, "invalid_token");
    await expectError(
      await call(deps, postForm("/v1/auth/token", { grant_type: "refresh_token", refresh_token: tablet.tokens.refresh_token })),
      400,
      "invalid_grant",
    );
    // The pending app code is gone too.
    const redirect = new URL(cb.headers.get("Location")!);
    await expectError(
      await call(
        deps,
        postForm("/v1/auth/token", { grant_type: "authorization_code", code: redirect.searchParams.get("code")!, code_verifier: pk.verifier, redirect_uri: APP_REDIRECT }),
      ),
      400,
      "invalid_grant",
    );

    // Apple revocation runs in waitUntil with the right client.
    await ctx.drain();
    const revoked = world.revoked.slice(before);
    expect(revoked.length).toBe(1);
    expect(revoked[0]!.client_id).toBe(world.secrets.APPLE_SERVICES_ID);
    expect(revoked[0]!.token).toMatch(/^apple-refresh-/);

    // Signing in again creates a fresh, empty account.
    const again = await signInWeb(world, deps, "apple", { sub });
    expect(again.tokens.user.id).not.toBe(uid);
  });

  it("accepts an empty body; rejects non-JSON content types; requires a session", async () => {
    const s = await directSession(deps);
    await expectError(
      await call(deps, new Request("https://api.test/v1/account/delete", { method: "POST", headers: { ...bearer(s.accessToken), "Content-Type": "text/plain" }, body: "x" })),
      415,
      "unsupported_media_type",
    );
    const res = await call(deps, new Request("https://api.test/v1/account/delete", { method: "POST", headers: bearer(s.accessToken) }));
    expect(res.status).toBe(200);
    await expectError(await call(deps, postJson("/v1/account/delete", {})), 401, "invalid_token");
  });

  it("Apple revocation failures never fail the deletion", async () => {
    const sub = unique("asub");
    const signedIn = await signInWeb(world, deps, "apple", { sub });
    const saved = world.deps.net.handlers.get("https://appleid.apple.com/auth/revoke")!;
    world.deps.net.on("https://appleid.apple.com/auth/revoke", () => {
      throw new TypeError("network down");
    });
    try {
      const ctx = new TestCtx();
      const res = await call(deps, postJson("/v1/account/delete", {}, bearer(signedIn.tokens.access_token)), world.env(), ctx);
      expect(res.status).toBe(200);
      await ctx.drain();
      expect(deps.logs.some((l) => l.event === "apple_revoke_failed")).toBe(true);
    } finally {
      world.deps.net.on("https://appleid.apple.com/auth/revoke", saved);
    }
  });
});
