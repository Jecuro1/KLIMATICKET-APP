-- KlimaBilanz cloud schema – Cloudflare D1 (SQLite). Contract: docs/CLOUDFLARE_BACKEND.md §4.
-- Applied by CI with `wrangler d1 migrations apply DB --remote`; tests apply it via applyD1Migrations().
-- Never edit an applied migration: add 0002_….sql instead.
--
-- Conventions
--  * Ids: lowercase UUID text (users, synced rows) or base64url random text (sessions, flows).
--  * Internal tables (auth, sessions, rate limits): timestamps are INTEGER milliseconds since the Unix epoch.
--  * Synced data tables: timestamps are TEXT in the canonical wire format "YYYY-MM-DDTHH:MM:SS.ffffffZ"
--    (UTC, exactly 6 fraction digits). The Worker canonicalises every value, so string order = time order.
--  * Booleans are INTEGER 0/1 (JSON true/false on the wire).
--  * Foreign keys are enforced by D1; everything hangs off users(id) with ON DELETE CASCADE. Account deletion still
--    deletes every table explicitly (belt and braces), see §3.9.

-- ---------------------------------------------------------------------------------------------------------------
-- Server revision counter (pull cursor). One row; bumped in the same batch that writes synced rows.
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE sync_state (
  id         INTEGER PRIMARY KEY CHECK (id = 1),
  server_rev INTEGER NOT NULL CHECK (server_rev >= 0)
);
INSERT INTO sync_state (id, server_rev) VALUES (1, 0);

-- ---------------------------------------------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE users (
  id            TEXT PRIMARY KEY,                -- lowercase UUID v4 (crypto.randomUUID())
  created_at    INTEGER NOT NULL,
  last_login_at INTEGER NOT NULL
);

-- One row per (provider, provider subject). Never matched by e-mail (no automatic account merge).
CREATE TABLE identities (
  provider               TEXT NOT NULL CHECK (provider IN ('apple', 'google', 'microsoft')),
  subject                TEXT NOT NULL,          -- id_token "sub" (Microsoft: "sub" of this app registration)
  user_id                TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  email                  TEXT,                   -- informational only, never used for lookups
  email_verified         INTEGER NOT NULL DEFAULT 0 CHECK (email_verified IN (0, 1)),
  provider_refresh_token TEXT,                   -- Apple only: AES-GCM sealed refresh token for revocation (§2.9)
  created_at             INTEGER NOT NULL,
  last_login_at          INTEGER NOT NULL,
  PRIMARY KEY (provider, subject)
);
CREATE INDEX identities_user ON identities (user_id);

CREATE TABLE profiles (
  user_id      TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_url   TEXT,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);

-- One session = one sign-in on one device = one refresh-token family.
CREATE TABLE sessions (
  id                TEXT PRIMARY KEY,            -- 16 random bytes, base64url; access token claim "sid"
  user_id           TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  provider          TEXT NOT NULL,               -- identity used for this sign-in
  subject           TEXT NOT NULL,
  created_at        INTEGER NOT NULL,
  last_refreshed_at INTEGER NOT NULL,
  expires_at        INTEGER NOT NULL,            -- sliding: last refresh + 60 days
  revoked_at        INTEGER,
  revoked_reason    TEXT,                        -- logout | refresh_reuse | code_reuse | account_deleted | replaced
  user_agent        TEXT
);
CREATE INDEX sessions_user ON sessions (user_id);

CREATE TABLE refresh_tokens (
  token_hash  TEXT PRIMARY KEY,                  -- base64url(SHA-256(token))
  session_id  TEXT NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL,
  used_at     INTEGER,                           -- set when rotated
  replaced_by TEXT,                              -- token_hash of the successor
  revoked_at  INTEGER
);
CREATE INDEX refresh_tokens_session ON refresh_tokens (session_id);

-- ---------------------------------------------------------------------------------------------------------------
-- Short-lived auth state (cleaned up by the daily cron)
-- ---------------------------------------------------------------------------------------------------------------
-- Browser flow app → Worker → provider → Worker. Keyed by the provider "state" value; consumed exactly once.
CREATE TABLE auth_flows (
  id                     TEXT PRIMARY KEY,       -- 32 random bytes, base64url = provider "state"
  provider               TEXT NOT NULL,
  nonce                  TEXT NOT NULL,          -- OIDC nonce sent to the provider
  provider_code_verifier TEXT,                   -- PKCE towards Google / Microsoft (Apple: NULL)
  app_code_challenge     TEXT NOT NULL,          -- PKCE S256 challenge from the app
  app_state              TEXT NOT NULL,
  app_redirect_uri       TEXT NOT NULL,
  created_at             INTEGER NOT NULL,
  expires_at             INTEGER NOT NULL        -- created_at + 10 min
);
CREATE INDEX auth_flows_expires ON auth_flows (expires_at);

