# KlimaBilanz Cloud Backend on Cloudflare: binding contract

> Status: **binding** for work packages WP-S (server), WP-D (deploy/docs) and WP-C (Swift client).
> Branch: `main` (trunk-based; developed on `wip/cloudflare`, merged). Copy: `docs/CLOUDFLARE_BACKEND.md`.
> Decision (user, 2026-10-09): *"dann nehme ich Cloudflare, da ich sowieso bereits bei Cloudflare bin"*, so
> Supabase is **removed completely**. The git history still has the Supabase backend (`supabase/`,
> `SupabaseClient.swift`, commits up to `0cb2acd`).
>
> Words: **MUST** / **MUST NOT** are binding. **SHOULD** means do it unless you write down why not. Anything this
> document leaves open is up to the owning work package, as long as it does not change an interface defined here.
> If you find a contradiction or a bug in this contract, do **not** silently diverge: fix it in your package in the
> way that keeps the interfaces in this document, and report it in your final message.

---

## 0. Summary

| Topic | Decision |
|---|---|
| Runtime | One Cloudflare Worker `klimabilanz-api` (TypeScript, ES modules, no framework, no runtime npm deps; WebCrypto only) |
| Database | D1 database `klimabilanz`, **EU jurisdiction** (`--jurisdiction eu`), binding `DB` |
| Public URL | `https://klimabilanz-api.<workers-subdomain>.workers.dev`, or repository variable `API_BASE_URL` (custom domain) |
| App ↔ Worker auth | OAuth 2.1-style authorization code + PKCE (S256), redirect `klimabilanz://auth-callback`, opened in `ASWebAuthenticationSession` |
| Worker ↔ provider | OIDC code flow with `state` + `nonce` (+ PKCE for Google/Microsoft): Google, Microsoft (`common`), Apple web (`form_post`). Native Sign in with Apple for signed builds |
| Sessions | Access token = HS256 JWT, 15 min, checked against the session row on every request. Refresh token = 256-bit random, stored hashed, single use, rotation with reuse detection, 60 days sliding |
| Accounts | Internal UUID; linked identities `(provider, subject)`; **no** automatic merge by e-mail |
| Sync | Same semantics as Supabase `0002_sync_hardening.sql`: user scoping from the token, monotonic `server_rev` (global counter, same batch), last writer wins on client `updated_at` with a 10-minute future clamp, echo-skip, soft deletes, immutable `id`/`user_id`/`created_at` |
| Deploy | `.github/workflows/backend.yml`: test, then find-or-create D1, migrate, set secrets, deploy, smoke test. Skips with a notice without `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` |
| App config | `AppConfig.apiBaseURL` (replaces `supabaseURL`/`supabaseAnonKey`); CI derives it from `vars.API_BASE_URL` or the Cloudflare API |
| Swift | New local package `Packages/KlimaCloud` (Foundation only, Linux-testable): HTTP client, DTOs, merge rule, timestamps, PKCE. The app keeps `AuthService`/`SyncService` with source-compatible public APIs |

Deliberate deviations from the task brief, with reasons:
1. **Deploy branches.** Tests run on every branch. *Deploys* run only on `main` (the old integration branch `claude/klimabilanz-ios-app` is still accepted), or a
   manual `workflow_dispatch`, because a WIP branch must not replace the production Worker that installed apps use (§5.1).
2. **snake_case everywhere.** The push response field is `server_rev`, not `serverRev`, to match every other field.
3. **No sync overlap window.** D1 runs batches one at a time in a single transaction, so a revision cursor needs no
   re-read window; the client's `pullOverlap` goes away (§3.7).

---

## 1. Repository layout and ownership

```
backend/                          WP-S (unless noted)
  package.json, package-lock.json   pinned devDependencies (see below); WP-S may add dev deps, never runtime deps
  .npmrc                             legacy-peer-deps=true (npm 10.9 crashes resolving vitest 4 optional peers)
  .gitignore                         node_modules, .wrangler, dist, wrangler.toml (rendered), .dev.vars
  tsconfig.json
  vitest.config.ts                   @cloudflare/vitest-plugin, migrations applied per test file
  wrangler.template.toml             committed config; CI renders wrangler.toml from it (WP-D only touches `# @render` values)
  src/                               Worker source (WP-S)
  migrations/0001_init.sql           D1 schema (§4), architect-written, WP-S owns from now on
  test/                              vitest tests (WP-S); test/fixtures/contract-rows.json is the shared wire fixture
  scripts/                           WP-D: render-wrangler-config.mjs, compose-secrets.mjs (deploy helpers)
Packages/KlimaCloud/              WP-C: Swift package (Linux-testable cloud core)
App/Sources/Services/…            WP-C
.github/workflows/backend.yml     WP-D (new)
.github/workflows/ios.yml         WP-D (config step, KlimaCloud test lines, remove SUPABASE_*)
scripts/write_app_config.py       WP-D
docs/SETUP.md, README.md, docs/ARCHITECTURE.md, other docs' Supabase mentions   WP-D
supabase/  (deleted)              WP-D
docs/CLOUDFLARE_BACKEND.md        architect (this file)
```

Pinned toolchain (checked in this container: `npm install` works through the proxy, the tests pass, `tsc` is clean):
`wrangler 4.141.0`, `vitest 4.1.11`, `@vitest/runner 4.1.11`, `@vitest/snapshot 4.1.11`,
`@cloudflare/vitest-plugin 1.2.8` (successor of `@cloudflare/vitest-pool-workers`; bundles wrangler 4.141.0),
`@cloudflare/workers-types 5.20260930.2`, `typescript 5.9.3`. Node ≥ 22.
Test facts: `import { env, exports } from "cloudflare:workers"`; `exports.default.fetch(req)` calls the Worker.
**D1 state is shared by all tests in one file** (there is no per-test rollback), so use fresh ids per test.
`test/contract-sql.test.ts` proves the SQL patterns of §3.6/§4 on D1 and MUST keep passing (WP-S may move the
assertions elsewhere).

---

## 2. Authentication

### 2.1 Overview

```
App                        Worker (klimabilanz-api)                       Provider (Google/Microsoft/Apple)
 │ verifier v, challenge c=S256(v), app_state s
 │── ASWebAuthenticationSession ─▶ GET /v1/auth/{p}/start?code_challenge=c&code_challenge_method=S256&state=s&redirect_uri=klimabilanz://auth-callback
 │                            store auth_flows{id=F, nonce N, provider PKCE pv, c, s}       
 │                            302 ─────────────────────────────────────────▶ authorize?state=F&nonce=N[&code_challenge=S256(pv)]
 │                                                                            user signs in
 │                            ◀──────── GET (Google/MS) or POST form_post (Apple) /v1/auth/{p}/callback?code=X&state=F
 │                            consume flow F (once), exchange X (+pv / client secret), verify id_token (JWKS, iss, aud, exp, nonce=N)
 │                            find-or-create user by identity (p, sub); issue one-time app code K (120 s, bound to c + redirect)
 │◀── 302 klimabilanz://auth-callback?code=K&state=s
 │ check state == s
 │── POST /v1/auth/token grant_type=authorization_code&code=K&code_verifier=v&redirect_uri=… ─▶ verify S256(v)==c → session
 │◀── { access_token (JWT 15 min), refresh_token (60 d sliding), user }
```

The app never sees provider tokens, and the Worker keeps no provider tokens except Apple's refresh token, which it
stores sealed so it can revoke it when the account is deleted (§2.9). No cookies are used anywhere. Flow state
lives in D1, so Apple's cross-site `form_post` works without SameSite issues.

### 2.2 Providers

| | Google | Microsoft | Apple (web) | Apple (native) |
|---|---|---|---|---|
| Enabled when these secrets exist | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET` | `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (and the key parses) | `APPLE_BUNDLE_ID` |
| Authorize | `https://accounts.google.com/o/oauth2/v2/auth` | `https://login.microsoftonline.com/common/oauth2/v2.0/authorize` | `https://appleid.apple.com/auth/authorize` | – |
| Token | `https://oauth2.googleapis.com/token` | `https://login.microsoftonline.com/common/oauth2/v2.0/token` | `https://appleid.apple.com/auth/token` | (optional code exchange, §2.9) |
| JWKS | `https://www.googleapis.com/oauth2/v3/certs` | `https://login.microsoftonline.com/common/discovery/v2.0/keys` | `https://appleid.apple.com/auth/keys` | same as web |
| Scope | `openid email profile` | `openid email profile` | `name email` | – |
| Extra params | `prompt=select_account`, `access_type=online`, PKCE S256 | `prompt=select_account`, `response_mode=query`, PKCE S256 | `response_mode=form_post` (no PKCE) | – |
| Callback method | GET | GET | **POST** `application/x-www-form-urlencoded` | – |
| `iss` | `https://accounts.google.com` or `accounts.google.com` | `https://login.microsoftonline.com/{tid}/v2.0`, where `tid` is the token's own `tid` claim and MUST be a GUID | `https://appleid.apple.com` | `https://appleid.apple.com` |
| `aud` | `GOOGLE_CLIENT_ID` | `MICROSOFT_CLIENT_ID` | `APPLE_SERVICES_ID` | `APPLE_BUNDLE_ID` |
| Subject | `sub` | `sub` (pairwise per app registration; stable for our single app) | `sub` (same for web and native under one Team ID) | `sub` |
| E-mail verified | `email_verified === true` | treat as **unverified** unless `xms_edov === true`; fall back to `preferred_username` for display only | `email_verified` (`true` or `"true"`) | same |
| Name | `name`, avatar `picture` | `name` | form field `user` (JSON, first authorization only, unsigned, display only) | request `full_name` (first authorization only) |

