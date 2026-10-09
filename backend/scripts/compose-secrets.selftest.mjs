// node --test scripts/*.selftest.mjs   (not *.test.mjs: vitest would collect those and run them inside workerd)
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import {
  ComposeError,
  MANAGED_SECRETS,
  SIGNING_KEY,
  composeSecrets,
  looksLikeP8,
  main,
  parseExistingSecrets,
} from "./compose-secrets.mjs";

const P8 = [
  "-----BEGIN PRIVATE KEY-----",
  "MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg" + "A".repeat(40),
  "oAoGCCqGSM49AwEHoUQDQgAE" + "B".repeat(64),
  "-----END PRIVATE KEY-----",
].join("\n");
const fixedKey = () => "k".repeat(64);

test("parseExistingSecrets: Cloudflare envelope, wrangler list, first deploy, failures", () => {
  const env = JSON.stringify({ success: true, errors: [], result: [{ name: "A", type: "secret_text" }] });
  assert.deepEqual([...parseExistingSecrets(200, env).names], ["A"]);
  assert.deepEqual([...parseExistingSecrets(200, '[{"name":"B","type":"secret_text"}]').names], ["B"]);
  assert.deepEqual([...parseExistingSecrets(200, '{"success":true,"result":[]}').names], []);

  const notFound = JSON.stringify({ success: false, errors: [{ code: 10007, message: "This Worker does not exist on your account." }] });
  assert.deepEqual(parseExistingSecrets(404, notFound), { names: new Set(), firstDeploy: true });

  // Anything else must abort: assuming "no secrets" would rotate the signing key.
  const auth = JSON.stringify({ success: false, errors: [{ code: 10000, message: "Authentication error" }] });
  assert.throws(() => parseExistingSecrets(403, auth), (e) => e instanceof ComposeError && /10000/.test(e.message));
  assert.throws(() => parseExistingSecrets(404, "<html>not found</html>"), ComposeError);
  assert.throws(() => parseExistingSecrets(500, ""), ComposeError);
  assert.throws(() => parseExistingSecrets(200, "<html>"), ComposeError);
  assert.throws(() => parseExistingSecrets(200, '{"success":false,"result":[]}'), ComposeError);
});

test("first deploy: generates the signing key once, sets only non-empty secrets (trimmed)", () => {
  const r = composeSecrets({
    env: { GOOGLE_CLIENT_ID: " gid \n", GOOGLE_CLIENT_SECRET: "gsecret", MICROSOFT_CLIENT_ID: "" },
    existing: new Set(),
    generateKey: fixedKey,
  });
  assert.deepEqual(r.secrets, { GOOGLE_CLIENT_ID: "gid", GOOGLE_CLIENT_SECRET: "gsecret", [SIGNING_KEY]: fixedKey() });
  assert.equal(r.generatedKey, true);
  assert.deepEqual(r.stale, {});
  assert.deepEqual(r.warnings, []);
});

test("existing signing key is never rotated or deleted", () => {
  const r = composeSecrets({
    env: {},
    existing: new Set([SIGNING_KEY, "SESSION_SIGNING_KEY_PREVIOUS"]),
    generateKey: () => assert.fail("must not generate"),
  });
  assert.deepEqual(r.secrets, {});
  assert.deepEqual(r.stale, {});
  assert.equal(r.generatedKey, false);
});

