// Seeds the local D1 of `wrangler dev` for the KlimaCloud end-to-end tests (no provider round trip needed):
// two users with a Google identity each, plus one-time app codes (as the /callback route would issue them) whose
// PKCE verifiers the Swift tests redeem through POST /v1/auth/token.
// Usage: node seed.mjs <out.sql> <out.json>
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { writeFileSync } from "node:fs";

const [sqlPath, jsonPath] = process.argv.slice(2);
const b64url = (buf) => Buffer.from(buf).toString("base64url");
const sha = (s) => b64url(createHash("sha256").update(s).digest());
const q = (s) => (s === null ? "NULL" : `'${String(s).replaceAll("'", "''")}'`);
const now = Date.now();
const redirect = "klimabilanz://auth-callback";

const users = { one: randomUUID(), two: randomUUID(), three: randomUUID() };
const sql = [];
for (const [name, id] of Object.entries(users)) {
  sql.push(`INSERT INTO users (id, created_at, last_login_at) VALUES (${q(id)}, ${now}, ${now});`);
  sql.push(`INSERT INTO identities (provider, subject, user_id, email, email_verified, created_at, last_login_at) VALUES ('google', ${q("e2e-" + id)}, ${q(id)}, ${q(name + "@e2e.test")}, 1, ${now}, ${now});`);
  sql.push(`INSERT INTO profiles (user_id, display_name, avatar_url, created_at, updated_at) VALUES (${q(id)}, ${q("E2E " + name)}, NULL, ${now}, ${now});`);
}
const codes = {};
const plan = { main: "one", reuse: "one", rotation: "one", logout: "one", coordinator: "one", sync: "one", other: "two", delete: "three" };
for (const [label, who] of Object.entries(plan)) {
  const code = b64url(randomBytes(32));
  const verifier = b64url(randomBytes(48));
  codes[label] = { code, verifier, user: users[who] };
  sql.push(`INSERT INTO auth_codes (code_hash, user_id, provider, subject, code_challenge, redirect_uri, created_at, expires_at) VALUES (${q(sha(code))}, ${q(users[who])}, 'google', ${q("e2e-" + users[who])}, ${q(sha(verifier))}, ${q(redirect)}, ${now}, ${now + 3_600_000});`);
}
writeFileSync(sqlPath, sql.join("\n") + "\n");
writeFileSync(jsonPath, JSON.stringify({ users, codes, redirect }, null, 2));