Provider redirect URI (MUST match what the user registers): `${PUBLIC_BASE_URL}/v1/auth/{provider}/callback`, where
`PUBLIC_BASE_URL` is the Worker var (rendered by CI) and, when it is empty, the request URL's origin. `{provider}` is
one of `google`, `microsoft`, `apple`.

Endpoints are hard-coded (no discovery fetch at runtime). Outbound provider calls use `AbortSignal.timeout(10_000)`.

### 2.3 Browser flow in detail

**`GET /v1/auth/{provider}/start`** (opened by `ASWebAuthenticationSession`, rate limit `auth_start`)
- Query: `code_challenge` (exactly 43 chars `[A-Za-z0-9_-]`), `code_challenge_method` (MUST be `S256`),
  `state` (16–256 chars `[A-Za-z0-9._~-]`), `redirect_uri` (MUST exactly equal one entry of `APP_REDIRECT_URIS`,
  default `klimabilanz://auth-callback`).
- If `redirect_uri` and `state` are valid, every error goes back to the app:
  `302 {redirect_uri}?error=<code>&error_description=<text>&state=<state>` (codes: `invalid_request`,
  `provider_disabled`, `rate_limited`, `server_error`). Otherwise the Worker answers `400` with the HTML error page (§2.10).
- Success: insert `auth_flows` (`id` = 32 random bytes base64url = provider `state`; `nonce` = 32 random bytes
  base64url; `provider_code_verifier` = 32 random bytes base64url for Google/Microsoft, NULL for Apple;
  `expires_at` = now + 10 min), then `302` to the provider authorize URL (§2.2) with `client_id`,
  `redirect_uri` (provider callback), `response_type=code`, `scope`, `state`, `nonce`, plus the provider extras.

**`GET|POST /v1/auth/{provider}/callback`** (rate limit `auth_callback`; GET for Google/Microsoft, POST form for Apple;
the other method → 405)
1. Read `state` (query or form). `DELETE FROM auth_flows WHERE id = ? RETURNING *`. If nothing comes back, the
   flow is expired, or its provider differs from the path, answer `400` with the HTML page "Die Anmeldung ist
   abgelaufen. Bitte starte sie in der App erneut." (no redirect: the app state is unknown).
2. If the provider sent `error` (Apple `user_cancelled_authorize`, Google/Microsoft `access_denied`, …), redirect to
   the app with `error=access_denied` (cancel) or `error=provider_error` plus a sanitized `error_description` (≤ 200
   chars, no control characters).
3. Exchange `code` at the token endpoint (form POST: `grant_type=authorization_code`, `code`, `redirect_uri`,
   `client_id`, `client_secret` (Apple: ES256 JWT, §2.9), `code_verifier` for Google/Microsoft; Microsoft also
   `scope`). Non-2xx, a missing `id_token`, or a timeout → app redirect `error=provider_error`.
4. Verify the `id_token` (§2.5) with `expected nonce = flow.nonce`. Failure → app redirect `error=invalid_id_token`.
   The `id_token` field in Apple's form post is **ignored**; only the one from the token endpoint counts.
5. Find-or-create the user (§2.6). Store Apple's `refresh_token` sealed (§2.9).
6. Create an app code: 32 random bytes base64url; store `auth_codes.code_hash = base64url(SHA-256(code))`,
   `code_challenge = flow.app_code_challenge`, `redirect_uri = flow.app_redirect_uri`, `expires_at = now + 120 s`.
7. Redirect: `302` (GET) or `303` (POST) `Location: {app_redirect_uri}?code=<code>&state=<app_state>`, plus a tiny
   HTML body with a "Zurück zur App" link (a fallback for when the redirect does not fire).

**`POST /v1/auth/token`** (rate limit `auth_token`). Body `application/x-www-form-urlencoded` (the app MUST send
this; the server MUST also accept `application/json` with the same fields).
- `grant_type=authorization_code`: `code`, `code_verifier` (43–128 chars `[A-Za-z0-9._~-]`), `redirect_uri`.
  - Look up by `code_hash`. Unknown or expired → `400 invalid_grant`.
  - Already used (`used_at` set) → revoke `session_id` (reason `code_reuse`) if set → `400 invalid_grant`.
  - Any redemption attempt consumes the code, so a PKCE or redirect mismatch also marks it used:
    `UPDATE auth_codes SET used_at=? WHERE code_hash=? AND used_at IS NULL`.
  - Check `base64url(SHA-256(code_verifier)) == code_challenge` (constant-time) and `redirect_uri` is an exact match.
    Mismatch → `400 invalid_grant`.
  - Success: create the session and its first refresh token in **one batch**. The writes MUST be guarded so that
    two concurrent redemptions cannot both succeed: `UPDATE auth_codes SET used_at=?, session_id=?sid WHERE code_hash=? AND used_at IS NULL`,
    then `INSERT INTO sessions … SELECT … WHERE EXISTS (SELECT 1 FROM auth_codes WHERE code_hash=? AND session_id=?sid)`,
    then insert the refresh token the same way. If the session insert's `meta.changes` is not 1 → `400 invalid_grant`.
- `grant_type=refresh_token`: `refresh_token`. See §2.7.
- Anything else → `400 unsupported_grant_type`. Success → `200` token response (§2.7.1).

**App side**: the callback URL MUST carry the same `state` the app generated (else the error
`stateMismatch`) – error redirects included, so a crafted link cannot show its own "provider" text in the app;
`error=access_denied` = the user cancelled (silent, no error text).

### 2.4 Native Sign in with Apple (signed builds only)

`POST /v1/auth/apple/native` (JSON, rate limit `auth_native`, `404 provider_disabled` without `APPLE_BUNDLE_ID`)
```json
{ "identity_token": "<JWT from ASAuthorizationAppleIDCredential.identityToken>",
  "raw_nonce": "<the raw nonce; the app set request.nonce = lowercase hex SHA-256(raw_nonce)>",
  "authorization_code": "<optional, credential.authorizationCode as UTF-8>",
  "full_name": "<optional, only on first authorization, ≤ 100 chars>" }
```
- Verify the identity token (§2.5) with `aud = APPLE_BUNDLE_ID` and `nonce == hex(SHA-256(raw_nonce))`.
- Replay protection: `INSERT INTO apple_native_nonces (nonce_hash, expires_at)` with `nonce_hash` = the token's
  `nonce` claim and `expires_at` = token `exp` (ms). A duplicate key → `400 invalid_grant`.
- Then find-or-create (§2.6) and create a session directly (no app code). `200` token response.
- With `authorization_code` present and the Apple key secrets configured, exchange it (client_id = `APPLE_BUNDLE_ID`)
  for a refresh token to seal (§2.9), best effort in `ctx.waitUntil`. A failure never fails the sign-in.

### 2.5 ID-token verification (all providers)

- A JWS compact JWT; header `alg` MUST be `RS256` (anything else, including `none`/`HS*`/missing `kid`, is rejected).
- The key comes from the provider JWKS by `kid` (`kty: RSA`), imported with `crypto.subtle.importKey("jwk", …, {name:"RSASSA-PKCS1-v1_5", hash:"SHA-256"})`.
- JWKS cache: module-level map per URL, TTL 6 h. On an unknown `kid`, refetch at most once per 60 s per URL.
  (The Cache API is not used: it does nothing on `*.workers.dev`.)
- Claims: `iss` and `aud` per §2.2 (`aud` may be a string or an array containing the client id; if it is an array
  with more than one entry, `azp` MUST equal the client id); `exp > now - 60 s`; `iat <= now + 60 s` and
  `iat >= now - 10 min`; `nbf` (if present) `<= now + 60 s`; `nonce` equals the expected value (constant-time); a
  non-empty `sub` of ≤ 255 chars.
- Strings taken from tokens are trimmed, have control characters stripped, and are length-capped (email 320,
  name 100, URL 2048, and `avatar_url` MUST start with `https://`).

### 2.6 Accounts and identities

- Lookup is **only** by `(provider, subject)`. The same e-mail at two providers gives two separate users. There is
  no automatic merge (account-takeover risk). Linking an existing account to a second provider is future work:
  `POST /v1/account/link` is reserved and not implemented.
- New identity: one batch of `INSERT users(id=crypto.randomUUID(), …)`, `INSERT identities … ON CONFLICT (provider, subject) DO NOTHING`,
  and `INSERT profiles (display_name = name ?? NULL, avatar_url)`. Then read the user id back via the identity. If
  two first logins race, the loser's `users` row is orphaned and removed by the cron (§3.10).
