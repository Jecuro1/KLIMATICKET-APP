#!/usr/bin/env node
// Picks one D1 database from `wrangler d1 list --json` output (docs/CLOUDFLARE_BACKEND.md §5.1 step 4).
//
// Usage: npx wrangler d1 list --json | node scripts/find-d1.mjs <name>
// Prints `uuid=<id>` and `jurisdiction=<eu|…|>` (GitHub output format) and exits 0 when found,
// prints nothing and exits 2 when there is no database with that name, exits 1 on unreadable input.
// Plain Node ≥ 22, no dependencies. Self-test: node --test scripts/*.selftest.mjs
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Parses the listing; tolerates log lines around the JSON array (wrangler banners or warnings). */
export function parseListing(text) {
  try {
    return asArray(JSON.parse(text));
  } catch {
    const end = text.lastIndexOf("]");
    for (const match of text.matchAll(/^[ \t]*\[/gm)) {
      try {
        return asArray(JSON.parse(text.slice(match.index, end + 1)));
      } catch {
        // try the next line that starts with "["
      }
    }
    throw new Error("no JSON array in the D1 listing");
  }
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  if (Array.isArray(value?.result)) return value.result; // raw Cloudflare API envelope
  throw new Error("the D1 listing is not an array");
}

/** Returns `{ uuid, jurisdiction }` (jurisdiction `null` when the listing has no such field) or `null`. */
export function findDatabase(list, name) {
  const matches = list.filter((db) => db?.name === name);
  if (matches.length === 0) return null;
  const db = matches[0];
  if (typeof db.uuid !== "string" || !UUID.test(db.uuid)) throw new Error(`database "${name}" has no valid uuid`);
  const jurisdiction = typeof db.jurisdiction === "string" && db.jurisdiction !== "" ? db.jurisdiction : null;
  return { uuid: db.uuid.toLowerCase(), jurisdiction };
}

export function main(argv = process.argv.slice(2), input = () => readFileSync(0, "utf8")) {
  const name = argv[0];
  if (!name) {
    console.error("usage: find-d1.mjs <database-name>  (listing on stdin)");
    return 1;
  }
  const found = findDatabase(parseListing(input()), name);
  if (!found) return 2;
  console.log(`uuid=${found.uuid}`);
  console.log(`jurisdiction=${found.jurisdiction ?? ""}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`find-d1: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}