-- One-time codes handed to the app (klimabilanz://auth-callback?code=…), redeemed at POST /v1/auth/token.
CREATE TABLE auth_codes (
  code_hash      TEXT PRIMARY KEY,               -- base64url(SHA-256(code))
  user_id        TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  provider       TEXT NOT NULL,
  subject        TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  redirect_uri   TEXT NOT NULL,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL,               -- created_at + 120 s
  used_at        INTEGER,
  session_id     TEXT                            -- session created on redemption (revoked on code reuse)
);
CREATE INDEX auth_codes_expires ON auth_codes (expires_at);

-- Replay cache for native Sign in with Apple (identity token nonce).
CREATE TABLE apple_native_nonces (
  nonce_hash TEXT PRIMARY KEY,                   -- the id_token "nonce" claim (already SHA-256 hex)
  expires_at INTEGER NOT NULL
);

-- Fixed-window rate limit counters. bucket = "<limit name>:<HMAC(ip or user)>".
CREATE TABLE rate_limits (
  bucket       TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,                 -- ms, aligned to the window length
  count        INTEGER NOT NULL
);

-- ---------------------------------------------------------------------------------------------------------------
-- Synced data (columns = SyncService DTOs, snake_case). Primary key (user_id, id): the same local row may exist in
-- two accounts (account switch → "merge"). Soft deletes via deleted_at; tombstones are kept.
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE tickets (
  user_id               TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  id                    TEXT NOT NULL,
  product_id            TEXT NOT NULL,
  name                  TEXT NOT NULL,
  variant               TEXT NOT NULL DEFAULT 'klassik',
  family                TEXT NOT NULL DEFAULT 'oe',
  states                TEXT NOT NULL DEFAULT '',
  price                 REAL NOT NULL DEFAULT 0,
  start_date            TEXT NOT NULL,
  end_date              TEXT NOT NULL,
  holder_name           TEXT NOT NULL DEFAULT '',
  ticket_number         TEXT NOT NULL DEFAULT '',
  theme                 TEXT NOT NULL DEFAULT 'twilight',
  reminders             TEXT NOT NULL DEFAULT '30,7,1',
  is_monthly_payment    INTEGER NOT NULL DEFAULT 0 CHECK (is_monthly_payment IN (0, 1)),
  auto_renews           INTEGER NOT NULL DEFAULT 0 CHECK (auto_renews IN (0, 1)),
  employer_contribution REAL NOT NULL DEFAULT 0,
  add_on_price          REAL NOT NULL DEFAULT 0,
  add_ons               TEXT NOT NULL DEFAULT '',
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  deleted_at            TEXT,
  server_rev            INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX tickets_user_rev ON tickets (user_id, server_rev);

CREATE TABLE trips (
  user_id         TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  id              TEXT NOT NULL,
  date            TEXT NOT NULL,
  from_name       TEXT NOT NULL,
  to_name         TEXT NOT NULL,
  from_station_id TEXT,
  to_station_id   TEXT,
  mode            TEXT NOT NULL DEFAULT 'train',
  distance_km     REAL NOT NULL DEFAULT 0,
  fare_eur        REAL NOT NULL DEFAULT 0,
  is_fare_manual  INTEGER NOT NULL DEFAULT 0 CHECK (is_fare_manual IN (0, 1)),
  is_round_trip   INTEGER NOT NULL DEFAULT 0 CHECK (is_round_trip IN (0, 1)),
  travel_class    TEXT NOT NULL DEFAULT 'second',
  companions      INTEGER NOT NULL DEFAULT 0,
  states          TEXT NOT NULL DEFAULT '',
  note            TEXT NOT NULL DEFAULT '',
  category        TEXT NOT NULL DEFAULT '',
  is_induced      INTEGER NOT NULL DEFAULT 0 CHECK (is_induced IN (0, 1)),
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  deleted_at      TEXT,
  server_rev      INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX trips_user_rev ON trips (user_id, server_rev);

CREATE TABLE favorite_routes (
  user_id         TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  id              TEXT NOT NULL,
  title           TEXT NOT NULL DEFAULT '',
  from_name       TEXT NOT NULL,
  to_name         TEXT NOT NULL,
  from_station_id TEXT,
  to_station_id   TEXT,
  mode            TEXT NOT NULL DEFAULT 'train',
  distance_km     REAL NOT NULL DEFAULT 0,
  fare_eur        REAL NOT NULL DEFAULT 0,
  is_round_trip   INTEGER NOT NULL DEFAULT 0 CHECK (is_round_trip IN (0, 1)),
  states          TEXT NOT NULL DEFAULT '',
  sort_index      INTEGER NOT NULL DEFAULT 0,
  usage_count     INTEGER NOT NULL DEFAULT 0,
  category        TEXT NOT NULL DEFAULT '',
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  deleted_at      TEXT,
  server_rev      INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX favorite_routes_user_rev ON favorite_routes (user_id, server_rev);

CREATE TABLE benefits (
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  id         TEXT NOT NULL,
  date       TEXT NOT NULL,
  partner_id TEXT NOT NULL DEFAULT 'custom',
  title      TEXT NOT NULL DEFAULT '',
  saved_eur  REAL NOT NULL DEFAULT 0,
  note       TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_rev INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX benefits_user_rev ON benefits (user_id, server_rev);