- Existing identity: update `identities.email/email_verified/last_login_at` and `users.last_login_at`. Fill the profile
  only where it is empty: `display_name = COALESCE(display_name, ?)`, `avatar_url = COALESCE(avatar_url, ?)`.
- User object (in the token response, `/v1/me` and `PATCH /v1/me`):
```json
{ "id": "0b9c6a4e-…", "email": "a@b.at", "email_verified": true, "display_name": "Marcel" , "avatar_url": null,
  "provider": "google", "created_at": "2026-10-09T12:00:00.000000Z" }
```
  `provider`, `email` and `email_verified` belong to the identity of the *current session* (`sessions.provider/subject`);
  `display_name` and `avatar_url` come from `profiles`; `created_at` is `users.created_at` in wire format.

### 2.7 Sessions and tokens

**Keys.** `SESSION_SIGNING_KEY` (secret, ≥ 32 chars, generated once by CI). If it is missing or too short, every
auth or authenticated endpoint answers `503 server_not_configured`, while `/v1/health` and `/v1/config` keep working
(and `config` reports all providers disabled). Sub-keys come from HKDF-SHA256 with `ikm` = the UTF-8 bytes of the
secret, `salt` = `"klimabilanz-api"`, and `info` per purpose: `"access-token-v1"` (HMAC-SHA256 key),
`"rate-limit-v1"` (HMAC key for hashing IPs and user ids), `"apple-token-seal-v1"` (AES-256-GCM key). CryptoKeys are
cached per isolate. Optional `SESSION_SIGNING_KEY_PREVIOUS` is accepted **only** to verify access tokens and to
unseal, never to sign. JWT `kid` = the first 8 chars of base64url(SHA-256(raw HMAC key)).

**Access token**: a JWT signed with HS256, header `{"alg":"HS256","typ":"JWT","kid":…}`, claims
`{"iss":"klimabilanz-api","aud":"klimabilanz-ios","sub":<user id>,"sid":<session id>,"iat":…,"exp":iat+900,"v":1}`.
Verification: exact `alg`, known `kid`, valid signature, `iss`, `aud`, `exp > now` (no leeway), `iat <= now + 60 s`.
**Every authenticated request** then runs
`SELECT 1 FROM sessions WHERE id = ?sid AND user_id = ?sub AND revoked_at IS NULL AND expires_at > ?now`. If there is
no row → `401 invalid_token`. Logout, reuse detection and account deletion therefore take effect immediately.

**Refresh token**: 32 random bytes base64url (43 chars), stored only as `token_hash = base64url(SHA-256(token))`,
with `expires_at = now + 60 d`. Every successful refresh also moves `sessions.expires_at` to now + 60 d (sliding).
There is no absolute cap. Rotation (`grant_type=refresh_token`):
1. Look up the token joined with its session. Unknown token, revoked session, expired session, or expired token → `400 invalid_grant`.
2. Token `revoked_at` is set → revoke the session (`refresh_reuse`) → `400 invalid_grant`.
3. Token unused (`used_at IS NULL`) → **rotate**: one batch of
   `UPDATE refresh_tokens SET used_at=?now, replaced_by=?new WHERE token_hash=?old AND used_at IS NULL`,
   `INSERT INTO refresh_tokens … SELECT … WHERE EXISTS (SELECT 1 FROM refresh_tokens WHERE token_hash=?old AND replaced_by=?new)`,
   and `UPDATE sessions SET last_refreshed_at=?now, expires_at=?now+60d WHERE id=?sid`. If the insert's
   `meta.changes` is not 1, a concurrent refresh won the race; continue with step 4.
4. Token already used:
   - **Grace (lost response):** if `now - used_at <= 60 s` and its successor (`replaced_by`) is neither used nor
     revoked, revoke the successor, issue a new successor from the old token (same guarded pattern, with
     `replaced_by` moved to the new hash) and answer `200`.
   - Otherwise this is **reuse**: revoke the whole session (`revoked_at`, `revoked_reason='refresh_reuse'`) and answer `400 invalid_grant`.
   - If a token that was revoked by a grace reissue comes back later, step 2 applies and the family is revoked.

**2.7.1 Token response** (`200`, both grants and native Apple):
```json
{ "access_token": "<jwt>", "token_type": "Bearer", "expires_in": 900,
  "refresh_token": "<43 chars>", "refresh_token_expires_in": 5184000, "user": { …user object… } }
```
`invalid_grant` is the **only** answer that means the session is dead. The client signs out to a local profile only
when it gets `400` + `{"error":"invalid_grant"}` + the `X-KB-API: 1` header (§3.1).

**Logout** `POST /v1/auth/logout` (rate limit `auth_logout`): form or JSON `refresh_token` and/or
`Authorization: Bearer <access token>`, even an expired one with a valid signature. It revokes that session
(`revoked_reason='logout'`); other devices stay signed in. It always answers `204`, even for unknown tokens.

### 2.8 Rate limiting (D1 fixed window, no Durable Objects)

`bucket = "<name>:" + base64url(HMAC(rate-limit key, subject))[0..22]`, where the subject is `CF-Connecting-IP` (or
`"unknown"`) or the user id. IPv6 addresses count per **/64** (`2001:db8:1:2::/64`; one subscriber gets a whole /64,
so per-address buckets would never fill), IPv4-mapped IPv6 as the IPv4 address. The upsert pattern is in `test/contract-sql.test.ts` (window = `floor(now / W) * W`).
Over the limit → `429 rate_limited` with `Retry-After` = seconds until the window ends; on `/start` and `/callback`
the app redirect carries `error=rate_limited` instead. If D1 fails, the limiter **fails open** (and logs).

| name | key | limit / window |
|---|---|---|
| `auth_start` | IP | 30 / 10 min |
| `auth_callback` | IP | 30 / 10 min |
| `auth_token` | IP | 120 / 10 min |
| `auth_native` | IP | 20 / 10 min |
| `auth_logout` | IP | 60 / 10 min |
| `account_delete` | user | 5 / 60 min |

Sync endpoints are not rate-limited: they need a valid session, and keeping them free of extra writes protects the
D1 free-tier write quota.

### 2.9 Apple specifics

- **Client secret**: an ES256 JWT created per request (cache it for ≤ 5 min), header `{alg:"ES256", kid: APPLE_KEY_ID}`,
  claims `{iss: APPLE_TEAM_ID, iat: now, exp: now+300, aud: "https://appleid.apple.com", sub: <client_id>}`, where
  `client_id` = `APPLE_SERVICES_ID` (web) or `APPLE_BUNDLE_ID` (native code exchange and revocation of native
  tokens). It is signed with `crypto.subtle.sign({name:"ECDSA", hash:"SHA-256"}, …)`, whose raw r‖s output already is
  the JWS format.
- **Private key parsing** (`APPLE_PRIVATE_KEY`): accept the whole `.p8` PEM (real newlines, `\n` escapes, CRLF), or the
  bare base64 body. Strip the header and footer lines and whitespace, base64-decode, and import as `pkcs8` with
  `{name:"ECDSA", namedCurve:"P-256"}`. If parsing fails, Apple web is disabled (`/v1/config`) and the error is logged
  once (never the key itself).
- **Token sealing**: AES-256-GCM with a random 12-byte IV; stored value = `base64url(iv ‖ ciphertext‖tag)` of the
  UTF-8 JSON `{"client_id":…,"refresh_token":…}` in `identities.provider_refresh_token`.
- **Revocation on account deletion**: for each Apple identity with a sealed token, POST
  `https://appleid.apple.com/auth/revoke` (`client_id`, `client_secret` for that client id, `token`,
  `token_type_hint=refresh_token`) in `ctx.waitUntil`, best effort, after the rows are deleted. (App Store guideline
  5.1.1(v) asks for token revocation.)

### 2.10 Browser / origin policy and headers

- No CORS, ever: there are no `Access-Control-*` headers, and `OPTIONS` on any path → `403 origin_not_allowed`.
- Every `/v1/*` endpoint except `/v1/auth/{p}/start` and `/v1/auth/{p}/callback` rejects requests that carry an
  `Origin` header → `403 origin_not_allowed`. Native `URLSession` sends none. `/v1/auth/apple/callback` (POST) allows
  `Origin` to be absent, `https://appleid.apple.com`, or `null`.
- All responses: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `X-KB-API: 1`, `X-Request-Id: <cf-ray or random>`, `Strict-Transport-Security: max-age=31536000`.
- HTML pages (errors and the callback fallback): German text, every interpolated value HTML-escaped,
  `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`.
- Logging (`console.log` → Workers Logs): request id, route, status, duration, error codes. **Never** log tokens,
  codes, verifiers, id_tokens, secrets, e-mails, names, IPs or row contents. The platform's invocation logs record
  request URLs, so `wrangler.template.toml` sets `observability.redact_query_string = true` (provider `code`/`state`
  on `/callback`, PKCE values on `/start`).

---

## 3. HTTP API

### 3.1 General rules

- Base: `${API_BASE_URL}` (no trailing slash). Path version prefix `/v1`. Additive changes stay on v1; breaking
  changes go to `/v2`, and v1 stays until `MIN_APP_VERSION` passes the last v1 app.
