/** Worker bindings, vars and secrets (docs/CLOUDFLARE_BACKEND.md §5.4). Every secret is optional at runtime. */
export interface Env {
  DB: D1Database;

  // [vars] (wrangler.template.toml)
  PUBLIC_BASE_URL?: string;
  MIN_APP_VERSION?: string;
  APP_REDIRECT_URIS?: string;
  /** owner/repo whose GitHub releases /v1/ota serves and whose "Gerät registrieren" workflow /v1/udid/done links. */
  OTA_GITHUB_REPO?: string;

  // Secrets
  SESSION_SIGNING_KEY?: string;
  SESSION_SIGNING_KEY_PREVIOUS?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  MICROSOFT_CLIENT_ID?: string;
  MICROSOFT_CLIENT_SECRET?: string;
  APPLE_SERVICES_ID?: string;
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
}
