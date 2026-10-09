// Sync push/pull (docs/CLOUDFLARE_BACKEND.md §3.4–§3.7): fixture round-trip, last writer wins, clamp, echo-skip,
// ties, soft deletes, immutable fields, user isolation, paging, malformed input.
import { beforeAll, describe, expect, it } from "vitest";
import fixture from "./fixtures/contract-rows.json";
import { canonicalFromMs } from "../src/timestamps";
import { SCHEMAS, SYNC_TABLES, type SyncTable } from "../src/sync/schema";
import { bearer, call, db, directSession, expectError, get, makeDeps, postJson, uuid, type DirectSession, type TestDeps } from "./helpers";

type Row = Record<string, unknown>;
interface PushResult {
  applied: number;
  skipped: number;
  server_rev: number;
}

let deps: TestDeps;

beforeAll(() => {
  deps = makeDeps();
});

function push(s: DirectSession, table: string, rows: unknown, headers: Record<string, string> = {}): Promise<Response> {
  return call(deps, postJson("/v1/sync/push", { table, rows }, { ...bearer(s.accessToken), ...headers }));
}

async function pushOk(s: DirectSession, table: string, rows: Row[]): Promise<PushResult> {
  const res = await push(s, table, rows);
  if (res.status !== 200) throw new Error(`push failed: ${res.status} ${await res.text()}`);
  return (await res.json()) as PushResult;
}

async function pullPage(s: DirectSession, table: string, after?: number | string, limit?: number | string): Promise<{ rows: Row[]; next: number | null }> {
  const q = new URLSearchParams({ table });
  if (after !== undefined) q.set("after", String(after));
  if (limit !== undefined) q.set("limit", String(limit));
  const res = await call(deps, get(`/v1/sync/pull?${q}`, bearer(s.accessToken)));
  expect(res.status).toBe(200);
  return (await res.json()) as { rows: Row[]; next: number | null };
}

async function pullAll(s: DirectSession, table: string, limit = 500): Promise<{ rows: Row[]; pages: number }> {
  let after = 0;
  const rows: Row[] = [];
  let pages = 0;
  for (;;) {
    const page = await pullPage(s, table, after, limit);
    pages++;
    rows.push(...page.rows);
    if (page.next === null) break;
    expect(page.next).toBeGreaterThan(after);
    after = page.next;
  }
  return { rows, pages };
}

async function stored(s: DirectSession, table: string, id: string): Promise<Row | undefined> {
  return (await pullAll(s, table)).rows.find((r) => r.id === id);
}

const ts = (day: number, extra = "00:00:00.000000") => `2026-10-${String(day).padStart(2, "0")}T${extra}Z`;

function trip(over: Row = {}): Row {
  return {
    id: "a0000000-0000-4000-8000-000000000001",
    date: ts(1, "08:00:00.000000"),
    from_name: "Bludenz",
    to_name: "Feldkirch",
    from_station_id: null,
    to_station_id: null,
    mode: "train",
    distance_km: 21.5,
    fare_eur: 4.4,
    is_fare_manual: false,
    is_round_trip: false,
    travel_class: "second",
    companions: 0,
    states: "V",
    note: "",
    created_at: ts(1),
    updated_at: ts(1),
    deleted_at: null,
    ...over,
  };
}

function benefit(id: string, over: Row = {}): Row {
  return {
    id,
    date: ts(2),
    partner_id: "custom",
    title: "Therme",
    saved_eur: 4.5,
    note: "",
    created_at: ts(2),
    updated_at: ts(2),
    ...over,
  };
}

describe("contract fixture round-trip", () => {
  it("push → pull reproduces the expected pull row for every table", async () => {
    const s = await directSession(deps, { userId: fixture.user_id });
    const tables = fixture.tables as Record<string, { push: Row; pull: Row }>;
    expect(Object.keys(tables).sort()).toEqual([...SYNC_TABLES].sort());
    for (const table of SYNC_TABLES) {
      const { push: pushRow, pull: expected } = tables[table]!;
      const result = await pushOk(s, table, [pushRow]);
      expect(result.applied).toBe(1);
      expect(result.skipped).toBe(0);
      const page = await pullPage(s, table, 0);
      expect(page.rows.length).toBe(1);
      const row = page.rows[0]!;
      expect(row).toEqual({ ...expected, server_rev: result.server_rev });
      // Exact key set: every column + user_id + server_rev, nullable ones as null.
      expect(Object.keys(row).sort()).toEqual(Object.keys(expected).sort());
      expect(Object.keys(row).length).toBe(SCHEMAS[table].columns.length + 2);
      expect(page.next).toBeNull();
    }
  });
});