- Requests: JSON bodies need `Content-Type: application/json` (otherwise `415 unsupported_media_type`). The
  `token`/`logout` endpoints also accept `application/x-www-form-urlencoded`; the Apple callback accepts only that.
- Client headers: `Accept: application/json`, `Authorization: Bearer <access token>` (authenticated endpoints),
  `User-Agent: KlimaBilanz/<version> (<build>; iOS <version>)`, `X-KB-App-Version: <CFBundleShortVersionString>`.
- **Error body** (all endpoints, OAuth-compatible):
  `{"error":"<code>","error_description":"<English, for logs>","request_id":"…", …extra}`. The client shows German
  texts by code (§6.5) and never shows `error_description` raw, except a sanitized provider message.
- Status codes:

| status | `error` codes |
|---|---|
| 400 | `invalid_request`, `invalid_grant`, `unsupported_grant_type`, `unknown_table` |
| 401 | `invalid_token` (+ `WWW-Authenticate: Bearer error="invalid_token"`) |
| 403 | `origin_not_allowed` |
| 404 | `not_found`, `provider_disabled` |
| 405 | `method_not_allowed` (+ `Allow`) |
| 413 | `payload_too_large` |
| 415 | `unsupported_media_type` |
| 422 | `invalid_row` (`details:{index, field, reason}`), `unknown_field` (`details:{index, field}`), `too_many_rows`, `user_mismatch` |
| 426 | `upgrade_required` (+ `min_app_version`) |
| 429 | `rate_limited` (+ `Retry-After`) |
| 500 | `server_error` |
| 502 | `upstream_unavailable` (`/v1/ota/*` only: GitHub not reachable) |
| 503 | `server_not_configured` |

- Limits: body ≤ **1 048 576 bytes** on `/v1/sync/push`, ≤ 65 536 bytes elsewhere. Check `Content-Length` first,
  then the bytes actually read. Push ≤ **500 rows** per request; pull `limit` 1–500 (default 500).
- Version gate: on `/v1/sync/*` only, if `X-KB-App-Version` is present and parses as `major.minor.patch` (missing
  parts = 0) below `MIN_APP_VERSION` → `426 upgrade_required`. A missing or unparsable header is allowed.
- Idempotency: push is idempotent (last writer wins plus echo-skip), so clients retry freely and no idempotency key
  is needed. Token, logout and delete are safe to retry; a retried refresh hits the 60 s grace window (§2.7).
- Timeouts: Worker → provider 10 s; client → Worker 30 s (60 s for account deletion).
- D1: never enable read replication or the Sessions API. Every query goes to the primary, which the gap-free
  revision cursor needs (§3.7). A request MUST stay ≤ 20 D1 queries (free-plan limit is 50 per invocation, and batch
  statements may count individually).
- CPU (free plan, 10 ms): cache CryptoKeys, precompile regexes, and do not re-serialize rows needlessly.

### 3.2 Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/v1/health` | – | `200 {"ok":true}` if D1 answers (`SELECT server_rev FROM sync_state`), else `503 {"ok":false}` |
| GET | `/v1/config` | – | providers, versions, limits (§3.3) |
| GET | `/v1/auth/{provider}/start` | – | §2.3 |
| GET/POST | `/v1/auth/{provider}/callback` | – | §2.3 |
| POST | `/v1/auth/token` | – | §2.3 / §2.7 |
| POST | `/v1/auth/apple/native` | – | §2.4 |
| POST | `/v1/auth/logout` | refresh or bearer | §2.7 |
| GET | `/v1/me` | bearer | `200 {"user":{…},"identities":[{"provider":"google","email":"…"}]}` |
| PATCH | `/v1/me` | bearer | body `{"display_name": "…" | null}` (trimmed, 1–100 chars, or null to clear) → `200 {"user":{…}}` |
| POST | `/v1/account/delete` | bearer | §3.9 → `200 {"deleted":true}` |
| POST | `/v1/sync/push` | bearer | §3.6 |
| GET | `/v1/sync/pull` | bearer | §3.7 |
| GET | `/v1/udid` | – | Direct install: unsigned iOS „Profile Service“ `.mobileconfig` (asks for UDID + PRODUCT; nothing stays installed) |
| POST | `/v1/udid/callback` | – | iOS posts the device-signed plist → `301` to `/v1/udid/done?udid=…&product=…` (`400 invalid_request` without a UDID) |
| GET | `/v1/udid/done` | – | German page: the UDID, a copy button, the link to „Gerät registrieren“ (nonce CSP, no third-party resources) |
| GET/HEAD | `/v1/ota/{tag}/{file}` | – | Streams `manifest.plist`, `KlimaBilanz-<v>-adhoc.ipa`, `AppIcon-57.png`/`-512.png` of a GitHub release of `OTA_GITHUB_REPO` (default this repo) without GitHub's redirect; `latest` only for the manifest; `502 upstream_unavailable` if GitHub fails |

Unknown path → `404 not_found`; wrong method → `405`. The direct-install routes (`/v1/udid*`, `/v1/ota/*`) store
nothing and never touch D1; the UDID travels only in the redirect URL (Workers Logs strip query strings) – see
docs/DIREKT_INSTALLIEREN.md.

### 3.3 `GET /v1/config`

```json
{ "api_version": 1,
  "providers": { "google": {"web": true}, "microsoft": {"web": false}, "apple": {"web": true, "native": true} },
  "min_app_version": "1.0.0",
  "sync_tables": ["tickets", "trips", "favorite_routes", "benefits"],
  "features": ["trip_via", "trip_journey"],
  "limits": { "push_max_rows": 500, "pull_max_limit": 500, "max_body_bytes": 1048576 },
  "server_time": "2026-10-09T12:00:00.000000Z" }
```
All flags are `false` when `SESSION_SIGNING_KEY` is unusable. The app caches the last answer and hides the buttons of
disabled providers (§6.3).

`features` lists additive capabilities of this Worker + D1 (`backend/src/routes/meta.ts` › `FEATURES`). The app sends a
newer sync column only when its feature is listed – a Worker without the migration answers `422 unknown_field` – and
takes that column from pulled rows only then (`CloudConfig.supports`). Missing `features` (older Worker) = none.
`trip_via`: `via` on trips and favorite_routes (migration `0002_via.sql`, docs/VIA.md).
`trip_journey`: `journey_id` + `leg_index` on trips and `legs` on favorite_routes (migration `0003_journey.sql`,
docs/JOURNEYS.md).

### 3.4 Wire values

| Type | JSON on the wire | Server rules |
|---|---|---|
| uuid | string | `^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`, stored and returned **lowercase** |
| text(n) | string | ≤ n UTF-16 code units, no U+0000; stored verbatim (no trimming, no normalization) |
| real | number | finite, \|x\| ≤ 1e9; integers allowed (`1179` ≡ `1179.0`) |
| int | number | integer, −2³¹ … 2³¹−1 |
| bool | `true`/`false` | only JSON booleans (no 0/1); stored 0/1 |
| timestamp | string | RFC 3339 with an offset: `YYYY-MM-DD[T ]HH:MM[:SS[.fraction]](Z\|±HH[:]MM)`, years 1900–9999. Canonicalized to **`YYYY-MM-DDTHH:MM:SS.ffffffZ`** (UTC, exactly 6 digits, extra digits truncated). The **µs precision MUST survive** (JS `Date` has only ms, so carry the fraction separately) |

The Swift `APITimestamp` (formerly `PostgresTimestamp`) already writes exactly the canonical format.

### 3.5 Synced tables (columns = Swift DTOs = D1 schema)

"push" = key in push rows: **R** required, **O** optional (absent or `null` means the default; the nullable ones
are stored as NULL), **K** optional and kept (absent or `null` keeps the stored value, a new row gets the default – for
columns older apps do not know, so their edits never wipe them). Every row MAY also contain `user_id` (it MUST equal the token user, case-insensitive, else
`422 user_mismatch`) and `server_rev` (ignored). Any other key → `422 unknown_field`. Pull rows always contain
**every** column below plus `user_id` and `server_rev` (nullable columns as JSON `null`).

**tickets**: `id` uuid R · `product_id` text(100) R · `name` text(200) R · `variant` text(50) R · `family` text(50) R ·
`states` text(200) R · `price` real R · `start_date` timestamp R · `end_date` timestamp R · `holder_name` text(200) R ·
`ticket_number` text(100) R · `theme` text(50) R · `reminders` text(200) R · `is_monthly_payment` bool O (false) ·
`auto_renews` bool O (false) · `employer_contribution` real O (0) · `add_on_price` real O (0) · `add_ons` text(2000) O ('') ·
`created_at` timestamp R · `updated_at` timestamp R · `deleted_at` timestamp-or-null O (null)

**trips**: `id` uuid R · `date` timestamp R · `from_name` text(200) R · `to_name` text(200) R · `from_station_id` text(100)-or-null O ·
`to_station_id` text(100)-or-null O · `mode` text(50) R · `distance_km` real R · `fare_eur` real R · `is_fare_manual` bool R ·
`is_round_trip` bool R · `travel_class` text(50) R · `companions` int R · `states` text(200) R · `note` text(10000) R ·
`category` text(50) O ('') · `is_induced` bool O (false) · `via` text(1000) K ('') · `journey_id` text(36) K ('') ·
`leg_index` int K (0) · `created_at` R · `updated_at` R · `deleted_at` O (null)

