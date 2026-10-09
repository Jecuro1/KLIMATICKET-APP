# backend/scripts (WP-D)

Deploy helpers used by `.github/workflows/backend.yml` (docs/CLOUDFLARE_BACKEND.md §5):

- `render-wrangler-config.mjs`: renders `wrangler.template.toml` → `wrangler.toml` (`# @render NAME` lines).
- `compose-secrets.mjs`: builds the Worker secrets file from GitHub secrets (+ one-time `SESSION_SIGNING_KEY`).

Plain Node ≥ 22, no dependencies, self-tests via `node --test scripts/`.