describe("last writer wins", () => {
  it("insert, stale skip, echo skip, newer edit, ties, soft delete, undelete", async () => {
    const s = await directSession(deps);
    const first = await pushOk(s, "trips", [trip()]);
    expect(first).toMatchObject({ applied: 1, skipped: 0 });
    const rev1 = (await stored(s, "trips", trip().id as string))!.server_rev as number;
    expect(rev1).toBe(first.server_rev);

    // Stale write (older updated_at, different content) → skipped.
    const stale = await pushOk(s, "trips", [trip({ note: "alt", updated_at: "2026-09-30T23:59:59.999999Z" })]);
    expect(stale).toMatchObject({ applied: 0, skipped: 1 });
    expect((await stored(s, "trips", trip().id as string))!.note).toBe("");

    // Echo: same content, newer updated_at → skipped, no revision bump, updated_at unchanged.
    const echo = await pushOk(s, "trips", [trip({ updated_at: ts(5) })]);
    expect(echo).toMatchObject({ applied: 0, skipped: 1 });
    let row = (await stored(s, "trips", trip().id as string))!;
    expect(row.server_rev).toBe(rev1);
    expect(row.updated_at).toBe(ts(1));

    // Newer edit → applied with a new revision.
    const edit = await pushOk(s, "trips", [trip({ note: "neu", updated_at: ts(3) })]);
    expect(edit.applied).toBe(1);
    row = (await stored(s, "trips", trip().id as string))!;
    expect(row).toMatchObject({ note: "neu", updated_at: ts(3), server_rev: edit.server_rev });
    expect(edit.server_rev).toBeGreaterThan(rev1);

    // One microsecond newer counts as newer.
    const micro = await pushOk(s, "trips", [trip({ note: "µ", updated_at: "2026-10-03T00:00:00.000001Z" })]);
    expect(micro.applied).toBe(1);

    // Equal updated_at, different content → applied; equal updated_at, same content → skipped.
    const tie = await pushOk(s, "trips", [trip({ note: "gleich", updated_at: "2026-10-03T00:00:00.000001Z" })]);
    expect(tie.applied).toBe(1);
    const tieEcho = await pushOk(s, "trips", [trip({ note: "gleich", updated_at: "2026-10-03T00:00:00.000001Z" })]);
    expect(tieEcho.applied).toBe(0);

    // Soft delete, then undelete by a newer write.
    const del = await pushOk(s, "trips", [trip({ note: "gleich", updated_at: ts(4), deleted_at: ts(4) })]);
    expect(del.applied).toBe(1);
    expect((await stored(s, "trips", trip().id as string))!.deleted_at).toBe(ts(4));
    const undelete = await pushOk(s, "trips", [trip({ note: "gleich", updated_at: ts(6), deleted_at: null })]);
    expect(undelete.applied).toBe(1);
    row = (await stored(s, "trips", trip().id as string))!;
    expect(row.deleted_at).toBeNull();
    // Pull after a cursor returns only the latest state of changed rows.
    const after = await pullPage(s, "trips", del.server_rev);
    expect(after.rows.map((r) => r.server_rev)).toEqual([undelete.server_rev]);
  });

  it("id, user_id and created_at are immutable; ids are case-insensitive and stored lowercase", async () => {
    const s = await directSession(deps);
    const id = "B0000000-0000-4000-8000-0000000000AB";
    await pushOk(s, "trips", [trip({ id, created_at: ts(1) })]);
    const res = await pushOk(s, "trips", [
      trip({ id: id.toLowerCase(), user_id: s.userId.toUpperCase(), created_at: "2030-01-01T00:00:00.000000Z", note: "x", updated_at: ts(2) }),
    ]);
    expect(res.applied).toBe(1);
    const rows = (await pullAll(s, "trips")).rows.filter((r) => (r.id as string).startsWith("b0000000"));
    expect(rows.length).toBe(1);
    expect(rows[0]).toMatchObject({ id: id.toLowerCase(), user_id: s.userId, created_at: ts(1), note: "x" });
  });

  it("clamps far-future updated_at to now (10 min tolerance), not created_at", async () => {
    const s = await directSession(deps);
    const now = deps.now();
    const far = trip({ id: uuid(), updated_at: "2030-01-01T00:00:00.000000Z", created_at: "2030-01-01T00:00:00.000000Z" });
    await pushOk(s, "trips", [far]);
    const row = (await stored(s, "trips", far.id as string))!;
    expect(row.updated_at).toBe(canonicalFromMs(now));
    expect(row.created_at).toBe("2030-01-01T00:00:00.000000Z");
    const near = trip({ id: uuid(), updated_at: canonicalFromMs(now + 9 * 60_000) });
    await pushOk(s, "trips", [near]);
    expect((await stored(s, "trips", near.id as string))!.updated_at).toBe(canonicalFromMs(now + 9 * 60_000));
    // A device with a fast clock cannot block later edits forever: a normal edit after the clamp wins.
    deps.clock.advance(1000);
    const later = await pushOk(s, "trips", [{ ...far, note: "später", updated_at: canonicalFromMs(deps.now()) }]);
    expect(later.applied).toBe(1);
  });

  it("deduplicates ids within one push (greatest updated_at; on a tie the last one)", async () => {
    const s = await directSession(deps);
    const id = uuid();
    const res = await pushOk(s, "trips", [
      trip({ id, note: "1", updated_at: ts(1) }),
      trip({ id: id.toUpperCase(), note: "3", updated_at: ts(3) }),
      trip({ id, note: "2", updated_at: ts(2) }),
    ]);
    expect(res).toMatchObject({ applied: 1, skipped: 2 });
    expect((await stored(s, "trips", id))!.note).toBe("3");
    const tie = await pushOk(s, "trips", [trip({ id, note: "a", updated_at: ts(4) }), trip({ id, note: "b", updated_at: ts(4) })]);
    expect(tie).toMatchObject({ applied: 1, skipped: 1 });
    expect((await stored(s, "trips", id))!.note).toBe("b");
  });

  it("fills defaults for absent optional columns and returns booleans", async () => {
    const s = await directSession(deps);
    const t = trip({ id: uuid(), is_round_trip: true });
    delete t.from_station_id;
    delete t.deleted_at;
    await pushOk(s, "trips", [t]);
    const row = (await stored(s, "trips", t.id as string))!;
    expect(row).toMatchObject({ category: "", is_induced: false, from_station_id: null, deleted_at: null, is_round_trip: true, is_fare_manual: false });
    const ticket = {
      id: uuid(),
      product_id: "oe-klassik",
      name: "KlimaTicket Ö",
      variant: "klassik",
      family: "oe",
      states: "",
      price: 1179,
      start_date: ts(1),
      end_date: "2027-09-30T23:59:59.000000Z",
      holder_name: "",
      ticket_number: "",
      theme: "twilight",
      reminders: "30,7,1",
      created_at: ts(1),
      updated_at: ts(1),
      is_monthly_payment: null,
    };
    await pushOk(s, "tickets", [ticket]);
    expect((await stored(s, "tickets", ticket.id))!).toMatchObject({
      is_monthly_payment: false,
      auto_renews: false,
      employer_contribution: 0,
      add_on_price: 0,
      add_ons: "",
      price: 1179,
    });
  });

  it("via (docs/VIA.md): new rows default to '', an older app's push without it keeps the stored value, '' clears", async () => {
    const s = await directSession(deps);
    const id = uuid();
    const via = "at:48:817\tFeldkirch\n\tLech Postamt";
    // New row from an older app (no via key) → default.
    await pushOk(s, "trips", [trip({ id })]);
    expect((await stored(s, "trips", id))!.via).toBe("");
    // A newer app writes the vias.
    await pushOk(s, "trips", [trip({ id, via, updated_at: ts(2) })]);
    expect((await stored(s, "trips", id))!.via).toBe(via);
    // The older app edits the note: absent (or null) via keeps the stored vias, the edit applies.
    const older = await pushOk(s, "trips", [trip({ id, note: "älter", updated_at: ts(3) })]);
    expect(older.applied).toBe(1);
    expect((await stored(s, "trips", id))!).toMatchObject({ via, note: "älter" });
    await pushOk(s, "trips", [trip({ id, note: "null", via: null, updated_at: ts(4) })]);
    expect((await stored(s, "trips", id))!).toMatchObject({ via, note: "null" });
    // Echo of the older app's row (same content, no via) is skipped, not applied.
    const echo = await pushOk(s, "trips", [trip({ id, note: "null", updated_at: ts(4) })]);
    expect(echo).toMatchObject({ applied: 0, skipped: 1 });
    // The newer app removes the vias.
    await pushOk(s, "trips", [trip({ id, note: "null", via: "", updated_at: ts(5) })]);
    expect((await stored(s, "trips", id))!.via).toBe("");

    const favorite = {
      id: uuid(), title: "", from_name: "Innsbruck Hbf", to_name: "Bregenz", mode: "train", distance_km: 202.8, fare_eur: 43.3,
      is_round_trip: false, states: "T,V", sort_index: 0, usage_count: 0, created_at: ts(1), updated_at: ts(1),
      via: "at:48:817\tFeldkirch",
    };
    await pushOk(s, "favorite_routes", [favorite]);
    const { via: _dropped, ...withoutVia } = favorite;
    await pushOk(s, "favorite_routes", [{ ...withoutVia, usage_count: 3, updated_at: ts(2) }]);
    expect((await stored(s, "favorite_routes", favorite.id))!).toMatchObject({ via: "at:48:817\tFeldkirch", usage_count: 3 });
  });

  it("journeys (docs/JOURNEYS.md): new rows default to ''/0, an older app's push keeps journey_id, leg_index and legs", async () => {
    const s = await directSession(deps);
    const id = uuid();
    const journey = "7c1d4e2a-9b3f-4a5e-8d6c-1f2e3a4b5c6d";
    // New row from an older app (no journey keys) → defaults.
    await pushOk(s, "trips", [trip({ id })]);
    expect((await stored(s, "trips", id))!).toMatchObject({ journey_id: "", leg_index: 0 });
    // A newer app makes it leg 2 of a journey.
    await pushOk(s, "trips", [trip({ id, journey_id: journey, leg_index: 1, updated_at: ts(2) })]);
    expect((await stored(s, "trips", id))!).toMatchObject({ journey_id: journey, leg_index: 1 });
    // The older app edits the note: absent journey keys keep the stored journey, the edit applies.
    const older = await pushOk(s, "trips", [trip({ id, note: "älter", updated_at: ts(3) })]);
    expect(older.applied).toBe(1);
    expect((await stored(s, "trips", id))!).toMatchObject({ journey_id: journey, leg_index: 1, note: "älter" });
    // An echo of the older app's row (same content, no journey keys) is skipped.
    const echo = await pushOk(s, "trips", [trip({ id, note: "älter", updated_at: ts(3) })]);
    expect(echo).toMatchObject({ applied: 0, skipped: 1 });
    // The newer app takes the leg out of the journey.
    await pushOk(s, "trips", [trip({ id, note: "älter", journey_id: "", leg_index: 0, updated_at: ts(4) })]);
    expect((await stored(s, "trips", id))!).toMatchObject({ journey_id: "", leg_index: 0 });

    const legs = '[{"eur":5.8,"f":"Lech","km":16,"m":"bus","t":"Langen am Arlberg"},{"eur":36,"f":"Langen am Arlberg","km":144.2,"m":"train","t":"Innsbruck Hbf"}]';
    const favorite = {
      id: uuid(), title: "Kombi", from_name: "Lech", to_name: "Innsbruck Hbf", mode: "train", distance_km: 160.2, fare_eur: 41.8,
      is_round_trip: false, states: "T,V", sort_index: 0, usage_count: 0, created_at: ts(1), updated_at: ts(1), legs,
    };
    await pushOk(s, "favorite_routes", [favorite]);
    const { legs: _dropped, ...withoutLegs } = favorite;
    await pushOk(s, "favorite_routes", [{ ...withoutLegs, usage_count: 4, updated_at: ts(2) }]);
    expect((await stored(s, "favorite_routes", favorite.id))!).toMatchObject({ legs, usage_count: 4 });
  });

  it("rejects malformed journey keys", async () => {
    const s = await directSession(deps);
    await expectError(await push(s, "trips", [trip({ id: uuid(), journey_id: "x".repeat(37) })]), 422, "invalid_row");
    await expectError(await push(s, "trips", [trip({ id: uuid(), leg_index: 1.5 })]), 422, "invalid_row");
    await expectError(await push(s, "trips", [trip({ id: uuid(), leg_index: "1" })]), 422, "invalid_row");
  });

  it("rejects an over-long via", async () => {
    const s = await directSession(deps);
    await expectError(await push(s, "trips", [trip({ id: uuid(), via: "x".repeat(1001) })]), 422, "invalid_row");
  });

  it("assigns one global, strictly increasing revision across tables", async () => {
    const s = await directSession(deps);
    const a = await pushOk(s, "trips", [trip({ id: uuid() })]);
    const b = await pushOk(s, "benefits", [benefit(uuid()), benefit(uuid())]);
    expect(b.server_rev).toBe(a.server_rev + 2);
    const rows = (await pullAll(s, "benefits")).rows;
    expect(rows.map((r) => r.server_rev)).toEqual([b.server_rev - 1, b.server_rev]);
  });

  it("empty pushes answer the current revision", async () => {
    const s = await directSession(deps);
    const a = await pushOk(s, "trips", [trip({ id: uuid() })]);
    expect(await pushOk(s, "favorite_routes", [])).toEqual({ applied: 0, skipped: 0, server_rev: a.server_rev });
  });
});