**favorite_routes**: `id` uuid R · `title` text(200) R · `from_name` text(200) R · `to_name` text(200) R ·
`from_station_id` O · `to_station_id` O · `mode` text(50) R · `distance_km` real R · `fare_eur` real R · `is_round_trip` bool R ·
`states` text(200) R · `sort_index` int R · `usage_count` int R · `category` text(50) O ('') · `via` text(1000) K ('') ·
`legs` text(4000) K ('') · `created_at` R · `updated_at` R · `deleted_at` O (null)

**benefits**: `id` uuid R · `date` timestamp R · `partner_id` text(100) R · `title` text(200) R · `saved_eur` real R ·
`note` text(10000) R · `created_at` R · `updated_at` R · `deleted_at` O (null)

`profiles` is **not** a sync table (use `/v1/me`). `photoData` is not synced. `test/fixtures/contract-rows.json` holds
one push row and the expected pull row per table, including upper-case ids → lowercase and a `+02:00` offset →
canonical UTC. Both sides test against it.

### 3.6 `POST /v1/sync/push`

Request `{"table":"trips","rows":[…]}`. Unknown envelope keys are ignored; an unknown table → `400 unknown_table`;
`rows` must be an array of ≤ 500 objects (else `422 too_many_rows` or `400 invalid_request`).
1. Authenticate (§2.7) and apply the version gate.
2. Validate and normalize every row (§3.4/§3.5). The first failure rejects the **whole** request with its index and field.
3. **Clamp**: `updated_at > now + 10 min` → `updated_at = now` (comparing canonical strings is valid because the
   format has fixed width). `created_at` is not clamped.
4. **Duplicates** (same `id` twice): keep the one with the greatest `updated_at` (on a tie, the last occurrence); the
   dropped ones count as `skipped`.
5. One `env.DB.batch` (2 statements, exactly the pattern proven in `test/contract-sql.test.ts`):
   - `UPDATE sync_state SET server_rev = server_rev + ?n WHERE id = 1 RETURNING server_rev` reserves the revisions
     `R-n+1 … R` (gaps from skipped rows are fine);
   - `INSERT INTO <table> (user_id, <columns…>, server_rev) SELECT ?uid, j.value ->> '$.<col>' …, (SELECT server_rev FROM sync_state WHERE id = 1) - ?n + j.key + 1 FROM json_each(?rowsJson) AS j WHERE true ON CONFLICT (user_id, id) DO UPDATE SET <every column except user_id, id, created_at> = excluded.<col>, server_rev = excluded.server_rev WHERE excluded.updated_at >= <table>.updated_at AND (<OR over every column except user_id, id, created_at, updated_at, server_rev: excluded.c IS NOT <table>.c>)`.
   `?rowsJson` is the **normalized** array (booleans as 0/1, canonical timestamps, lowercase ids). Table and column
   names come from the static schema map in `src/`, never from input.
6. A FOREIGN KEY failure (the user was deleted meanwhile) → `401 invalid_token`.
7. `200 {"applied": <upsert meta.changes>, "skipped": <received − applied>, "server_rev": R}`.
   Empty `rows` → `200 {"applied":0,"skipped":0,"server_rev":<current>}` (the client skips empty pushes anyway).

Semantics, identical to Supabase 0002: last writer wins on the client's `updated_at`; a stale write (older
`updated_at`) is silently skipped; a write that changes nothing but `updated_at` (an echo) is skipped without a
revision bump; equal `updated_at` with different content → applied; `user_id`/`id`/`created_at` never change;
deletes are soft (`deleted_at`), and an "undelete" is an ordinary newer write. Tombstones are never purged (an
offline device must learn deletions months later).

### 3.7 `GET /v1/sync/pull?table=<t>&after=<rev>&limit=<n>`

- `table` from §3.5, else `400 unknown_table`; `after` matches `^\d{1,15}$` (default 0); `limit` 1–500 (default 500).
- `SELECT * FROM <t> WHERE user_id = ?uid AND server_rev > ?after ORDER BY server_rev ASC LIMIT ?limit`, then convert
  the 0/1 columns to booleans.
- `200 {"rows":[…], "next": <server_rev of the last row> | null}`. `next` is non-null iff `rows.length == limit`.
- Why there is no overlap window: D1 runs batches one at a time, each in a single transaction, and every batch takes
  revisions above all earlier ones. A reader sees only whole batches, so `cursor = max(server_rev seen)` never skips
  a row. (Postgres needed the 2-minute re-read; D1 does not.)

### 3.8 Client sync algorithm (unchanged semantics, new transport)

For each table in order: tickets → trips → favorite_routes → benefits.
- **Push**: rows changed since this account's last push (as today). Chunks of ≤ 500 rows **and** ≤ 1 000 000
  encoded bytes (halve a chunk that is too big). A 401 → refresh once and retry (`withSession`).
- **Pull**: `after = cursor(table, account)`; loop until `next == null`. A `next` that is not greater than the
  current `after` → `invalidResponse` (no endless loops). Max 4000 pages.
- Then merge (`SyncMergeRule`, unchanged) → save → move the cursors to `max(server_rev)` per table → `lastSync`.

### 3.9 `POST /v1/account/delete`

Bearer auth, rate limit `account_delete`, body `{}` or empty. First read the sealed Apple tokens, then run one batch
that deletes from `tickets`, `trips`, `favorite_routes`, `benefits` (WHERE user_id), `refresh_tokens` (WHERE
session_id IN the user's sessions), `sessions`, `auth_codes`, `identities`, `profiles`, and `users` (last). Then
start the Apple revocation (§2.9) in `waitUntil` and answer `200 {"deleted":true}`. Every session of the user is
gone, so other devices get `401` → refresh `invalid_grant` → local profile with "Mit Konto verbinden". Data on the
devices stays local.

### 3.10 Cron (`scheduled`, daily, `23 3 * * *`)

Delete expired `auth_flows`, `auth_codes`, `apple_native_nonces`; `rate_limits` with `window_start < now − 1 d`;
`refresh_tokens` with `expires_at < now − 1 d`; sessions that are revoked or expired for more than 30 days (cascades
to their tokens); `users` without identities whose `created_at < now − 1 d` (orphans from §2.6 races). Each delete
is bounded (`LIMIT`-style via `rowid IN (SELECT … LIMIT 5000)`) so the run stays within the limits.

---

## 4. D1 schema

Authoritative: `backend/migrations/0001_init.sql` (committed with this contract, verified on D1/Miniflare). Summary:

| Table | Key | Notes |
|---|---|---|
| `sync_state` | `id = 1` | `server_rev` global counter |
| `users` | `id` (uuid) | `created_at`, `last_login_at` (ms) |
| `identities` | `(provider, subject)` | `user_id` → users CASCADE, index `identities_user`; `email`, `email_verified`, sealed Apple `provider_refresh_token` |
| `profiles` | `user_id` | `display_name`, `avatar_url` |
| `sessions` | `id` (= JWT `sid`) | `user_id`, `provider`, `subject`, `expires_at` (sliding), `revoked_at`, `revoked_reason`, index `sessions_user` |
| `refresh_tokens` | `token_hash` | `session_id` → sessions CASCADE, `used_at`, `replaced_by`, `revoked_at` |
| `auth_flows` | `id` (= provider state) | 10 min |
| `auth_codes` | `code_hash` | 120 s, `used_at`, `session_id` |
| `apple_native_nonces` | `nonce_hash` | replay cache |
| `rate_limits` | `bucket` | fixed window |
| `tickets`, `trips`, `favorite_routes`, `benefits` | `(user_id, id)` | columns per §3.5, `server_rev`, index `<table>_user_rev (user_id, server_rev)` |

Internal timestamps are INTEGER ms; synced data timestamps are canonical TEXT. Rules for later migrations
(`0002_*.sql` …): CI applies migrations **before** it deploys the new code, so each migration MUST be backwards
compatible with the Worker version still running (additive: new tables, or new columns with defaults). A new sync
column MUST have a default so that older apps that do not send it keep working, and goes into §3.5, the fixture, the
Swift DTO and the schema map together.

---

## 5. Deploy

### 5.1 `.github/workflows/backend.yml` (WP-D)

- Triggers: `push` on any branch with `paths: ['backend/**', '.github/workflows/backend.yml']`; `workflow_dispatch`.
  `permissions: contents: read`.
- Job **test** (ubuntu-24.04, `working-directory: backend`): checkout, `actions/setup-node@v4` (node 22, npm cache
  on `backend/package-lock.json`), `npm ci`, `npm run typecheck`, `npm test`.
- Job **deploy** (`needs: test`, `concurrency: {group: backend-deploy, cancel-in-progress: false}`). It runs when
  `github.event_name == 'workflow_dispatch' || github.ref_name == 'main' || github.ref_name == 'claude/klimabilanz-ios-app'`.
  Env: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (secrets; passed **per step** to the steps that call
  Cloudflare, never job-wide, so `npm ci` install scripts never see them), `WRANGLER_SEND_METRICS=false`. Steps:
  1. **Gate**: if either Cloudflare secret is empty, print
     `::notice title=Backend nicht bereitgestellt::CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID fehlen – siehe docs/SETUP.md §3`,
     write the same line to `$GITHUB_STEP_SUMMARY`, set the output `skip=true`, and **exit 0**. Every later step has
     `if: steps.gate.outputs.skip != 'true'`.
  2. `npm ci`.
  3. **Subdomain**: `GET https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain` →
     `result.subdomain`. If it is missing, fail with the German hint "Öffne einmal *Workers & Pages* im
     Cloudflare-Dashboard, um eine workers.dev-Subdomain anzulegen". `PUBLIC_BASE_URL = vars.API_BASE_URL` (trailing
     `/` stripped) `|| https://klimabilanz-api.<subdomain>.workers.dev`.
  4. **D1 find-or-create**: `npx wrangler d1 list --json` → entry with `name == "klimabilanz"` → `uuid`. If there is
     none, run `npx wrangler d1 create klimabilanz --jurisdiction eu` and list again. If an existing database reports
     a jurisdiction other than `eu` (when the listing has that field), emit `::warning::`.
  5. **Render**: `node scripts/render-wrangler-config.mjs` with env `D1_DATABASE_ID`, `PUBLIC_BASE_URL`,
     `MIN_APP_VERSION` (`vars.API_MIN_APP_VERSION`, may be empty) writes `backend/wrangler.toml`: in each line marked
     `# @render NAME`, replace the quoted value with `$NAME` when it is set. Fail if a `database_id` placeholder is
     left. The rendered file is never committed (`.gitignore`) and never uploaded as an artifact.
  6. **Migrate**: `npx wrangler d1 migrations apply DB --remote` (non-interactive in CI).
  7. **Secrets**: `npx wrangler secret list --format json` (if the Worker does not exist yet, this fails → `[]`).
     `node scripts/compose-secrets.mjs` writes `$RUNNER_TEMP/kb-secrets.json` (mode 600) with every **non-empty**
     managed secret from the env (§5.4), plus `SESSION_SIGNING_KEY` = `crypto.randomBytes(48).toString("base64url")`
     **only if** the list does not contain it (never rotate it implicitly: that would sign everyone out). It also
     writes `$RUNNER_TEMP/kb-stale.json` with `null` for every managed provider secret that exists on the Worker but
     is empty in GitHub (GitHub is the source of truth, so deleting a GitHub secret disables the provider). Pruning is
     skipped when the repository variable `BACKEND_KEEP_WORKER_SECRETS == 'true'` (for people who set provider
     secrets directly in Cloudflare). Values are never printed; `::add-mask::` the generated key.
  8. **Deploy**: `npx wrangler deploy --secrets-file $RUNNER_TEMP/kb-secrets.json` (atomic with the new version;
     secrets are additive). Then, if the stale file is non-empty, `npx wrangler secret bulk $RUNNER_TEMP/kb-stale.json`.
     `rm -f` both files in an `always()` step.
  9. **Smoke test**: `curl -fsS --retry 5 --retry-delay 3 "$PUBLIC_BASE_URL/v1/health"` and `…/v1/config`.
  10. **Summary** (`$GITHUB_STEP_SUMMARY`, German): the Worker URL, which providers are enabled (from `/v1/config`),
      and the exact callback URLs to register (`$PUBLIC_BASE_URL/v1/auth/google/callback`, `…/microsoft/callback`,
      `…/apple/callback`) plus the Apple *Domains* value (the host).
