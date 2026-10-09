#!/usr/bin/env bash
# End-to-end test of the KlimaCloud Swift client against the real Worker (`wrangler dev`, local D1).
#   Packages/KlimaCloud/E2E/run-e2e.sh            (needs node ≥ 22 and the Swift toolchain; runs `npm ci` if needed)
# Starts the Worker on 127.0.0.1:$PORT with a throwaway signing key and dummy Google credentials (so Google counts as
# enabled), applies the migrations to a temporary D1, seeds users + one-time codes (seed.mjs), then runs the Swift
# tests with KLIMACLOUD_E2E_URL set (E2ETests.swift; skipped in normal runs).
set -euo pipefail
E2E=$(cd "$(dirname "$0")" && pwd)
PKG=$(cd "$E2E/.." && pwd)
BACKEND=$(cd "$PKG/../../backend" && pwd)
PORT=${PORT:-8787}
WORK=$(mktemp -d)
cleanup() {
  # wrangler starts workerd children: stop the whole process group.
  if [ -n "${WRANGLER_PID:-}" ]; then kill -- -"$WRANGLER_PID" 2>/dev/null || kill "$WRANGLER_PID" 2>/dev/null || true; fi
  wait 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
export WRANGLER_SEND_METRICS=false CI=1

if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null || (exec 3<>/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null; then
  echo "Port $PORT is in use – stop the other server or set PORT=…" >&2
  exit 1
fi

cd "$BACKEND"
[ -d node_modules ] || npm ci --no-audit --no-fund
cat > "$WORK/e2e.env" <<VARS
SESSION_SIGNING_KEY=$(node -e 'console.log(require("crypto").randomBytes(48).toString("base64url"))')
GOOGLE_CLIENT_ID=e2e-google-client.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=e2e-google-secret
VARS
npx wrangler d1 migrations apply DB --local -c wrangler.template.toml --persist-to "$WORK/state" >"$WORK/migrate.log" 2>&1 \
  || { cat "$WORK/migrate.log"; exit 1; }
node "$E2E/seed.mjs" "$WORK/seed.sql" "$WORK/seed.json"
npx wrangler d1 execute DB --local -c wrangler.template.toml --persist-to "$WORK/state" --file "$WORK/seed.sql" >"$WORK/seed.log" 2>&1 \
  || { cat "$WORK/seed.log"; exit 1; }

setsid npx wrangler dev -c wrangler.template.toml --local --ip 127.0.0.1 --port "$PORT" --persist-to "$WORK/state" \
  --env-file "$WORK/e2e.env" --show-interactive-dev-session=false >"$WORK/wrangler.log" 2>&1 &
WRANGLER_PID=$!
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$PORT/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:$PORT/v1/health" >/dev/null || { cat "$WORK/wrangler.log"; exit 1; }
echo "Worker up on :$PORT – config: $(curl -fsS "http://127.0.0.1:$PORT/v1/config")"

cd "$PKG"
status=0
KLIMACLOUD_E2E_URL="http://127.0.0.1:$PORT" KLIMACLOUD_E2E_SEED="$WORK/seed.json" \
  swift test --no-parallel --filter E2ETests 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' | tail -${TAIL:-60} || status=$?
[ "${KEEP_LOG:-}" = 1 ] && cp "$WORK/wrangler.log" "${TMPDIR:-/tmp}/klimacloud-e2e-wrangler.log"
exit $status
