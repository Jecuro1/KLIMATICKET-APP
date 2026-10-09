// Browser flow app → Worker → provider → Worker → app (docs/CLOUDFLARE_BACKEND.md §2.3).
import type { Env } from "../env";
import type { Ctx, Deps } from "../deps";
import { findOrCreateUser } from "../accounts";
import { sealAppleToken } from "../apple";
import { sha256Base64url } from "../crypto";
import { MAX_BODY_BYTES, clientIp, htmlPage, isPlainObject, mediaType, readText, redirect, sanitizeText, type RequestInfo } from "../http";
import { JwksUnavailableError } from "../jwks";
import { loadKeys } from "../keys";
import { IdTokenError, verifyIdToken } from "../oidc";
import { SPECS, isWebEnabled, webClientId, webClientSecret, type ProviderName } from "../providers";
import { hit } from "../ratelimit";
import { TOKEN_RE, hashToken, randomToken } from "../sessions";

const STATE_RE = /^[A-Za-z0-9._~-]{16,256}$/;
const CHALLENGE_RE = /^[A-Za-z0-9_-]{43}$/;
const FLOW_TTL_MS = 10 * 60_000;
const CODE_TTL_MS = 120_000;
const PROVIDER_TIMEOUT_MS = 10_000;

const EXPIRED_TEXT = "Die Anmeldung ist abgelaufen. Bitte starte sie in der App erneut.";
const INVALID_START_TEXT = "Ungültige Anmeldeanfrage. Bitte starte die Anmeldung in der App erneut.";