- Custom domain (optional): repository variable `API_BASE_URL=https://api.example.at`. WP-D MAY add
  `API_CUSTOM_DOMAIN` support (render `routes = [{ pattern = "<host>", custom_domain = true }]`) **only** after
  checking the token permissions this needs in Cloudflare's docs; otherwise document the dashboard way (*Worker ›
  Settings › Domains & Routes › Add › Custom domain*) and then setting `API_BASE_URL`.

### 5.2 iOS build: deriving the API URL (WP-D, `ios.yml` + `scripts/write_app_config.py`)

The "App configuration" step passes `API_BASE_URL: ${{ vars.API_BASE_URL }}`, `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` (secrets) to `write_app_config.py`, which:
1. uses `API_BASE_URL` if set; otherwise, if both Cloudflare values are set, calls the subdomain API (urllib, 10 s
   timeout, token only in the header, never printed) → `https://klimabilanz-api.<subdomain>.workers.dev`; otherwise `""`;
2. checks the result: `https://` and no path, query or fragment (trailing `/` stripped); anything invalid →
   `::warning::` and `""`;
3. with a URL, probes `GET <url>/v1/health` (5 s); a failure is only a `::warning::` (the backend may be deployed
   later). It never fails the build;
4. writes `apiBaseURL` (and still `updateManifestURL`, `tariffsURL`). `SUPABASE_*` is removed everywhere.

The `ios.yml` lines for the new Swift package (WP-D adds them; WP-C creates the package):
- job `core-tests`: `swift test --package-path Packages/KlimaCloud --no-parallel 2>&1 | tail -60` (after KlimaCore);
- job `build`, step "KlimaCore tests (macOS)": additionally `swift test --package-path Packages/KlimaCloud 2>&1 | tail -25`.

### 5.3 Rendered config values

| Marker | Source | Default (template) |
|---|---|---|
| `D1_DATABASE_ID` | step 4 | `00000000-0000-0000-0000-000000000000` (local/tests) |
| `PUBLIC_BASE_URL` | step 3 | `""` (derive from the request) |
| `MIN_APP_VERSION` | `vars.API_MIN_APP_VERSION` | `"1.0.0"` |

### 5.4 Secrets (GitHub → Worker)

| GitHub secret | Worker secret | Notes |
|---|---|---|
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | – | deploy credentials only, never sent to the Worker |
| – | `SESSION_SIGNING_KEY` | generated once by CI; rotate manually: `wrangler secret put SESSION_SIGNING_KEY_PREVIOUS` (old value), then the new key (all refresh tokens stay valid; access tokens signed with the old key verify via `_PREVIOUS`) |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | same names | |
| `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET` | same names | secret expires after ≤ 24 months |
| `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_BUNDLE_ID` | same names | `APPLE_TEAM_ID` is shared with the iOS signing job; `APPLE_PRIVATE_KEY` = the whole `.p8` content |

Managed provider secrets = the 9 provider names above (`SESSION_SIGNING_KEY*` are never deleted by CI). Repository
variables used: `API_BASE_URL` (optional custom origin), `API_MIN_APP_VERSION` (optional), `BACKEND_KEEP_WORKER_SECRETS`
(optional, disables pruning).

### 5.5 User setup (content WP-D MUST put into `docs/SETUP.md` §3, German, step by step)

1. **Account ID**: dash.cloudflare.com → *Workers & Pages* (or the account home) → "Account ID" in the right
   column → copy. If you have never used Workers & Pages, open it once and **pick a workers.dev subdomain**.
2. **API token**: *My Profile › API Tokens › Create Token › Custom token*, name "KlimaBilanz GitHub Deploy",
   permissions **Account · Workers Scripts · Edit**, **Account · D1 · Edit**, **Account · Account Settings · Read**,
   **User · User Details · Read**. Account Resources: *Include › <your account>*. No IP filter (GitHub runners
   change). Copy the token once.
3. GitHub → *Settings › Secrets and variables › Actions › Secrets*: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
4. *Actions › Backend › Run workflow* → creates D1 "klimabilanz" (EU), the Worker and the signing key. The run
   summary shows the URL and the callback URLs.
5. **Google (free)**: console.cloud.google.com → project → *Google Auth Platform*: Branding (app name, support
   e-mail), Audience *External* → **Publish app** (openid/email/profile are not sensitive, so Google does not need
   to verify the app); *Clients › Create client › Web application*, *Authorized redirect URI* = the Google callback
   URL from the summary → secrets `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`.
6. **Microsoft (free)**: entra.microsoft.com (needs a Microsoft Entra directory, free, e.g. through a free Azure
   account) → *App registrations › New registration*, "Accounts in any organizational directory and personal
   Microsoft accounts", Redirect URI platform **Web** = the Microsoft callback URL → *Certificates & secrets › New
   client secret* (note the expiry date) → secrets `MICROSOFT_CLIENT_ID` (Application (client) ID),
   `MICROSOFT_CLIENT_SECRET` (secret **Value**).
7. **Apple (only with the paid Apple Developer Program, 99 €/year)**: *Identifiers*: App ID
   `com.knitelarlberg.klimabilanz` with Sign in with Apple; *Services ID* `com.knitelarlberg.klimabilanz.web` →
   Sign in with Apple → Configure: Primary App ID, **Domains** = the Worker host, **Return URLs** = the Apple
   callback URL; *Keys* → new key with Sign in with Apple → download the `.p8` (only possible once), note the Key ID;
   Team ID from *Membership* → secrets `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`
   (the full file content), `APPLE_BUNDLE_ID=com.knitelarlberg.klimabilanz` (native sign-in in signed builds). If Apple
   rejects the workers.dev domain, use a custom domain (§5.1).
