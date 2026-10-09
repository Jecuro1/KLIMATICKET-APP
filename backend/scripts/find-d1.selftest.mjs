// node --test scripts/*.selftest.mjs   (not *.test.mjs: vitest would collect those and run them inside workerd)
import assert from "node:assert/strict";
import { test } from "node:test";

import { findDatabase, main, parseListing } from "./find-d1.mjs";

const LIST = [
  { uuid: "11111111-2222-3333-4444-555555555555", name: "other", created_at: "2026-01-01T00:00:00Z" },
  { uuid: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", name: "klimabilanz", created_at: "2026-10-09T12:00:00Z", jurisdiction: "eu" },
];

test("finds the database by exact name and lowercases the uuid", () => {
  assert.deepEqual(findDatabase(LIST, "klimabilanz"), { uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", jurisdiction: "eu" });
  assert.equal(findDatabase(LIST, "klima"), null);
  assert.deepEqual(findDatabase([{ uuid: LIST[0].uuid, name: "x" }], "x"), { uuid: LIST[0].uuid, jurisdiction: null });
  assert.throws(() => findDatabase([{ name: "x", uuid: "nope" }], "x"));
});

test("parses plain output, the API envelope and output with log lines around it", () => {
  const json = JSON.stringify(LIST, null, 2);
  assert.equal(parseListing(json).length, 2);
  assert.equal(parseListing(JSON.stringify({ success: true, result: LIST })).length, 2);
  const noisy = `▲ [WARNING] Proxy environment variables detected.\n\n${json}\n`;
  assert.equal(parseListing(noisy).length, 2);
  assert.deepEqual(parseListing("[]"), []);
  assert.throws(() => parseListing("✘ [ERROR] Authentication error [code: 10000]"));
});

test("CLI exit codes: 0 found, 2 missing", () => {
  const lines = [];
  const log = console.log;
  console.log = (l) => lines.push(l);
  try {
    assert.equal(main(["klimabilanz"], () => JSON.stringify(LIST)), 0);
    assert.equal(main(["missing"], () => JSON.stringify(LIST)), 2);
  } finally {
    console.log = log;
  }
  assert.deepEqual(lines, ["uuid=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "jurisdiction=eu"]);
});
