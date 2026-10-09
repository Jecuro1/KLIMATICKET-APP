// node --test scripts/*.selftest.mjs   (not *.test.mjs: vitest would collect those and run them inside workerd)
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { isHttpsOrigin, main, renderTemplate } from "./render-wrangler-config.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const realTemplate = readFileSync(path.join(here, "..", "wrangler.template.toml"), "utf8");
const DB_ID = "3f2c8a9e-1b7d-4c55-9e0a-6d1f2b3c4d5e";

test("renders the committed template with all three markers", () => {
  const { text, applied, errors } = renderTemplate(realTemplate, {
    D1_DATABASE_ID: DB_ID,
    PUBLIC_BASE_URL: "https://klimabilanz-api.example.workers.dev/",
    MIN_APP_VERSION: "1.2.0",
  });
  assert.deepEqual(errors, []);
  assert.deepEqual(applied.sort(), ["D1_DATABASE_ID", "MIN_APP_VERSION", "PUBLIC_BASE_URL"]);
  assert.match(text, /^database_id = "3f2c8a9e-1b7d-4c55-9e0a-6d1f2b3c4d5e" # @render D1_DATABASE_ID$/m);
  // trailing slash stripped
  assert.match(text, /^PUBLIC_BASE_URL = "https:\/\/klimabilanz-api\.example\.workers\.dev" # @render PUBLIC_BASE_URL$/m);
  assert.match(text, /^MIN_APP_VERSION = "1\.2\.0" # @render MIN_APP_VERSION$/m);
  // everything without a marker is untouched
  const strip = (s) => s.split("\n").filter((l) => !l.includes("# @render")).join("\n");
  assert.equal(strip(text), strip(realTemplate));
  assert.equal(text.split("\n").length, realTemplate.split("\n").length);
});

test("empty or missing variables keep the template default", () => {
  const { text, kept, errors } = renderTemplate(realTemplate, { D1_DATABASE_ID: DB_ID, MIN_APP_VERSION: "  " });
  assert.deepEqual(errors, []);
  assert.ok(kept.includes("MIN_APP_VERSION") && kept.includes("PUBLIC_BASE_URL"));
  assert.match(text, /^MIN_APP_VERSION = "1\.0\.0" # @render MIN_APP_VERSION$/m);
  assert.match(text, /^PUBLIC_BASE_URL = "" # @render PUBLIC_BASE_URL$/m);
});

test("a left-over placeholder database_id is an error (unless allowed)", () => {
  assert.match(renderTemplate(realTemplate, {}).errors.join("\n"), /placeholder/);
  assert.deepEqual(renderTemplate(realTemplate, {}, { allowPlaceholder: true }).errors, []);
});

test("invalid values are rejected", () => {
  const bad = [
    { D1_DATABASE_ID: "not-a-uuid" },
    { D1_DATABASE_ID: DB_ID, PUBLIC_BASE_URL: "http://insecure.example" },
    { D1_DATABASE_ID: DB_ID, PUBLIC_BASE_URL: "https://x.example/path" },
    { D1_DATABASE_ID: DB_ID, PUBLIC_BASE_URL: "https://x.example?q=1" },
    { D1_DATABASE_ID: DB_ID, MIN_APP_VERSION: "1.0.0-beta" },
    { D1_DATABASE_ID: DB_ID, MIN_APP_VERSION: '1"; evil = "x' },
  ];
  for (const env of bad) assert.notDeepEqual(renderTemplate(realTemplate, env).errors, [], JSON.stringify(env));
});

test("marker on a line without a quoted value is an error", () => {
  const { errors } = renderTemplate('crons = ["x"] # @render FOO\n', { FOO: "y" }, { allowPlaceholder: true });
  assert.equal(errors.length, 1);
});

test("unknown marker names are TOML-escaped", () => {
  const { text, errors } = renderTemplate('X = "a" # @render FOO\n', { FOO: 'b"\\c' }, { allowPlaceholder: true });
  assert.deepEqual(errors, []);
  assert.equal(text, 'X = "b\\"\\\\c" # @render FOO\n');
});

test("isHttpsOrigin", () => {
  assert.ok(isHttpsOrigin("https://api.example.at"));
  assert.ok(isHttpsOrigin("https://klimabilanz-api.foo.workers.dev"));
  assert.ok(isHttpsOrigin("https://api.example.at:8443"));
  for (const v of ["", "api.example.at", "http://a.b", "https://", "https://a.b/x", "https://u:p@a.b", "https://a.b#f"]) {
    assert.equal(isHttpsOrigin(v), false, v);
  }
});

test("CLI writes the file and fails without writing on errors", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "kb-render-"));
  const input = path.join(dir, "in.toml");
  const output = path.join(dir, "out.toml");
  writeFileSync(input, realTemplate);
  const log = console.log;
  console.log = () => {};
  try {
    assert.equal(main(["--in", input, "--out", output], {}), 1);
    assert.equal(existsSync(output), false);
    assert.equal(main(["--in", input, "--out", output], { D1_DATABASE_ID: DB_ID }), 0);
  } finally {
    console.log = log;
  }
  assert.match(readFileSync(output, "utf8"), new RegExp(DB_ID));
});