8. Run *Backend* again (changing a secret does not trigger a run), then *iOS › Run workflow*: the app gets the URL
   automatically.

Also document: the free plans are enough (Workers Free 100 000 requests/day, D1 Free 5 GB / 5 M reads / 100 000
writes per day); data is stored in the EU (D1 jurisdiction `eu`), while the Worker runs at the Cloudflare location
nearest to the user; and "Abmelden", "Kontowechsel" and "Uhrzeit" behave as before (keep those paragraphs).

---

## 6. Swift client (WP-C)

### 6.1 `Packages/KlimaCloud` (new local SwiftPM package; Foundation only; Linux + macOS)

`Package.swift` like KlimaCore: tools 6.0, `platforms: [.iOS("26.0"), .macOS("15.0")]`,
`swiftLanguageModes: [.v5]`, library `KlimaCloud`, test target `KlimaCloudTests`. No UIKit, Security, SwiftData,
AuthenticationServices or Observation. `#if canImport(FoundationNetworking) import FoundationNetworking #endif`.
Public types (names binding, internals free):
- `CloudSession` (Codable, Equatable, Sendable): `accessToken`, `refreshToken`, `expiresAt` (device clock from
  `expires_in`), `refreshExpiresAt`, `user: CloudUser`; `isExpired` (60 s margin).
- `CloudUser`: `id`, `email`, `emailVerified`, `displayName`, `avatarURL`, `provider` (String), `createdAt`.
- `CloudConfig`: provider flags (`googleWeb`, `microsoftWeb`, `appleWeb`, `appleNative`), `minAppVersion`,
  `syncTables`, `serverTime`; decoding tolerates unknown or missing keys.
- `CloudError: LocalizedError`: `notConfigured`, `invalidResponse`, `missingCode`, `stateMismatch`,
  `authorization(String)`, `sessionExpired`, `schemaOutdated`, `upgradeRequired(minVersion: String?)`,
  `rateLimited(retryAfter: Int?)`, `api(status: Int, code: String, message: String)`, `http(Int, String)`;
  `status`, `code`, `isUnauthorized` (401 `invalid_token` from our API), `isDefinitiveAuthFailure` (only
  `sessionExpired`, or `api(400, "invalid_grant", _)` that came from our API, recognized by `X-KB-API: 1`). A
  response without `X-KB-API` (captive portal, proxy HTML) maps to `http(status, …)` and never signs anyone out.
- `HTTPTransport` protocol `send(_ URLRequest) async throws -> (Data, HTTPURLResponse)` and `URLSessionTransport`
  (ephemeral, 30 s, no cache, no cookies, **never follows redirects**: the API has none, and following one would replay
  the bearer token and body against the `Location`).
- `CloudAPIClient` (Sendable struct; `baseURL`, `transport`, `appVersion`, `build`, `osVersion`):
  `fetchConfig()`, `authorizeURL(provider:codeChallenge:state:redirectURI:)`, `exchangeCode(_:codeVerifier:redirectURI:)`,
  `signInWithApple(identityToken:rawNonce:authorizationCode:fullName:)`, `refresh(_:)`, `logout(_:)` (best effort, sends
  the refresh token, ignores errors), `me(session:)`, `updateDisplayName(_:session:)`, `deleteAccount(session:)` (60 s),
  `push(table:rows:session:) -> PushResult` (chunking per §3.8), `pullAll(table:after:pageSize:maxPages:session:) -> (rows, maxRev)`,
  and `static withSession(_ provider: SessionProvider, _ op:)` (one refresh and retry after 401).
  `typealias SessionProvider = @Sendable (_ rejected: CloudSession?) async throws -> CloudSession`.
- `WebAuthCallback.parse(_ url: URL, expectedState: String) -> Result<String /*code*/, CloudError>` (query and
  fragment, `+` → space, `access_denied` → a distinct `.cancelled` case or error, as WP-C decides).
- `APITimestamp` (renamed `PostgresTimestamp`, same algorithm), `CloudCoding.encoder/decoder` (dates as canonical strings).
- `PKCE`: `makeVerifier()` (48 random bytes → 64 chars), `challenge(for:)`, `randomURLSafe(byteCount:)`,
  `sha256Hex(_:)`, `base64URL(_:)`. Randomness from `SystemRandomNumberGenerator` (a CSPRNG on Apple platforms and
  Linux). SHA-256: CryptoKit `#if canImport(CryptoKit)`, otherwise a portable implementation in the package. The
  tests run both against the same vectors.
- `SyncRow` protocol and `TicketDTO`, `TripDTO`, `FavoriteDTO`, `BenefitDTO` (fields exactly as today = §3.5; public
  memberwise inits; `server_rev: Int64?`), `SyncMergeRule` (unchanged), `SyncOwnerStore` (UserDefaults; see §6.4).
- `SecureStore` protocol (`read(key) -> SecureReadResult {found(Data), notFound, locked, failed}`,
  `write(_:key:thisDeviceOnly:) -> Bool`, `delete(key)`) plus an in-memory implementation for tests.
- SHOULD: `SessionCoordinator` (`@MainActor` class, no Observation): the current session, a single in-flight
  refresh shared by all callers, persistence through `SecureStore`, a callback when a refresh definitively fails. This
  makes the serialization logic Linux-testable. If WP-C keeps the logic in `AuthService`, it MUST keep today's
  guarantees (one refresh in flight; a result is ignored if the account changed meanwhile).

### 6.2 App changes

- Delete `App/Sources/Services/SupabaseClient.swift`. New `App/Sources/Services/KeychainStore.swift` (the existing
  `Keychain` enum, conforming to `SecureStore`). `project.yml`: package `KlimaCloud: path: Packages/KlimaCloud`, and
  the dependency of the `KlimaBilanz` target (not the widget).
- `AppConfig`: `apiBaseURL: String`, `api: URL?` (only `https`, no path), `isCloudConfigured`, plus `updateManifestURL`
  and `tariffsURL`. A custom `init(from:)` with `decodeIfPresent` everywhere (today a missing key silently turns the
  whole config off). `AppConfig.json` = `{"apiBaseURL":"","updateManifestURL":"","tariffsURL":""}`.
  `urlScheme`/`authCallback` stay.
- `AuthService` (same public API, §6.3): uses `CloudAPIClient`. `AuthProvider.supabaseProvider` →
  `apiProvider` (`"apple"`, `"google"`, `"microsoft"`); `init?(apiProvider:)`. New observable
  `serverConfig: CloudConfig?` (cached in UserDefaults `cloud.config`, refreshed at init and on `signIn`), and
  `func isProviderEnabled(_ p: AuthProvider, native: Bool = false) -> Bool` (true while the config is unknown).
  Web sign-in: verifier and state from `PKCE`, `WebAuthenticationSession.authenticate(using: client.authorizeURL(…), callbackURLScheme: AppConfig.urlScheme, preferredBrowserSession: .ephemeral)`,
  `WebAuthCallback.parse`, then `exchangeCode`. Native Apple: the nonce is handled as today; send `identityToken`,
  raw nonce, `authorizationCode`, and the formatted `fullName`. There is no more `updateUserMetadata`: the server
  stores the first-login name. Without a cloud, the local Apple identity behaves exactly as today.
  `signOut()`: clear local state first, then `client.logout(old)` (no refresh needed). `deleteAccount()`: through
  `withSession`; afterwards clear local state and `SyncOwnerStore.forget`. `updateDisplayName` also calls
  `PATCH /v1/me` (fire and forget) when signed in to the cloud.
  Keychain: the session lives under **`auth.session.cf1`** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), the
  profile under `auth.profile` (unchanged). At init, delete the legacy item `auth.session` (the old Supabase session).
  The existing reconcile logic then turns a legacy cloud profile into a local one with `needsReauthentication = true`.
- `SyncService` (same public API): `client.push`/`client.pullAll`; remove `onConflict`, `pullOverlap` and
  `schemaOutdated` texts about Supabase; DTO ↔ entity mapping as extensions in the app (`init(_ e: TicketEntity, userID:)`,
  `apply(to:)`, `makeEntity()`), delegating to the public memberwise inits. Map `426` to the German message, and when
  it happens SHOULD trigger `app.updates.checkIfDue(force: true)` from the caller if that is easy.
- `AuthButtonStack`: Google only if `isProviderEnabled(.google)`, Microsoft only if `isProviderEnabled(.microsoft)`;
  Apple: native button if `AppConfig.supportsNativeAppleSignIn && (!isCloudAvailable || isProviderEnabled(.apple, native: true))`,
  else the web button if `isCloudAvailable && isProviderEnabled(.apple)`, else none. If the cloud is available but
  the config says nothing is enabled, show the footnote "Die Anmeldung ist auf dem Server noch nicht eingerichtet."
  Change the Supabase comment to say Cloudflare.
- `SetAccountSection` › `SetCloudSetupPage`: a German summary of §5.5 in six steps (Cloudflare account and
  subdomain, API token with the 4 permissions, the two GitHub secrets, *Actions › Backend*, providers (Google/Microsoft
  free, Apple needs the paid program), rebuild with *Actions › iOS*). A link row "dash.cloudflare.com öffnen"; replace
  the "Redirect-URL kopieren" row with "Anleitung öffnen" → `https://github.com/Jecuro1/KLIMATICKET-APP/blob/main/docs/SETUP.md`.
  The intro mentions "dein eigenes, kostenloses Cloudflare-Konto". Footer unchanged in spirit.
