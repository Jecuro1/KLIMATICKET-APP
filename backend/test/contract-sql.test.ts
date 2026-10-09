// Architect's executable proof of the SQL patterns the contract relies on (docs/CLOUDFLARE_BACKEND.md §3.6/§4).
// WP-S may move these into its own tests but must keep every assertion passing.
// Note: with @cloudflare/vitest-plugin 1.x the D1 state is shared by all tests of a file (no per-test rollback) –
// use fresh ids per test.
import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

const USER = "11111111-1111-4111-8111-111111111111";

// §3.6: one batch per push chunk = reserve n revisions, then one INSERT … SELECT FROM json_each(?) upsert.
const RESERVE = "UPDATE sync_state SET server_rev = server_rev + ?1 WHERE id = 1 RETURNING server_rev";
const UPSERT_BENEFITS = `
INSERT INTO benefits (user_id, id, date, partner_id, title, saved_eur, note, created_at, updated_at, deleted_at, server_rev)
SELECT ?1, j.value ->> '$.id', j.value ->> '$.date', j.value ->> '$.partner_id', j.value ->> '$.title',
       j.value ->> '$.saved_eur', j.value ->> '$.note', j.value ->> '$.created_at', j.value ->> '$.updated_at',
       j.value ->> '$.deleted_at',
       (SELECT server_rev FROM sync_state WHERE id = 1) - ?3 + j.key + 1
FROM json_each(?2) AS j
WHERE true
ON CONFLICT (user_id, id) DO UPDATE SET
  date = excluded.date, partner_id = excluded.partner_id, title = excluded.title, saved_eur = excluded.saved_eur,
  note = excluded.note, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at,
  server_rev = excluded.server_rev
WHERE excluded.updated_at >= benefits.updated_at
  AND (excluded.date IS NOT benefits.date OR excluded.partner_id IS NOT benefits.partner_id
       OR excluded.title IS NOT benefits.title OR excluded.saved_eur IS NOT benefits.saved_eur
       OR excluded.note IS NOT benefits.note OR excluded.deleted_at IS NOT benefits.deleted_at)`;

type Row = {
  id: string; date: string; partner_id: string; title: string; saved_eur: number; note: string;
  created_at: string; updated_at: string; deleted_at: string | null;
};

function row(over: Partial<Row> = {}): Row {
  return {
    id: "aaaaaaaa-0000-4000-8000-000000000001",
    date: "2026-10-01T08:00:00.000000Z",
    partner_id: "custom",
    title: "Therme",
    saved_eur: 4.5,
    note: "",
    created_at: "2026-10-01T08:00:00.000000Z",
    updated_at: "2026-10-01T08:00:00.000000Z",
    deleted_at: null,
    ...over,
  };
}

async function push(rows: Row[]): Promise<{ applied: number; serverRev: number }> {
  const [reserved, upsert] = await env.DB.batch([
    env.DB.prepare(RESERVE).bind(rows.length),
    env.DB.prepare(UPSERT_BENEFITS).bind(USER, JSON.stringify(rows), rows.length),
  ]);
  const serverRev = (reserved!.results[0] as { server_rev: number }).server_rev;
  return { applied: upsert!.meta.changes, serverRev };
}

async function stored(id = row().id) {
  return env.DB.prepare("SELECT * FROM benefits WHERE user_id = ?1 AND id = ?2").bind(USER, id).first<Row & { server_rev: number }>();
}

