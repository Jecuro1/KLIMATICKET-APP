#!/usr/bin/env node
// Renders wrangler.template.toml → wrangler.toml for CI deploys (docs/CLOUDFLARE_BACKEND.md §5.1 step 5, §5.3).
//
// Every line that ends in `# @render NAME` and has the form `key = "value" # @render NAME` gets its quoted value
// replaced by the environment variable NAME when that variable is set and non-empty. Lines without a marker are
// copied verbatim. The rendered file is git-ignored and never uploaded as an artifact.
//
// Usage (from backend/):  node scripts/render-wrangler-config.mjs [--in FILE] [--out FILE] [--allow-placeholder]
// Env:                    D1_DATABASE_ID, PUBLIC_BASE_URL, MIN_APP_VERSION (+ any other NAME used by a marker)
// Plain Node ≥ 22, no dependencies. Self-test: node --test scripts/*.selftest.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const PLACEHOLDER_DATABASE_ID = "00000000-0000-0000-0000-000000000000";

const MARKER = /#\s*@render\s+([A-Z][A-Z0-9_]*)\s*$/;
// key = "basic string" # @render NAME   (TOML basic string; escapes allowed inside)
const VALUE_LINE = /^(\s*[A-Za-z0-9_.-]+\s*=\s*)"((?:[^"\\]|\\.)*)"(\s*#.*)$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VERSION = /^\d{1,6}(\.\d{1,6}){0,2}$/;
const CONTROL = /[\u0000-\u001f\u007f]/;

/** `https://host[:port]` without path, query, fragment or credentials (a trailing `/` is tolerated by callers). */
export function isHttpsOrigin(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  return (
    url.protocol === "https:" &&
    url.hostname !== "" &&
    url.username === "" &&
    url.password === "" &&
    (url.pathname === "/" || url.pathname === "") &&
    url.search === "" &&
    url.hash === "" &&
    !value.includes("?") &&
    !value.includes("#") &&
    /^https:\/\/[^/]+\/?$/i.test(value)
  );
}

/** Normalizes a value before validation (only PUBLIC_BASE_URL has a normalization: no trailing slash). */
function normalize(name, value) {
  const trimmed = value.trim();
  return name === "PUBLIC_BASE_URL" ? trimmed.replace(/\/+$/, "") : trimmed;
}

const VALIDATORS = {
  D1_DATABASE_ID: (v) => UUID.test(v) || "must be a D1 database UUID",
  PUBLIC_BASE_URL: (v) => isHttpsOrigin(v) || "must be an https:// origin without path, query or fragment",
  MIN_APP_VERSION: (v) => VERSION.test(v) || "must look like 1.2.3",
};

function tomlEscape(value) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

/**
 * Pure renderer. Returns `{ text, applied, kept, errors }`; `errors` non-empty means the caller MUST NOT write the file.
 * @param {string} template
 * @param {Record<string, string | undefined>} env
 * @param {{ allowPlaceholder?: boolean }} [options]
 */
export function renderTemplate(template, env, { allowPlaceholder = false } = {}) {
  const lines = template.split("\n");
  const out = [];
  const applied = [];
  const kept = [];
  const errors = [];
  lines.forEach((line, index) => {
    const marker = line.match(MARKER);
    if (!marker) {
      out.push(line);
      return;
    }
    const name = marker[1];
    const parts = line.match(VALUE_LINE);
    if (!parts) {
      errors.push(`line ${index + 1}: "# @render ${name}" needs the form key = "value" # @render ${name}`);
      out.push(line);
      return;
    }
    const raw = env[name];
    const value = typeof raw === "string" ? normalize(name, raw) : "";
    if (value === "") {
      kept.push(name);
      out.push(line);
      return;
    }
    if (CONTROL.test(value)) {
      errors.push(`${name} must not contain control characters`);
      out.push(line);
      return;
    }
    const verdict = VALIDATORS[name]?.(value);
    if (typeof verdict === "string") {
      errors.push(`${name} ${verdict}`);
      out.push(line);
      return;
    }
    out.push(`${parts[1]}"${tomlEscape(value)}"${parts[3]}`);
    applied.push(name);
  });
  const text = out.join("\n");
  if (!allowPlaceholder) {
    const placeholder = /^\s*database_id\s*=\s*"0{8}-0{4}-0{4}-0{4}-0{12}"/m;
    if (placeholder.test(text)) errors.push("database_id is still the placeholder – set D1_DATABASE_ID");
  }
  return { text, applied, kept, errors };
}

function parseArgs(argv) {
  const args = { in: "wrangler.template.toml", out: "wrangler.toml", allowPlaceholder: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--in") args.in = argv[++i];
    else if (arg === "--out") args.out = argv[++i];
    else if (arg === "--allow-placeholder") args.allowPlaceholder = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (!args.in || !args.out) throw new Error("--in/--out need a file name");
  return args;
}

export function main(argv = process.argv.slice(2), env = process.env) {
  const args = parseArgs(argv);
  const template = readFileSync(args.in, "utf8");
  const { text, applied, kept, errors } = renderTemplate(template, env, { allowPlaceholder: args.allowPlaceholder });
  if (errors.length > 0) {
    for (const error of errors) console.log(`::error title=wrangler.toml::${error}`);
    return 1;
  }
  writeFileSync(args.out, text);
  console.log(`${args.out} rendered from ${args.in}.`);
  console.log(`  set from env:     ${applied.join(", ") || "–"}`);
  console.log(`  template default: ${kept.join(", ") || "–"}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.log(`::error title=wrangler.toml::${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}
