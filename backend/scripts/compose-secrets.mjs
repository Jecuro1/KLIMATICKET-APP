#!/usr/bin/env node
// Builds the Worker secrets for `wrangler deploy --secrets-file` from GitHub secrets (docs/CLOUDFLARE_BACKEND.md
// §5.1 step 7, §5.4). Secret VALUES are never printed.
//
// Inputs (env):
//   GOOGLE_CLIENT_ID … APPLE_BUNDLE_ID   the 9 managed provider secrets (empty = not configured)
//   EXISTING_SECRETS_FILE                 response body of GET /accounts/{id}/workers/scripts/{name}/secrets
//                                         (Cloudflare envelope) or `wrangler secret list --format json` output
//   EXISTING_SECRETS_STATUS               HTTP status of that request (default 200). 404 + error code 10007
//                                         ("Worker not found") = first deploy; any other failure aborts, because
//                                         guessing "no secrets" would rotate SESSION_SIGNING_KEY and sign everyone out.
//   SECRETS_FILE                          output, default $RUNNER_TEMP/kb-secrets.json (mode 600)
//   STALE_FILE                            output, default $RUNNER_TEMP/kb-stale.json (mode 600; only written if needed)
//   BACKEND_KEEP_WORKER_SECRETS           "true" = never delete provider secrets that exist only on the Worker
//   GITHUB_OUTPUT                         if set: secret_count, stale_count, generated_key, first_deploy
// Plain Node ≥ 22, no dependencies. Self-test: node --test scripts/*.selftest.mjs
import { randomBytes } from "node:crypto";
import { appendFileSync, chmodSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const SIGNING_KEY = "SESSION_SIGNING_KEY";

/** Provider secrets that CI manages (GitHub is the source of truth). `SESSION_SIGNING_KEY*` is never touched. */
export const MANAGED_SECRETS = [
  "GOOGLE_CLIENT_ID",
  "GOOGLE_CLIENT_SECRET",
  "MICROSOFT_CLIENT_ID",
  "MICROSOFT_CLIENT_SECRET",
  "APPLE_SERVICES_ID",
  "APPLE_TEAM_ID",
  "APPLE_KEY_ID",
  "APPLE_PRIVATE_KEY",
  "APPLE_BUNDLE_ID",
];

/** Secrets that together enable one login (contract §2.2). Used only for warnings about half-configured providers. */
export const PROVIDER_GROUPS = [
  { label: "Google", names: ["GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"] },
  { label: "Microsoft", names: ["MICROSOFT_CLIENT_ID", "MICROSOFT_CLIENT_SECRET"] },
  { label: "Apple (Web)", names: ["APPLE_SERVICES_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY"] },
];

const WORKER_NOT_FOUND_CODES = new Set([10007, 10090]);

export class ComposeError extends Error {}

/**
 * Interprets the "list secrets" answer. Returns `{ names: Set<string>, firstDeploy: boolean }` or throws ComposeError.
 * @param {number} status
 * @param {string} body
 */
export function parseExistingSecrets(status, body) {
  let parsed;
  try {
    parsed = body.trim() === "" ? undefined : JSON.parse(body);
  } catch {
    parsed = undefined;
  }
  if (status === 200) {
    const list = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.result) ? parsed.result : undefined;
    if (!list || (parsed && !Array.isArray(parsed) && parsed.success === false)) {
      throw new ComposeError("unexpected answer while listing the Worker secrets (no result array)");
    }
    const names = new Set();
    for (const entry of list) {
      if (typeof entry?.name !== "string") throw new ComposeError("unexpected secret entry without a name");
      names.add(entry.name);
    }
    return { names, firstDeploy: false };
  }
  const errors = Array.isArray(parsed?.errors) ? parsed.errors : [];
  if (status === 404 && errors.some((e) => WORKER_NOT_FOUND_CODES.has(Number(e?.code)))) {
    return { names: new Set(), firstDeploy: true };
  }
  const detail = errors
    .map((e) => `${Number(e?.code) || "?"}: ${String(e?.message ?? "").slice(0, 200)}`)
    .join("; ");
  throw new ComposeError(`listing the Worker secrets failed (HTTP ${status}${detail ? `, ${detail}` : ""})`);
}

/** Light sanity check of the .p8 content (warning only; the Worker does the real parsing, contract §2.9). */
export function looksLikeP8(value) {
  const body = value
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) [A-Z ]*PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  return body.length >= 100 && /^[A-Za-z0-9+/]+={0,2}$/.test(body);
}