describe("user isolation", () => {
  it("the same id in two accounts are two rows; nobody sees or changes the other's data", async () => {
    const alice = await directSession(deps);
    const bob = await directSession(deps);
    const id = uuid();
    await pushOk(alice, "benefits", [benefit(id, { title: "Alice" })]);
    await pushOk(bob, "benefits", [benefit(id, { title: "Bob", updated_at: ts(9) })]);
    expect((await stored(alice, "benefits", id))!.title).toBe("Alice");
    expect((await stored(bob, "benefits", id))!.title).toBe("Bob");
    expect((await pullAll(alice, "benefits")).rows.every((r) => r.user_id === alice.userId)).toBe(true);
    // Bob cannot write into Alice's account by naming her user id.
    const res = await push(bob, "benefits", [benefit(uuid(), { user_id: alice.userId })]);
    const body = await expectError(res, 422, "user_mismatch");
    expect(body.details).toEqual({ index: 0, field: "user_id" });
    expect((await pullAll(alice, "benefits")).rows.length).toBe(1);
  });
});

describe("paging", () => {
  it("pages through 1200 rows with a strictly increasing next cursor", async () => {
    const s = await directSession(deps);
    const ids = Array.from({ length: 1200 }, () => uuid());
    for (const chunk of [ids.slice(0, 500), ids.slice(500, 1000), ids.slice(1000)]) {
      const res = await pushOk(s, "benefits", chunk.map((id) => benefit(id)));
      expect(res.applied).toBe(chunk.length);
    }
    const first = await pullPage(s, "benefits");
    expect(first.rows.length).toBe(500);
    expect(first.next).toBe(first.rows[499]!.server_rev);
    const { rows, pages } = await pullAll(s, "benefits", 500);
    expect(pages).toBe(3);
    expect(rows.length).toBe(1200);
    expect(new Set(rows.map((r) => r.id)).size).toBe(1200);
    const revs = rows.map((r) => r.server_rev as number);
    expect(revs).toEqual([...revs].sort((a, b) => a - b));
    expect(new Set(revs).size).toBe(1200);
    // Small pages and an exact multiple: the last page is empty with next = null.
    const small = await pullAll(s, "benefits", 400);
    expect(small.pages).toBe(4);
    expect(small.rows.length).toBe(1200);
    // A cursor past the end.
    expect(await pullPage(s, "benefits", 999_999_999_999)).toEqual({ rows: [], next: null });
  });

  it("validates table, after and limit", async () => {
    const s = await directSession(deps);
    const bad = (q: string) => call(deps, get(`/v1/sync/pull?${q}`, bearer(s.accessToken)));
    await expectError(await bad("table=profiles"), 400, "unknown_table");
    await expectError(await bad(""), 400, "unknown_table");
    for (const q of ["after=-1", "after=1.5", "after=abc", "after=1234567890123456", "limit=0", "limit=501", "limit=abc", "limit=-5"]) {
      await expectError(await bad(`table=trips&${q}`), 400, "invalid_request");
    }
    expect((await bad("table=trips&limit=1&after=0")).status).toBe(200);
  });
});