export function appRedirectUris(env: Env): string[] {
  return (env.APP_REDIRECT_URIS ?? "klimabilanz://auth-callback")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function publicBaseUrl(env: Env, request: Request): string {
  const configured = (env.PUBLIC_BASE_URL ?? "").trim().replace(/\/+$/, "");
  return configured.length > 0 ? configured : new URL(request.url).origin;
}

export function providerCallbackUrl(env: Env, request: Request, provider: ProviderName): string {
  return `${publicBaseUrl(env, request)}/v1/auth/${provider}/callback`;
}

/** URLSearchParams with %20 instead of "+" for spaces (some providers do not decode "+" in queries). */
function query(params: Record<string, string>): string {
  return new URLSearchParams(params).toString().replace(/\+/g, "%20");
}

function appUrl(redirectUri: string, params: Record<string, string>): string {
  return `${redirectUri}${redirectUri.includes("?") ? "&" : "?"}${query(params)}`;
}

// ---------------------------------------------------------------------------------------------------------------
// GET /v1/auth/{provider}/start
// ---------------------------------------------------------------------------------------------------------------

export async function startFlow(request: Request, env: Env, deps: Deps, info: RequestInfo, provider: ProviderName): Promise<Response> {
  const q = new URL(request.url).searchParams;
  const redirectUri = q.get("redirect_uri");
  const state = q.get("state");
  if (redirectUri === null || !appRedirectUris(env).includes(redirectUri) || state === null || !STATE_RE.test(state)) {
    return htmlPage(info, 400, INVALID_START_TEXT, { errorCode: "invalid_request" });
  }
  const fail = (code: string, description: string, headers: Record<string, string> = {}): Response => {
    info.errorCode = code;
    const res = redirect(info, appUrl(redirectUri, { error: code, error_description: description, state }));
    for (const [k, v] of Object.entries(headers)) res.headers.set(k, v);
    return res;
  };

  const keys = await loadKeys(env);
  if (!keys) return fail("server_error", "The server is not configured yet.");
  const rate = await hit(env.DB, keys, deps, "auth_start", clientIp(request));
  if (!rate.allowed) return fail("rate_limited", "Too many sign-in attempts.", { "Retry-After": String(rate.retryAfter) });

  const challenge = q.get("code_challenge");
  if (challenge === null || !CHALLENGE_RE.test(challenge) || q.get("code_challenge_method") !== "S256") {
    return fail("invalid_request", "code_challenge (S256) is required.");
  }
  if (!(await isWebEnabled(env, deps, provider))) return fail("provider_disabled", `Sign-in with ${provider} is not configured.`);

  const spec = SPECS[provider];
  const flowId = randomToken(deps);
  const nonce = randomToken(deps);
  const providerVerifier = spec.pkce ? randomToken(deps) : null;
  const now = deps.now();
  try {
    await env.DB.prepare(
      `INSERT INTO auth_flows (id, provider, nonce, provider_code_verifier, app_code_challenge, app_state, app_redirect_uri, created_at, expires_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)`,
    )
      .bind(flowId, provider, nonce, providerVerifier, challenge, state, redirectUri, now, now + FLOW_TTL_MS)
      .run();
  } catch (err) {
    deps.log({ event: "auth_flow_insert_failed", request_id: info.requestId, error: err instanceof Error ? err.name : "unknown" });
    return fail("server_error", "Please try again.");
  }

  const params: Record<string, string> = {
    client_id: webClientId(env, provider),
    redirect_uri: providerCallbackUrl(env, request, provider),
    response_type: "code",
    scope: spec.scope,
    state: flowId,
    nonce,
    ...spec.extraAuthorizeParams,
  };
  if (providerVerifier) {
    params.code_challenge = await sha256Base64url(providerVerifier);
    params.code_challenge_method = "S256";
  }
  return redirect(info, `${spec.authorizeUrl}?${query(params)}`);
}

// ---------------------------------------------------------------------------------------------------------------
// GET|POST /v1/auth/{provider}/callback
// ---------------------------------------------------------------------------------------------------------------

interface FlowRow {
  id: string;
  provider: string;
  nonce: string;
  provider_code_verifier: string | null;
  app_code_challenge: string;
  app_state: string;
  app_redirect_uri: string;
  expires_at: number;
}

const APPLE_ORIGINS = new Set(["https://appleid.apple.com", "null"]);

function appleName(raw: string | null): string | null {
  if (!raw || raw.length > 4096) return null;
  try {
    const v: unknown = JSON.parse(raw);
    if (!isPlainObject(v) || !isPlainObject(v.name)) return null;
    const parts = [sanitizeText(v.name.firstName, 100), sanitizeText(v.name.lastName, 100)].filter((p): p is string => p !== null);
    return sanitizeText(parts.join(" "), 100);
  } catch {
    return null;
  }
}

export async function callbackFlow(
  request: Request,
  env: Env,
  ctx: Ctx,
  deps: Deps,
  info: RequestInfo,
  provider: ProviderName,
): Promise<Response> {
  void ctx;
  const spec = SPECS[provider];
  if (spec.callbackMethod === "POST") {
    const origin = request.headers.get("Origin");
    if (origin !== null && !APPLE_ORIGINS.has(origin)) {
      return htmlPage(info, 403, INVALID_START_TEXT, { errorCode: "origin_not_allowed" });
    }
  }
  const keys = await loadKeys(env);
  if (!keys) return htmlPage(info, 503, "Der Server ist noch nicht fertig eingerichtet.", { errorCode: "server_not_configured" });
  const rate = await hit(env.DB, keys, deps, "auth_callback", clientIp(request));

  let params: URLSearchParams;
  if (spec.callbackMethod === "POST") {
    if (mediaType(request) !== "application/x-www-form-urlencoded") {
      return htmlPage(info, 415, INVALID_START_TEXT, { errorCode: "unsupported_media_type" });
    }
    params = new URLSearchParams(await readText(request, MAX_BODY_BYTES));
  } else {
    params = new URL(request.url).searchParams;
  }

  // 1. Consume the flow exactly once.
  const state = params.get("state");
  const now = deps.now();
  let flow: FlowRow | null = null;
  try {
    flow =
      state !== null && TOKEN_RE.test(state)
        ? await env.DB.prepare("DELETE FROM auth_flows WHERE id = ?1 RETURNING *").bind(state).first<FlowRow>()
        : null;
  } catch (err) {
    deps.log({ event: "auth_flow_consume_failed", request_id: info.requestId, error: err instanceof Error ? err.name : "unknown" });
    return htmlPage(info, 500, "Etwas ist schiefgelaufen. Bitte starte die Anmeldung in der App erneut.", { errorCode: "server_error" });
  }
  if (!flow || flow.expires_at <= now || flow.provider !== provider) {
    if (!rate.allowed) {
      const res = htmlPage(info, 429, "Zu viele Versuche. Bitte warte kurz und versuch es dann noch einmal.", { errorCode: "rate_limited" });
      res.headers.set("Retry-After", String(rate.retryAfter));
      return res;
    }
    return htmlPage(info, 400, EXPIRED_TEXT, { errorCode: "flow_expired" });
  }
  const active: FlowRow = flow;

  const status = spec.callbackMethod === "POST" ? 303 : 302;
  const toApp = (extra: Record<string, string>, ok: boolean): Response => {
    const location = appUrl(active.app_redirect_uri, { ...extra, state: active.app_state });
    const text = ok ? "Anmeldung erfolgreich – zurück zur App." : "Die Anmeldung hat nicht geklappt – zurück zur App.";
    return htmlPage(info, status, text, { location, link: { href: location, label: "Zurück zur App" } });
  };
  const fail = (code: string, description?: string | null): Response => {
    info.errorCode = code;
    return toApp(description ? { error: code, error_description: description } : { error: code }, false);
  };

  if (!rate.allowed) return fail("rate_limited", "Too many sign-in attempts.");

  // 2. Provider-side errors / cancellation.
  const providerError = params.get("error");
  if (providerError !== null) {
    if (providerError === "access_denied" || providerError === "user_cancelled_authorize") return fail("access_denied");
    return fail("provider_error", sanitizeText(params.get("error_description") ?? providerError, 200));
  }
  if (!(await isWebEnabled(env, deps, provider))) return fail("provider_disabled", `Sign-in with ${provider} is not configured.`);
  const code = params.get("code");
  if (!code || code.length > 4096) return fail("provider_error", "The provider sent no authorization code.");

  try {
    // 3. Exchange the provider code (the id_token of Apple's form post is ignored).
    const clientId = webClientId(env, provider);
    const clientSecret = await webClientSecret(env, deps, provider);
    if (!clientSecret) return fail("provider_disabled", `Sign-in with ${provider} is not configured.`);
    const form = new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: providerCallbackUrl(env, request, provider),
      client_id: clientId,
      client_secret: clientSecret,
    });
    if (active.provider_code_verifier) form.set("code_verifier", active.provider_code_verifier);
    if (provider === "microsoft") form.set("scope", spec.scope);
    let tokenBody: Record<string, unknown>;
    try {
      const res = await deps.fetch(spec.tokenUrl, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
        body: form,
        signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
      });
      if (!res.ok) {
        deps.log({ event: "provider_token_failed", request_id: info.requestId, provider, status: res.status });
        return fail("provider_error", "The provider rejected the sign-in.");
      }
      const body: unknown = await res.json();
      if (!isPlainObject(body)) return fail("provider_error", "Unexpected provider response.");
      tokenBody = body;
    } catch (err) {
      deps.log({ event: "provider_token_failed", request_id: info.requestId, provider, error: err instanceof Error ? err.name : "unknown" });
      return fail("provider_error", "The provider did not answer.");
    }
    const idToken = tokenBody.id_token;
    if (typeof idToken !== "string") return fail("provider_error", "The provider sent no id_token.");

    // 4. Verify the id_token.
    let identity;
    try {
      identity = await verifyIdToken(idToken, { provider, audience: clientId, expectedNonce: active.nonce }, deps);
    } catch (err) {
      if (err instanceof JwksUnavailableError) return fail("provider_error", "Provider keys are unavailable.");
      if (err instanceof IdTokenError) {
        deps.log({ event: "id_token_rejected", request_id: info.requestId, provider, reason: err.reason });
        return fail("invalid_id_token");
      }
      throw err;
    }

    // 5. Find or create the user; Apple: seal the refresh token for revocation on account deletion.
    const name = provider === "apple" ? appleName(params.get("user")) : identity.name;
    const appleRefresh = provider === "apple" && typeof tokenBody.refresh_token === "string" ? tokenBody.refresh_token : null;
    const sealed = appleRefresh ? await sealAppleToken(keys, deps, { client_id: clientId, refresh_token: appleRefresh }) : null;
    const userId = await findOrCreateUser(env, deps, {
      provider,
      subject: identity.subject,
      email: identity.email,
      emailVerified: identity.emailVerified,
      name,
      avatarUrl: identity.avatarUrl,
      sealedRefreshToken: sealed,
    });

    // 6. One-time app code (stored hashed, 120 s, bound to the app's PKCE challenge and redirect URI).
    const appCode = randomToken(deps);
    await env.DB.prepare(
      `INSERT INTO auth_codes (code_hash, user_id, provider, subject, code_challenge, redirect_uri, created_at, expires_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
    )
      .bind(await hashToken(appCode), userId, provider, identity.subject, active.app_code_challenge, active.app_redirect_uri, now, now + CODE_TTL_MS)
      .run();

    // 7. Back to the app.
    return toApp({ code: appCode }, true);
  } catch (err) {
    deps.log({ event: "callback_failed", request_id: info.requestId, provider, error: err instanceof Error ? err.name : "unknown" });
    return fail("server_error", "Please try again.");
  }
}
