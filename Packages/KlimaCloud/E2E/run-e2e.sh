#!/usr/bin/env bash
# End-to-end test of the KlimaCloud Swift client against the real Worker (`wrangler dev`, local D1).
#   Packages/KlimaCloud/E2E/run-e2e.sh            (needs node ≥ 22 and the Swift toolchain; runs `npm ci` if needed)
# 1. Starts a fake OIDC server (fake-oidc.mjs: Google, Microsoft, Apple with real RS256 JWKS and an ES256-checked Apple
#    client secret) on 127.0.0.1:$FAKE_PORT.
# 2. Starts the Worker on 127.0.0.1:$PORT through the e2e entry backend/test/e2e/worker.ts (production handler; only the
#    provider hosts are rewritten to the fake) with a throwaway signing key and provider credentials for all three web
#    sign-ins, applies the migrations to a temporary D1 and seeds users + one-time codes (seed.mjs).
# 3. Runs the Swift e2e tests (E2ETests.swift: seeded codes; FullFlowE2ETests.swift: complete browser sign-ins through
#    the fake providers, two devices, 1 200 rows, stale writes, account switch, account deletion). Skipped in normal runs.
set -euo pipefail
E2E=$(cd "$(dirname "$0")" && pwd)
PKG=$(cd "$E2E/.." && pwd)
BACKEND=$(cd "$PKG/../../backend" && pwd)
PORT=${PORT:-8787}
FAKE_PORT=${FAKE_PORT:-8790}
WORK=$(mktemp -d)
cleanup() {
  # wrangler starts workerd children: stop the whole process group.
  if [ -n "${WRANGLER_PID:-}" ]; then kill -- -"$WRANGLER_PID" 2>/dev/null || kill "$WRANGLER_PID" 2>/dev/null || true; fi
  if [ -n "${FAKE_PID:-}" ]; then kill "$FAKE_PID" 2>/dev/null || true; fi
  wait 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
export WRANGLER_SEND_METRICS=false CI=1
# Local traffic (Swift → Worker, Worker → fake provider) must never go through an HTTP(S) proxy.
export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}" no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"

for p in "$PORT" "$FAKE_PORT"; do
  if (exec 3<>/dev/tcp/127.0.0.1/"$p") 2>/dev/null; then
    echo "Port $p is in use – stop the other server or set PORT=… / FAKE_PORT=…" >&2
    exit 1
  fi
done

cd "$BACKEND"
[ -d node_modules ] || npm ci --no-audit --no-fund

# Throwaway credentials: an Apple P-256 key (private key for the Worker, public key for the fake) and dummy client ids.
node - "$WORK" "$PORT" "$FAKE_PORT" <<'NODE'
const { generateKeyPairSync, randomBytes } = require("node:crypto");
const { writeFileSync } = require("node:fs");
const [work, port, fakePort] = process.argv.slice(2);
const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const der = privateKey.export({ format: "der", type: "pkcs8" }).toString("base64"); // bare base64 body (accepted, §2.9)
const cfg = {
  worker: `http://127.0.0.1:${port}`,
  google: { client_id: "e2e-google-client.apps.googleusercontent.com", client_secret: "e2e-google-secret" },
  microsoft: { client_id: "6731de76-14a6-49ae-97bc-6eba6914391e", client_secret: "e2e-microsoft-secret",
               tenant: "9188040d-6c67-4c5b-b112-36a304b66dad" },
  apple: { services_id: "com.knitelarlberg.klimabilanz.web", team_id: "E2ETEAM123", key_id: "E2EKEY1234",
           public_key_pem: publicKey.export({ format: "pem", type: "spki" }) },
};
writeFileSync(`${work}/fake-oidc.json`, JSON.stringify(cfg, null, 2));
writeFileSync(`${work}/e2e.env`, [
  `SESSION_SIGNING_KEY=${randomBytes(48).toString("base64url")}`,
  `GOOGLE_CLIENT_ID=${cfg.google.client_id}`,
  `GOOGLE_CLIENT_SECRET=${cfg.google.client_secret}`,
  `MICROSOFT_CLIENT_ID=${cfg.microsoft.client_id}`,
  `MICROSOFT_CLIENT_SECRET=${cfg.microsoft.client_secret}`,
  `APPLE_SERVICES_ID=${cfg.apple.services_id}`,
  `APPLE_TEAM_ID=${cfg.apple.team_id}`,
  `APPLE_KEY_ID=${cfg.apple.key_id}`,
  `APPLE_PRIVATE_KEY=${der}`,
  `E2E_FAKE_OIDC_URL=http://127.0.0.1:${fakePort}`,
  "",
].join("\n"));
NODE

node "$E2E/fake-oidc.mjs" "$FAKE_PORT" "$WORK/fake-oidc.json" >"$WORK/fake-oidc.log" 2>&1 &
FAKE_PID=$!

npx wrangler d1 migrations apply DB --local -c wrangler.template.toml --persist-to "$WORK/state" >"$WORK/migrate.log" 2>&1 \
  || { cat "$WORK/migrate.log"; exit 1; }
node "$E2E/seed.mjs" "$WORK/seed.sql" "$WORK/seed.json"
npx wrangler d1 execute DB --local -c wrangler.template.toml --persist-to "$WORK/state" --file "$WORK/seed.sql" >"$WORK/seed.log" 2>&1 \
  || { cat "$WORK/seed.log"; exit 1; }

setsid npx wrangler dev test/e2e/worker.ts -c wrangler.template.toml --local --ip 127.0.0.1 --port "$PORT" \
  --persist-to "$WORK/state" --env-file "$WORK/e2e.env" --show-interactive-dev-session=false >"$WORK/wrangler.log" 2>&1 &
WRANGLER_PID=$!
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$PORT/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:$PORT/v1/health" >/dev/null || { cat "$WORK/wrangler.log"; exit 1; }
curl -fsS "http://127.0.0.1:$FAKE_PORT/__calls" >/dev/null || { cat "$WORK/fake-oidc.log"; exit 1; }
echo "Worker up on :$PORT, fake OIDC on :$FAKE_PORT – config: $(curl -fsS "http://127.0.0.1:$PORT/v1/config")"

cd "$PKG"
status=0
KLIMACLOUD_E2E_URL="http://127.0.0.1:$PORT" KLIMACLOUD_E2E_SEED="$WORK/seed.json" \
  KLIMACLOUD_E2E_FAKE_OIDC="http://127.0.0.1:$FAKE_PORT" \
  swift test --no-parallel --filter "${FILTER:-E2ETests}" 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' | tail -"${TAIL:-80}" || status=$?
# (pipefail: a failing `swift test` sets status even though grep/tail succeed)
if [ "${KEEP_LOG:-}" = 1 ]; then
  cp "$WORK/wrangler.log" "${TMPDIR:-/tmp}/klimacloud-e2e-wrangler.log"
  cp "$WORK/fake-oidc.log" "${TMPDIR:-/tmp}/klimacloud-e2e-fake-oidc.log"
fi
exit $status