describe("contract SQL patterns (D1)", () => {
  it("health endpoint reads the migrated database", async () => {
    const res = await exports.default.fetch(new Request("https://api.test/v1/health"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("enforces foreign keys (rows for unknown users fail)", async () => {
    await expect(push([row()])).rejects.toThrow(/FOREIGN KEY/i);
  });

  it("inserts, applies newer edits, skips stale writes and echoes, assigns unique increasing revisions", async () => {
    await env.DB.prepare("INSERT INTO users (id, created_at, last_login_at) VALUES (?1, 0, 0)").bind(USER).run();

    const first = await push([row(), row({ id: "aaaaaaaa-0000-4000-8000-000000000002", title: "Museum" })]);
    expect(first.applied).toBe(2);
    const a = await stored();
    const b = await stored("aaaaaaaa-0000-4000-8000-000000000002");
    expect(a!.server_rev).toBe(first.serverRev - 1);
    expect(b!.server_rev).toBe(first.serverRev);

    // Echo: same content, newer updated_at → skipped, no revision bump.
    const echo = await push([row({ updated_at: "2026-10-02T08:00:00.000000Z" })]);
    expect(echo.applied).toBe(0);
    expect((await stored())!.server_rev).toBe(a!.server_rev);
    expect((await stored())!.updated_at).toBe("2026-10-01T08:00:00.000000Z");

    // Stale write (older updated_at) → skipped.
    const stale = await push([row({ title: "Alt", updated_at: "2026-09-30T08:00:00.000000Z" })]);
    expect(stale.applied).toBe(0);
    expect((await stored())!.title).toBe("Therme");

    // Newer edit → applied, new revision, created_at immutable.
    const edit = await push([row({ title: "Neu", updated_at: "2026-10-03T08:00:00.000000Z", created_at: "2030-01-01T00:00:00.000000Z" })]);
    expect(edit.applied).toBe(1);
    const after = await stored();
    expect(after!.title).toBe("Neu");
    expect(after!.server_rev).toBe(edit.serverRev);
    expect(after!.created_at).toBe("2026-10-01T08:00:00.000000Z");

    // Equal updated_at with different content → applied (ties go to the incoming write, like 0002_sync_hardening).
    const tie = await push([row({ title: "Gleichstand", updated_at: "2026-10-03T08:00:00.000000Z" })]);
    expect(tie.applied).toBe(1);

    // Soft delete → applied; pull by revision returns the tombstone.
    const del = await push([row({ title: "Gleichstand", updated_at: "2026-10-04T08:00:00.000000Z", deleted_at: "2026-10-04T08:00:00.000000Z" })]);
    expect(del.applied).toBe(1);
    const pulled = await env.DB.prepare(
      "SELECT id, deleted_at, server_rev FROM benefits WHERE user_id = ?1 AND server_rev > ?2 ORDER BY server_rev ASC LIMIT ?3",
    ).bind(USER, tie.serverRev, 500).all<{ id: string; deleted_at: string | null; server_rev: number }>();
    expect(pulled.results).toEqual([{ id: row().id, deleted_at: "2026-10-04T08:00:00.000000Z", server_rev: del.serverRev }]);
  });

  it("keeps rows of different users apart (primary key user_id, id)", async () => {
    const other = "22222222-2222-4222-8222-222222222222";
    const id = "aaaaaaaa-0000-4000-8000-000000000099";
    await env.DB.batch([
      env.DB.prepare("INSERT OR IGNORE INTO users (id, created_at, last_login_at) VALUES (?1, 0, 0)").bind(USER),
      env.DB.prepare("INSERT OR IGNORE INTO users (id, created_at, last_login_at) VALUES (?1, 0, 0)").bind(other),
    ]);
    await push([row({ id })]);
    await env.DB.batch([
      env.DB.prepare(RESERVE).bind(1),
      env.DB.prepare(UPSERT_BENEFITS).bind(other, JSON.stringify([row({ id, title: "Fremd" })]), 1),
    ]);
    expect((await stored(id))!.title).toBe("Therme");
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM benefits WHERE id = ?1").bind(id).first<{ n: number }>();
    expect(count!.n).toBe(2);
  });

  it("rate-limit upsert counts within a window and resets in the next one", async () => {
    const hit = (windowStart: number) =>
      env.DB.prepare(
        `INSERT INTO rate_limits (bucket, window_start, count) VALUES (?1, ?2, 1)
         ON CONFLICT (bucket) DO UPDATE SET
           count = CASE WHEN rate_limits.window_start = excluded.window_start THEN rate_limits.count + 1 ELSE 1 END,
           window_start = excluded.window_start
         RETURNING count`,
      ).bind("auth_start:x", windowStart).first<{ count: number }>();
    expect((await hit(600_000))!.count).toBe(1);
    expect((await hit(600_000))!.count).toBe(2);
    expect((await hit(1_200_000))!.count).toBe(1);
  });

  it("consumes auth flows exactly once (DELETE … RETURNING)", async () => {
    await env.DB.prepare(
      `INSERT INTO auth_flows (id, provider, nonce, provider_code_verifier, app_code_challenge, app_state, app_redirect_uri, created_at, expires_at)
       VALUES ('flow1', 'google', 'n', 'v', 'c', 's', 'klimabilanz://auth-callback', 0, 600000)`,
    ).run();
    const take = () => env.DB.prepare("DELETE FROM auth_flows WHERE id = ?1 RETURNING *").bind("flow1").first<{ nonce: string }>();
    expect((await take())!.nonce).toBe("n");
    expect(await take()).toBeNull();
  });
});