/**
 * Pure composition. Returns `{ secrets, stale, generatedKey, warnings }`.
 * @param {{ env: Record<string,string|undefined>, existing: Set<string>, keepWorkerSecrets?: boolean,
 *           generateKey?: () => string }} input
 */
export function composeSecrets({ env, existing, keepWorkerSecrets = false, generateKey = defaultKey }) {
  const value = (name) => (typeof env[name] === "string" ? env[name].trim() : "");
  const secrets = {};
  const stale = {};
  const warnings = [];
  for (const name of MANAGED_SECRETS) {
    const v = value(name);
    if (v !== "") secrets[name] = v;
    else if (existing.has(name) && !keepWorkerSecrets) stale[name] = null;
  }
  let generatedKey = false;
  if (!existing.has(SIGNING_KEY)) {
    const key = generateKey();
    if (typeof key !== "string" || key.length < 32) throw new ComposeError("generated signing key is too short");
    secrets[SIGNING_KEY] = key;
    generatedKey = true;
  }
  for (const group of PROVIDER_GROUPS) {
    const missing = group.names.filter((n) => value(n) === "");
    if (missing.length > 0 && missing.length < group.names.length) {
      warnings.push(`${group.label}: ${missing.join(", ")} fehlt – diese Anmeldung bleibt deaktiviert.`);
    }
  }
  if (value("APPLE_PRIVATE_KEY") !== "" && !looksLikeP8(value("APPLE_PRIVATE_KEY"))) {
    warnings.push(
      "APPLE_PRIVATE_KEY sieht nicht wie der Inhalt einer .p8-Datei aus (den ganzen Dateiinhalt inkl. BEGIN/END-Zeilen einfügen).",
    );
  }
  return { secrets, stale, generatedKey, warnings };
}

function defaultKey() {
  return randomBytes(48).toString("base64url"); // 64 chars, ≥ 32 required by the Worker (contract §2.7)
}

function writePrivate(file, data) {
  writeFileSync(file, data, { mode: 0o600 });
  chmodSync(file, 0o600); // mode only applies on create
}

export function main(env = process.env) {
  const tmp = env.RUNNER_TEMP || process.cwd();
  const secretsFile = env.SECRETS_FILE || path.join(tmp, "kb-secrets.json");
  const staleFile = env.STALE_FILE || path.join(tmp, "kb-stale.json");
  if (!env.EXISTING_SECRETS_FILE) throw new ComposeError("EXISTING_SECRETS_FILE is not set");
  const status = Number(env.EXISTING_SECRETS_STATUS || "200");
  const { names, firstDeploy } = parseExistingSecrets(status, readFileSync(env.EXISTING_SECRETS_FILE, "utf8"));
  const keepWorkerSecrets = String(env.BACKEND_KEEP_WORKER_SECRETS || "").trim().toLowerCase() === "true";
  const result = composeSecrets({ env, existing: names, keepWorkerSecrets });

  // Mask before anything else is printed (the runner hides the value in all later log lines).
  if (result.generatedKey) console.log(`::add-mask::${result.secrets[SIGNING_KEY]}`);

  writePrivate(secretsFile, JSON.stringify(result.secrets));
  const staleNames = Object.keys(result.stale);
  if (staleNames.length > 0) writePrivate(staleFile, JSON.stringify(result.stale));
  else rmSync(staleFile, { force: true });

  const setNames = Object.keys(result.secrets);
  console.log(firstDeploy ? "Worker existiert noch nicht – erster Deploy." : `Worker-Secrets vorhanden: ${[...names].sort().join(", ") || "–"}`);
  console.log(`Wird gesetzt: ${setNames.join(", ") || "–"}`);
  console.log(
    keepWorkerSecrets
      ? "Aufräumen übersprungen (BACKEND_KEEP_WORKER_SECRETS=true)."
      : `Wird entfernt (in GitHub gelöscht): ${staleNames.join(", ") || "–"}`,
  );
  if (result.generatedKey) console.log(`${SIGNING_KEY} wurde neu erzeugt (nur beim ersten Deploy).`);
  for (const warning of result.warnings) console.log(`::warning title=Backend-Secrets::${warning}`);

  if (env.GITHUB_OUTPUT) {
    appendFileSync(
      env.GITHUB_OUTPUT,
      [
        `secret_count=${setNames.length}`,
        `stale_count=${staleNames.length}`,
        `generated_key=${result.generatedKey}`,
        `first_deploy=${firstDeploy}`,
        "",
      ].join("\n"),
    );
  }
  return result;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    main();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.log(`::error title=Backend-Secrets::${message}`);
    process.exitCode = 1;
  }
}