- `RootView`/`AppState`/`Repository`/`DashboardView`/Onboarding: touch only if an API change forces it (it should not).

### 6.3 Public API that MUST stay source-compatible

`app.auth.`: `profile`, `isCloudAvailable`, `isSignedIn`, `signIn(with:using:)`, `phase` (`.signedOut`,
`.signingIn(AuthProvider)`, `.signedIn`), `lastError`, `signOut()`, `prepareAppleRequest(_:)`,
`handleAppleCompletion(_:)`, `continueWithoutAccount(name:)`, `updateDisplayName(_:)`, `deleteAccount()`,
`isDeletingAccount`, `needsReauthentication`, `validSession(forceRefresh:)`, `refreshedSession(after:)`,
`session?.user.id`/`.email` (used by SyncService). `UserProfile`, `AuthProvider` (`.apple/.google/.microsoft/.local`,
`displayName`).
`app.sync.`: `sync(context:auth:)`, `state` (`.disabled/.idle/.syncing/.synced(Date)/.failed(String)`),
`resetSyncCursor()`, `lastSync`, `pendingAccountSwitch` (`SyncService.AccountSwitch` with today's fields),
`mergeLocalDataIntoAccount`, `discardLocalDataAndSync`, `cancelAccountSwitch(auth:)`,
`deleteAllDataEverywhere(context:auth:) -> Bool` (discardable), `isPaused`.

### 6.4 Migration from the Supabase era (on-device)

- `SyncOwnerStore` gains `sync.owner.backend` (`"cf1"`). `claim` writes it. An existing owner **without** the
  marker is a *legacy owner*: its data was synced with the retired Supabase project. On the first cloud sync, the
  signed-in account silently adopts the data (claim + `setLastPush(nil)` = push everything, as in
  `mergeLocalDataIntoAccount`) instead of showing the account-switch dialog. Owners with the marker behave as today.
- The old per-user cursors and lastPush keys of Supabase user ids can be left alone (they are never read for the new ids).

### 6.5 Error texts (German, by code)

| Code / case | Text |
|---|---|
| `sessionExpired` / `invalid_grant` on refresh | "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an." |
| `provider_disabled` | "Die Anmeldung mit {Anbieter} ist auf dem Server noch nicht eingerichtet." |
| `access_denied` (callback) | (silent: cancelled) |
| `stateMismatch`, `invalid_id_token`, `provider_error` | "Die Anmeldung hat nicht geklappt. Bitte versuch es noch einmal." (+ sanitized provider text, if any) |
| `rate_limited` | "Zu viele Versuche. Bitte warte kurz und versuch es dann noch einmal." |
| `upgrade_required` | "Bitte aktualisiere KlimaBilanz – diese Version wird vom Server nicht mehr unterstützt." |
| `unknown_field`, `unknown_table` (→ `schemaOutdated`) | "Der Server ist nicht auf dem neuesten Stand. Bitte das Backend neu bereitstellen (GitHub › Actions › Backend)." |
| `invalid_row` | "Ein Eintrag konnte nicht synchronisiert werden (ungültiges Feld „{field}“)." |
| `server_not_configured` | "Der Server ist noch nicht fertig eingerichtet." |
| `notConfigured` | "Cloud-Anmeldung ist noch nicht eingerichtet." |
| account delete 404 | "Die Kontolöschung wird vom Server nicht unterstützt – bitte das Backend aktualisieren." |
| network (`URLError`) | the existing texts ("Keine Internetverbindung." / "Der Server ist gerade nicht erreichbar.") |

### 6.6 Linux tests (`swift test --package-path Packages/KlimaCloud`), minimum set

APITimestamp round-trips, µs precision, and every offset form; PKCE against the RFC 7636 Appendix B vector; SHA-256
against the NIST "abc"/empty/long vectors; callback parsing (query, fragment, `+`, error, state mismatch); error
mapping (JSON `invalid_grant` + `X-KB-API` → definitive; HTML 403 without the header → not definitive; 401 →
refresh and retry exactly once; 426/429/422 `unknown_field`); push chunking (1001 rows → 3 requests; big notes →
byte split); pull paging (`next` chain, a non-advancing `next` → error); DTO coding against
`backend/test/fixtures/contract-rows.json` (read via `#filePath`): decoding every `pull` object must work (with
`server_rev` replaced by an integer), and encoding a DTO must produce exactly the key set of the `push` object
(`user_id` included, `server_rev` absent, nil optionals absent); `SyncMergeRule` table; the `SyncOwnerStore`
legacy-owner rule; `SessionCoordinator` (if built): concurrent callers share one refresh, and a definitive failure
signals once.

---

## 7. Work packages

Every package works in its own worktree off `wip/cloudflare` and touches **only** its files. Shared interfaces are
this document and `backend/test/fixtures/contract-rows.json` (WP-S owns the fixture; changes need a contract update).

### WP-S: server (`backend/src/**`, `backend/migrations/**`, `backend/test/**`, `backend/package*.json`, `backend/tsconfig.json`, `backend/vitest.config.ts`, `backend/wrangler.template.toml` except `# @render` semantics)
Deliver all of §2 and §3: a router (tiny, hand-written), crypto helpers (HKDF, HS256 JWT, RS256 verify, ES256 sign,
AES-GCM, SHA-256, constant-time compare), JWKS cache, providers, auth flows, sessions, rate limiting, sync
push/pull, me, account delete, cron, config, health, error/headers middleware. Use dependency injection for
`fetch`, `now()` and random bytes (`handle(request, env, ctx, deps)`), so tests stub providers and time without
global mocks. Tests (vitest in workerd) MUST cover at least: the PKCE happy path and mismatch; code reuse revoking the
session; state replay; a wrong nonce/iss/aud/alg/expired/unknown kid; Microsoft tenant issuer; Apple form_post with
a `user` name; native Apple nonce, aud and replay; refresh rotation, the grace window, reuse revoking the family, and
expiry; logout revoking only that device; access tokens dying immediately after logout and deletion; rate limits
(429 + Retry-After, app redirect on `/start`); Origin rejection and OPTIONS; body limit 413; 501 rows → 422; unknown
field/table; user_mismatch; the fixture round-trip for all 4 tables; LWW/clamp/echo/tie/soft delete/immutables;
user isolation; paging with `next`; config flags per secret set; account deletion removing every row in every table;
cron cleanup. `npm run typecheck` and `npm test` green.

### WP-D: deploy and docs (`.github/workflows/backend.yml`, `.github/workflows/ios.yml`, `scripts/write_app_config.py`, `backend/scripts/**`, `docs/SETUP.md`, `README.md`, `docs/ARCHITECTURE.md`, Supabase mentions in other `docs/*`, delete `supabase/`, root `.gitignore`)
Deliver §5 completely. `render-wrangler-config.mjs` and `compose-secrets.mjs` are plain Node (no deps) with a
`node --test` self-test in `backend/scripts/*.test.mjs` (run from `backend.yml`'s test job). `write_app_config.py`
gets a small `python3 -m unittest` (subdomain derivation mocked, URL validation). Validate the YAML
(`python3 -c "import yaml…"` or actionlint if available). SETUP.md §3 is fully rewritten per §5.5; the docs say that
the git history still contains the Supabase variant. In ARCHITECTURE/README, replace the Supabase descriptions with
Cloudflare Worker + D1.

### WP-C: Swift client (`Packages/KlimaCloud/**`, `App/Sources/Services/{AuthService,SyncService,KeychainStore}.swift`, delete `SupabaseClient.swift`, `App/Sources/Core/AppConfig.swift`, `App/Resources/AppConfig.json`, `App/Sources/Features/Account/AuthButtonStack.swift`, `App/Sources/Features/Settings/SetAccountSection.swift`, `project.yml`; RootView/AppState/Settings only if forced)
Deliver §6. `swift test --package-path Packages/KlimaCloud` green on Linux. The app target cannot compile on Linux,
so keep the iOS-only glue thin and type-check by reading carefully; the orchestrator runs the macOS build (`[build]`).

### Integration order and acceptance
1. WP-S, WP-D and WP-C run in parallel against this contract.
2. Integration on `wip/cloudflare`: `backend` tests, `KlimaCloud` tests, `python3 scripts/check_integration.py` (if
   relevant), then a `[build]` commit for the iOS build. Merge into `main` only when green; that
   push triggers the first real deploy (it skips until the user adds the Cloudflare secrets).
3. Done means: with no Cloudflare secrets, every workflow is green and the app runs locally only, as today. With
   the secrets and at least one provider configured, a sign-in on the iPhone, sync between two devices, sign-out, and
   account deletion all work.

---

## 8. Out of scope / later
Account linking (`/v1/account/link`), e-mail/passkey login, sync of `profiles`/photos, tombstone purging, read
replicas, a custom domain via the API without verified permissions, Durable Objects, server-side push notifications.
