# backend/scripts (WP-D)

Deploy helpers used by `.github/workflows/backend.yml` (docs/CLOUDFLARE_BACKEND.md §5). Plain Node ≥ 22, no
dependencies, run from `backend/`.

| Script | Step | What it does |
|---|---|---|
| `find-d1.mjs <name>` | 4 | Reads `wrangler d1 list --json` on stdin, prints `uuid=…` / `jurisdiction=…` (exit 0), or exits 2 if there is no database with that name. |
| `render-wrangler-config.mjs` | 5 | Renders `wrangler.template.toml` → `wrangler.toml` (git-ignored): every `key = "…" # @render NAME` line gets `$NAME` if set (validated: D1 UUID, https origin, `x.y.z`). Fails if `database_id` is still the placeholder. |
| `compose-secrets.mjs` | 7 | Turns the GitHub secrets into `$RUNNER_TEMP/kb-secrets.json` for `wrangler deploy --secrets-file` (only non-empty ones, plus a one-time `SESSION_SIGNING_KEY`), and `kb-stale.json` (`null` = delete) for provider secrets that were deleted in GitHub. Both files are mode 600; values are never printed. |

`compose-secrets.mjs` reads the Worker's current secret *names* from
`GET /accounts/{id}/workers/scripts/klimabilanz-api/secrets`. Only "404 + error code 10007" counts as "the Worker does
not exist yet"; every other failure aborts the deploy, because assuming "no secrets" would generate a new
`SESSION_SIGNING_KEY` and sign every user out.

Self-tests: `node --test scripts/*.selftest.mjs` (the test job runs them). They are deliberately **not** named
`*.test.mjs`: vitest's default include pattern would pick those up and run them inside workerd.

Local try-out of the renderer (no Cloudflare account needed):

```bash
cd backend
D1_DATABASE_ID=3f2c8a9e-1b7d-4c55-9e0a-6d1f2b3c4d5e PUBLIC_BASE_URL=https://klimabilanz-api.example.workers.dev \
  node scripts/render-wrangler-config.mjs --out /tmp/wrangler.toml && cat /tmp/wrangler.toml
```