test("provider secrets deleted in GitHub are pruned, unknown Worker secrets are kept", () => {
  const existing = new Set([SIGNING_KEY, "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "APPLE_BUNDLE_ID", "MY_OWN_SECRET"]);
  const r = composeSecrets({ env: { APPLE_BUNDLE_ID: "com.knitelarlberg.klimabilanz" }, existing, generateKey: fixedKey });
  assert.deepEqual(r.stale, { GOOGLE_CLIENT_ID: null, GOOGLE_CLIENT_SECRET: null });
  assert.deepEqual(r.secrets, { APPLE_BUNDLE_ID: "com.knitelarlberg.klimabilanz" });

  const kept = composeSecrets({ env: {}, existing, keepWorkerSecrets: true, generateKey: fixedKey });
  assert.deepEqual(kept.stale, {});
});

test("half-configured providers and a broken .p8 produce warnings", () => {
  const r = composeSecrets({
    env: { MICROSOFT_CLIENT_ID: "mid", APPLE_SERVICES_ID: "web", APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K", APPLE_PRIVATE_KEY: "nope" },
    existing: new Set([SIGNING_KEY]),
  });
  const text = r.warnings.join("\n");
  assert.match(text, /Microsoft: MICROSOFT_CLIENT_SECRET fehlt/);
  assert.match(text, /APPLE_PRIVATE_KEY sieht nicht/);
  assert.doesNotMatch(text, /Google/);
});

test("looksLikeP8 accepts PEM with real or escaped newlines and the bare body", () => {
  assert.ok(looksLikeP8(P8));
  assert.ok(looksLikeP8(P8.replace(/\n/g, "\\n")));
  assert.ok(looksLikeP8(P8.replace(/\n/g, "\r\n")));
  assert.ok(looksLikeP8(P8.split("\n").slice(1, -1).join("")));
  assert.equal(looksLikeP8("-----BEGIN PRIVATE KEY-----\nshort\n-----END PRIVATE KEY-----"), false);
});

test("main writes mode-600 files, masks the generated key and never prints values", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "kb-secrets-"));
  const existingFile = path.join(dir, "existing.json");
  const output = path.join(dir, "out.txt");
  writeFileSync(existingFile, JSON.stringify({ success: true, result: [{ name: "MICROSOFT_CLIENT_ID" }] }));
  const env = {
    RUNNER_TEMP: dir,
    EXISTING_SECRETS_FILE: existingFile,
    EXISTING_SECRETS_STATUS: "200",
    GITHUB_OUTPUT: output,
    GOOGLE_CLIENT_ID: "google-id-value",
    GOOGLE_CLIENT_SECRET: "google-secret-value",
    APPLE_PRIVATE_KEY: P8,
  };
  const lines = [];
  const log = console.log;
  console.log = (...a) => lines.push(a.join(" "));
  let result;
  try {
    result = main(env);
  } finally {
    console.log = log;
  }
  const secretsFile = path.join(dir, "kb-secrets.json");
  const staleFile = path.join(dir, "kb-stale.json");
  assert.equal(statSync(secretsFile).mode & 0o777, 0o600);
  assert.equal(statSync(staleFile).mode & 0o777, 0o600);
  const written = JSON.parse(readFileSync(secretsFile, "utf8"));
  assert.equal(written.GOOGLE_CLIENT_ID, "google-id-value");
  assert.equal(written.APPLE_PRIVATE_KEY, P8);
  assert.equal(written[SIGNING_KEY].length, 64);
  assert.deepEqual(JSON.parse(readFileSync(staleFile, "utf8")), { MICROSOFT_CLIENT_ID: null });

  const log0 = lines[0];
  assert.equal(log0, `::add-mask::${written[SIGNING_KEY]}`);
  const rest = lines.slice(1).join("\n");
  for (const value of ["google-id-value", "google-secret-value", "PRIVATE KEY", written[SIGNING_KEY]]) {
    assert.equal(rest.includes(value), false, `printed ${value}`);
  }
  assert.equal(
    readFileSync(output, "utf8"),
    "secret_count=4\nstale_count=1\ngenerated_key=true\nfirst_deploy=false\n",
  );
  assert.equal(result.generatedKey, true);

  // Second run: nothing stale any more → the stale file is removed.
  writeFileSync(existingFile, JSON.stringify({ success: true, result: [{ name: SIGNING_KEY }] }));
  console.log = () => {};
  try {
    main({ ...env, GITHUB_OUTPUT: "" });
  } finally {
    console.log = log;
  }
  assert.equal(existsSync(staleFile), false);
  assert.equal(SIGNING_KEY in JSON.parse(readFileSync(secretsFile, "utf8")), false);
});

test("managed secret list matches the Worker Env (contract §5.4)", () => {
  assert.equal(MANAGED_SECRETS.length, 9);
  const envTs = readFileSync(new URL("../src/env.ts", import.meta.url), "utf8");
  for (const name of [...MANAGED_SECRETS, SIGNING_KEY]) assert.match(envTs, new RegExp(`\\b${name}\\?:`), name);
});