describe("malformed pushes", () => {
  it("rejects envelopes: unknown table, non-array rows, non-object rows, > 500 rows", async () => {
    const s = await directSession(deps);
    await expectError(await push(s, "profiles", []), 400, "unknown_table");
    await expectError(await call(deps, postJson("/v1/sync/push", { rows: [] }, bearer(s.accessToken))), 400, "unknown_table");
    await expectError(await push(s, "trips", { a: 1 }), 400, "invalid_request");
    await expectError(await push(s, "trips", [1]), 400, "invalid_request");
    await expectError(await push(s, "trips", [null]), 400, "invalid_request");
    const many = Array.from({ length: 501 }, () => benefit(uuid()));
    await expectError(await push(s, "benefits", many), 422, "too_many_rows");
    expect((await pullAll(s, "benefits")).rows.length).toBe(0);
  });

  it("unknown fields → 422 unknown_field with index and field; nothing is written", async () => {
    const s = await directSession(deps);
    const res = await push(s, "trips", [trip({ id: uuid() }), trip({ id: uuid(), photo_data: "…" })]);
    const body = await expectError(res, 422, "unknown_field");
    expect(body.details).toEqual({ index: 1, field: "photo_data" });
    expect((await pullAll(s, "trips")).rows.length).toBe(0);
    // server_rev in push rows is ignored.
    expect((await pushOk(s, "trips", [trip({ id: uuid(), server_rev: 5 })])).applied).toBe(1);
  });

  it.each<[string, unknown, string]>([
    ["id", "not-a-uuid", "format"],
    ["id", 42, "type"],
    ["id", null, "required"],
    ["from_name", undefined, "required"],
    ["from_name", "x".repeat(201), "too_long"],
    ["from_name", "a\u0000b", "nul_character"],
    ["from_name", "a\uD800b", "invalid_unicode"],
    ["note", "x".repeat(10_001), "too_long"],
    ["from_station_id", 8100093, "type"],
    ["distance_km", "21.5", "type"],
    ["distance_km", 1e9 + 1, "out_of_range"],
    ["companions", 1.5, "type"],
    ["companions", 2147483648, "out_of_range"],
    ["is_round_trip", 1, "type"],
    ["is_round_trip", "true", "type"],
    ["is_fare_manual", null, "required"],
    ["date", "2026-10-09", "format"],
    ["date", "yesterday", "format"],
    ["updated_at", 1791547200, "type"],
    ["deleted_at", "2026-02-30T00:00:00Z", "format"],
  ])("invalid_row: %s = %j → %s", async (field, value, reason) => {
    const s = await directSession(deps);
    const row = trip({ id: uuid() });
    if (value === undefined) delete row[field];
    else row[field] = value;
    const res = await push(s, "trips", [trip({ id: uuid() }), row]);
    const body = await expectError(res, 422, "invalid_row");
    expect(body.details).toEqual({ index: 1, field, reason });
  });

  it("accepts boundary values (10 000-char note, emoji, ±1e9, int32 range, offsets)", async () => {
    const s = await directSession(deps);
    const row = trip({
      id: uuid(),
      note: "😀".repeat(5000),
      from_name: "„ruhig“ – Zürich ✓",
      distance_km: 1e9,
      fare_eur: -1e9,
      companions: -2147483648,
      date: "2026-10-09T07:00:00.123456789+02:00",
    });
    await pushOk(s, "trips", [row]);
    const got = (await stored(s, "trips", row.id as string))!;
    expect(got).toMatchObject({ note: row.note, from_name: row.from_name, distance_km: 1e9, fare_eur: -1e9, companions: -2147483648, date: "2026-10-09T05:00:00.123456Z" });
  });

  it("a deleted account's push fails with 401 (FOREIGN KEY → invalid_token)", async () => {
    const s = await directSession(deps);
    const real = db();
    const fkDb = new Proxy(real, {
      get(target, prop, receiver) {
        if (prop === "batch") return async () => { throw new Error("D1_ERROR: FOREIGN KEY constraint failed: SQLITE_CONSTRAINT"); };
        const v = Reflect.get(target, prop, receiver);
        return typeof v === "function" ? v.bind(target) : v;
      },
    });
    const res = await call(deps, postJson("/v1/sync/push", { table: "trips", rows: [trip({ id: uuid() })] }, bearer(s.accessToken)), { DB: fkDb });
    await expectError(res, 401, "invalid_token");
  });

  it("requires a valid session", async () => {
    await expectError(await call(deps, postJson("/v1/sync/push", { table: "trips", rows: [] })), 401, "invalid_token");
    await expectError(await call(deps, get("/v1/sync/pull?table=trips", bearer("a.b.c"))), 401, "invalid_token");
  });
});

describe("schema map", () => {
  it("matches the D1 columns of every synced table", async () => {
    for (const table of SYNC_TABLES as readonly SyncTable[]) {
      const info = await db().prepare(`SELECT name FROM pragma_table_info('${table}') ORDER BY cid`).all<{ name: string }>();
      const expected = ["user_id", ...SCHEMAS[table].columns.map((c) => c.name), "server_rev"];
      expect(info.results.map((r) => r.name).sort()).toEqual(expected.sort());
    }
  });
});
