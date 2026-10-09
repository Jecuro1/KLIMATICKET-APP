// Test helpers: injected deps (fake clock + fake network), fake OIDC providers with real RSA JWKS, a fake Apple token
// endpoint that verifies the ES256 client secret, and full sign-in flows through the Worker.
import { env } from "cloudflare:workers";
import { expect } from "vitest";
import { handle } from "../src/app";
import { base64Decode, base64urlDecode, base64urlEncode, decodeJwt, sha256Base64url, sha256Hex, utf8 } from "../src/crypto";
import type { Ctx, Deps } from "../src/deps";
import type { Env } from "../src/env";
import { JwksCache } from "../src/jwks";
import { loadKeys } from "../src/keys";
import { SPECS, type ProviderName } from "../src/providers";
import { hashToken, newSessionIds, sessionStatements, signAccessToken, type TokenResponse } from "../src/sessions";

export const BASE = "https://api.test";
export const APP_REDIRECT = "klimabilanz://auth-callback";
/** 2026-10-09T12:00:00Z */
export const T0 = Date.UTC(2026, 9, 9, 12, 0, 0);

// ---------------------------------------------------------------------------------------------------------------
// Clock, ids, deps
// ---------------------------------------------------------------------------------------------------------------

export class Clock {
  constructor(public t = T0) {}
  now = (): number => this.t;
  advance(ms: number): void {
    this.t += ms;
  }
}

let counter = 0;
export function unique(prefix = "u"): string {
  counter++;
  return `${prefix}${counter}${base64urlEncode(crypto.getRandomValues(new Uint8Array(6)))}`;
}

export function uniqueIp(): string {
  counter++;
  return `2001:db8::${counter.toString(16)}:${Math.floor(Math.random() * 0xffff).toString(16)}`;
}

export function uuid(): string {
  return crypto.randomUUID();
}

export type Handler = (req: Request) => Response | Promise<Response>;

/** Body as text without workerd's ".text() on a non-text body" warning for form posts. */
export async function bodyText(r: Request | Response): Promise<string> {
  return new TextDecoder().decode(await r.arrayBuffer());
}

export interface RecordedCall {
  url: string;
  method: string;
  body: string;
}

export class FakeNet {
  readonly handlers = new Map<string, Handler>();
  readonly calls: RecordedCall[] = [];
  on(url: string, h: Handler): this {
    this.handlers.set(url, h);
    return this;
  }
  fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    const body = req.method === "GET" ? "" : await bodyText(req.clone());
    this.calls.push({ url: req.url, method: req.method, body });
    const h = this.handlers.get(url.origin + url.pathname);
    if (!h) throw new TypeError(`network error: no fake for ${url.origin}${url.pathname}`);
    return h(req);
  };
  callsTo(prefix: string): RecordedCall[] {
    return this.calls.filter((c) => c.url.startsWith(prefix));
  }
}

export interface TestDeps extends Deps {
  logs: Record<string, unknown>[];
  clock: Clock;
  net: FakeNet;
}

export function makeDeps(net = new FakeNet(), clock = new Clock()): TestDeps {
  const logs: Record<string, unknown>[] = [];
  return {
    fetch: net.fetch,
    now: clock.now,
    randomBytes: (n) => crypto.getRandomValues(new Uint8Array(n)),
    randomUUID: () => crypto.randomUUID(),
    jwks: new JwksCache(),
    log: (e) => logs.push(e),
    logs,
    clock,
    net,
  };
}

export class TestCtx implements Ctx {
  promises: Promise<unknown>[] = [];
  waitUntil(p: Promise<unknown>): void {
    this.promises.push(p);
  }
  async drain(): Promise<void> {
    const ps = this.promises;
    this.promises = [];
    await Promise.all(ps);
  }
}

export function testEnv(over: Partial<Env> = {}): Env {
  return { ...(env as unknown as Env), ...over };
}

/** Calls the Worker handler. Requests without CF-Connecting-IP get a unique one (rate limits are per IP). */
export function call(deps: TestDeps, req: Request, over: Partial<Env> = {}, ctx: Ctx = new TestCtx()): Promise<Response> {
  if (!req.headers.has("CF-Connecting-IP")) req.headers.set("CF-Connecting-IP", uniqueIp());
  return handle(req, testEnv(over), ctx, deps);
}

export function get(path: string, headers: Record<string, string> = {}): Request {
  return new Request(`${BASE}${path}`, { headers });
}

export function postJson(path: string, body: unknown, headers: Record<string, string> = {}, method = "POST"): Request {
  return new Request(`${BASE}${path}`, {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

export function postForm(path: string, fields: Record<string, string>, headers: Record<string, string> = {}): Request {
  return new Request(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", ...headers },
    body: new URLSearchParams(fields).toString(),
  });
}

export function bearer(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

export async function expectError(res: Response, status: number, code: string): Promise<Record<string, unknown>> {
  const body = (await res.json()) as Record<string, unknown>;
  expect({ status: res.status, error: body.error }).toEqual({ status, error: code });
  expect(res.headers.get("X-KB-API")).toBe("1");
  expect(typeof body.request_id).toBe("string");
  return body;
}

// ---------------------------------------------------------------------------------------------------------------
// Fake identity providers
// ---------------------------------------------------------------------------------------------------------------

function jsonSegment(v: unknown): string {
  return base64urlEncode(utf8(JSON.stringify(v)));
}

export class FakeIdp {
  constructor(
    readonly kid: string,
    readonly keys: CryptoKeyPair,
    readonly jwk: JsonWebKey,
  ) {}

  static async create(kid = unique("kid")): Promise<FakeIdp> {
    const keys = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const jwk = (await crypto.subtle.exportKey("jwk", keys.publicKey)) as JsonWebKey;
    return new FakeIdp(kid, keys, jwk);
  }

  jwks(): { keys: Record<string, unknown>[] } {
    return { keys: [{ kty: "RSA", kid: this.kid, use: "sig", alg: "RS256", n: this.jwk.n, e: this.jwk.e }] };
  }

  async sign(claims: Record<string, unknown>, header: Record<string, unknown> = {}): Promise<string> {
    const input = `${jsonSegment({ alg: "RS256", kid: this.kid, typ: "JWT", ...header })}.${jsonSegment(claims)}`;
    const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", this.keys.privateKey, utf8(input));
    return `${input}.${base64urlEncode(sig)}`;
  }
}

/** Mutations a test can apply to the id_token a fake provider returns. */
export interface TokenMutation {
  claims?: Record<string, unknown>;
  header?: Record<string, unknown>;
  signWith?: FakeIdp;
  /** Replace the whole id_token. */
  raw?: string;
  /** Token endpoint answers with this status (no id_token). */
  tokenStatus?: number;
  omitIdToken?: boolean;
}

interface PendingCode {
  provider: ProviderName;
  nonce: string;
  challenge: string | null;
  sub: string;
  mutation: TokenMutation;
  appleRefresh?: string;
}

export const MS_TENANT = "9188040d-6c67-4c5b-b112-36a304b66dad";

export interface ProviderSecrets {
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  MICROSOFT_CLIENT_ID: string;
  MICROSOFT_CLIENT_SECRET: string;
  APPLE_SERVICES_ID: string;
  APPLE_TEAM_ID: string;
  APPLE_KEY_ID: string;
  APPLE_PRIVATE_KEY: string;
  APPLE_BUNDLE_ID: string;
}

export function pem(der: ArrayBuffer): string {
  const b64 = base64urlEncode(der).replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "===".slice((b64.length + 3) % 4);
  const lines = padded.match(/.{1,64}/g) ?? [];
  return `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;
}

/** Verifies an Apple ES256 client secret the way Apple would. Returns the claims or throws. */
export async function verifyAppleClientSecret(
  world: ProviderWorld,
  secret: string,
  expectedSub: string,
): Promise<Record<string, unknown>> {
  const jwt = decodeJwt(secret);
  if (!jwt) throw new Error("client_secret malformed");
  if (jwt.header.alg !== "ES256" || jwt.header.kid !== world.secrets.APPLE_KEY_ID) throw new Error("client_secret header");
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, world.applePublicKey, jwt.signature, utf8(jwt.signingInput));
  if (!ok) throw new Error("client_secret signature");
  const c = jwt.payload;
  if (c.iss !== world.secrets.APPLE_TEAM_ID || c.aud !== "https://appleid.apple.com" || c.sub !== expectedSub) {
    throw new Error("client_secret claims");
  }
  if (typeof c.iat !== "number" || c.exp !== c.iat + 300) throw new Error("client_secret times");
  return c;
}

export class ProviderWorld {
  readonly pending = new Map<string, PendingCode>();
  readonly nativeCodes = new Map<string, string>();
  readonly revoked: { client_id: string; token: string }[] = [];

  private constructor(
    readonly deps: TestDeps,
    readonly google: FakeIdp,
    readonly microsoft: FakeIdp,
    readonly apple: FakeIdp,
    readonly applePublicKey: CryptoKey,
    readonly secrets: ProviderSecrets,
  ) {}

  static async create(): Promise<ProviderWorld> {
    const [google, microsoft, apple] = await Promise.all([FakeIdp.create(), FakeIdp.create(), FakeIdp.create()]);
    const ec = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const pkcs8 = (await crypto.subtle.exportKey("pkcs8", ec.privateKey)) as ArrayBuffer;
    const secrets: ProviderSecrets = {
      GOOGLE_CLIENT_ID: "test-google.apps.googleusercontent.com",
      GOOGLE_CLIENT_SECRET: "test-google-secret",
      MICROSOFT_CLIENT_ID: "6731de76-14a6-49ae-97bc-6eba6914391e",
      MICROSOFT_CLIENT_SECRET: "test-microsoft-secret",
      APPLE_SERVICES_ID: "com.knitelarlberg.klimabilanz.web",
      APPLE_TEAM_ID: "TEAM123456",
      APPLE_KEY_ID: "KEY1234567",
      APPLE_PRIVATE_KEY: pem(pkcs8),
      APPLE_BUNDLE_ID: "com.knitelarlberg.klimabilanz",
    };
    const world = new ProviderWorld(makeDeps(), google, microsoft, apple, ec.publicKey, secrets);
    world.install();
    return world;
  }

  /** A fresh deps object (clock, logs, JWKS cache) wired to this world's fake network. */
  freshDeps(): TestDeps {
    const d = makeDeps(this.deps.net, this.deps.clock);
    return d;
  }

  idp(p: ProviderName): FakeIdp {
    return this[p];
  }

  clientId(p: ProviderName): string {
    return p === "google" ? this.secrets.GOOGLE_CLIENT_ID : p === "microsoft" ? this.secrets.MICROSOFT_CLIENT_ID : this.secrets.APPLE_SERVICES_ID;
  }

  defaultClaims(p: ProviderName, sub: string, nonce: string, aud = this.clientId(p)): Record<string, unknown> {
    const now = Math.floor(this.deps.clock.now() / 1000);
    const base = { sub, aud, nonce, iat: now, exp: now + 3600 };
    switch (p) {
      case "google":
        return {
          ...base,
          iss: "https://accounts.google.com",
          azp: aud,
          email: `${sub}@gmail.test`,
          email_verified: true,
          name: "Grete Google",
          picture: "https://lh3.googleusercontent.test/a/photo",
        };
      case "microsoft":
        return {
          ...base,
          iss: `https://login.microsoftonline.com/${MS_TENANT}/v2.0`,
          tid: MS_TENANT,
          email: `${sub}@outlook.test`,
          preferred_username: `${sub}@outlook.test`,
          name: "Mia Microsoft",
        };
      case "apple":
        return { ...base, iss: "https://appleid.apple.com", email: `${sub}@privaterelay.appleid.test`, email_verified: "true" };
    }
  }

  async idToken(p: ProviderName, sub: string, nonce: string, m: TokenMutation = {}, aud?: string): Promise<string> {
    if (m.raw !== undefined) return m.raw;
    const signer = m.signWith ?? this.idp(p);
    return signer.sign({ ...this.defaultClaims(p, sub, nonce, aud), ...(m.claims ?? {}) }, m.header ?? {});
  }

  private install(): void {
    const net = this.deps.net;
    for (const p of ["google", "microsoft", "apple"] as const) {
      net.on(SPECS[p].jwksUrl, () => Response.json(this.idp(p).jwks()));
      net.on(SPECS[p].tokenUrl, (req) => this.tokenEndpoint(p, req));
    }
    net.on("https://appleid.apple.com/auth/revoke", async (req) => {
      const form = new URLSearchParams(await bodyText(req));
      await verifyAppleClientSecret(this, form.get("client_secret") ?? "", form.get("client_id") ?? "");
      if (form.get("token_type_hint") !== "refresh_token") return new Response("bad hint", { status: 400 });
      this.revoked.push({ client_id: form.get("client_id") ?? "", token: form.get("token") ?? "" });
      return new Response(null, { status: 200 });
    });
  }

  private async tokenEndpoint(p: ProviderName, req: Request): Promise<Response> {
    const form = new URLSearchParams(await bodyText(req));
    const err = (status: number, error: string) => Response.json({ error }, { status });
    if (form.get("grant_type") !== "authorization_code") return err(400, "unsupported_grant_type");
    const code = form.get("code") ?? "";

    if (p === "apple" && form.get("client_id") === this.secrets.APPLE_BUNDLE_ID) {
      // Native code exchange (no redirect_uri).
      try {
        await verifyAppleClientSecret(this, form.get("client_secret") ?? "", this.secrets.APPLE_BUNDLE_ID);
      } catch {
        return err(400, "invalid_client");
      }
      const refresh = this.nativeCodes.get(code);
      if (!refresh) return err(400, "invalid_grant");
      this.nativeCodes.delete(code);
      return Response.json({ access_token: "a", token_type: "Bearer", expires_in: 3600, refresh_token: refresh, id_token: "ignored" });
    }

    const entry = this.pending.get(code);
    if (!entry || entry.provider !== p) return err(400, "invalid_grant");
    this.pending.delete(code);
    if (form.get("client_id") !== this.clientId(p)) return err(401, "invalid_client");
    if (form.get("redirect_uri") !== `${BASE}/v1/auth/${p}/callback`) return err(400, "invalid_grant");
    if (p === "apple") {
      try {
        await verifyAppleClientSecret(this, form.get("client_secret") ?? "", this.secrets.APPLE_SERVICES_ID);
      } catch {
        return err(401, "invalid_client");
      }
      if (form.has("code_verifier")) return err(400, "invalid_request");
    } else {
      const expected = p === "google" ? this.secrets.GOOGLE_CLIENT_SECRET : this.secrets.MICROSOFT_CLIENT_SECRET;
      if (form.get("client_secret") !== expected) return err(401, "invalid_client");
      const verifier = form.get("code_verifier");
      if (!verifier || (await sha256Base64url(verifier)) !== entry.challenge) return err(400, "invalid_grant");
      if (p === "microsoft" && form.get("scope") !== "openid email profile") return err(400, "invalid_scope");
    }
    if (entry.mutation.tokenStatus) return err(entry.mutation.tokenStatus, "server_error");
    const body: Record<string, unknown> = { access_token: "provider-access", token_type: "Bearer", expires_in: 3600 };
    if (!entry.mutation.omitIdToken) body.id_token = await this.idToken(p, entry.sub, entry.nonce, entry.mutation);
    if (entry.appleRefresh) body.refresh_token = entry.appleRefresh;
    return Response.json(body);
  }

  /** Simulates the user signing in at the provider: returns the code the provider would send to the callback. */
  authorize(location: string, sub: string, mutation: TokenMutation = {}): { code: string; state: string; url: URL } {
    const url = new URL(location);
    const p = (["google", "microsoft", "apple"] as const).find((x) => location.startsWith(SPECS[x].authorizeUrl));
    if (!p) throw new Error(`not an authorize URL: ${location}`);
    const state = url.searchParams.get("state")!;
    const nonce = url.searchParams.get("nonce")!;
    const code = unique("pcode");
    this.pending.set(code, {
      provider: p,
      nonce,
      challenge: url.searchParams.get("code_challenge"),
      sub,
      mutation,
      appleRefresh: p === "apple" ? unique("apple-refresh-") : undefined,
    });
    return { code, state, url };
  }

  /** Env overrides with every provider configured. */
  env(over: Partial<Env> = {}): Partial<Env> {
    return { ...this.secrets, ...over };
  }
}

export interface AppPkce {
  verifier: string;
  challenge: string;
  state: string;
}

export async function appPkce(): Promise<AppPkce> {
  const verifier = base64urlEncode(crypto.getRandomValues(new Uint8Array(48)));
  return { verifier, challenge: await sha256Base64url(verifier), state: unique("appstate-") };
}

export function startUrl(p: ProviderName, pk: AppPkce, over: Record<string, string> = {}): string {
  const q = new URLSearchParams({
    code_challenge: pk.challenge,
    code_challenge_method: "S256",
    state: pk.state,
    redirect_uri: APP_REDIRECT,
    ...over,
  });
  return `/v1/auth/${p}/start?${q}`;
}

export function callbackRequest(p: ProviderName, fields: Record<string, string>, headers: Record<string, string> = {}): Request {
  if (p === "apple") return postForm(`/v1/auth/apple/callback`, fields, headers);
  return get(`/v1/auth/${p}/callback?${new URLSearchParams(fields)}`, headers);
}

export interface WebSignIn {
  tokens: TokenResponse;
  sub: string;
  appCode: string;
  pkce: AppPkce;
}

/** Runs start → provider → callback → token through the Worker. Returns the app's token response. */
export async function signInWeb(
  world: ProviderWorld,
  deps: TestDeps,
  p: ProviderName,
  opts: { sub?: string; mutation?: TokenMutation; appleUser?: string; envOver?: Partial<Env>; ip?: string } = {},
): Promise<WebSignIn> {
  const sub = opts.sub ?? unique("sub");
  const ip = opts.ip ?? uniqueIp();
  const envOver = world.env(opts.envOver);
  const pk = await appPkce();
  const start = await call(deps, get(startUrl(p, pk), { "CF-Connecting-IP": ip }), envOver);
  expect(start.status).toBe(302);
  const { code, state } = world.authorize(start.headers.get("Location")!, sub, opts.mutation);
  const fields: Record<string, string> = { code, state };
  if (opts.appleUser) fields.user = opts.appleUser;
  const cb = await call(deps, callbackRequest(p, fields, { "CF-Connecting-IP": ip }), envOver);
  expect(cb.status).toBe(p === "apple" ? 303 : 302);
  const appLocation = new URL(cb.headers.get("Location")!);
  expect(appLocation.searchParams.get("state")).toBe(pk.state);
  expect(appLocation.searchParams.get("error")).toBeNull();
  const appCode = appLocation.searchParams.get("code")!;
  const tokenRes = await call(
    deps,
    postForm("/v1/auth/token", { grant_type: "authorization_code", code: appCode, code_verifier: pk.verifier, redirect_uri: APP_REDIRECT }, {
      "CF-Connecting-IP": ip,
    }),
    envOver,
  );
  expect(tokenRes.status).toBe(200);
  return { tokens: (await tokenRes.json()) as TokenResponse, sub, appCode, pkce: pk };
}

/** Native Sign in with Apple through the Worker. */
export async function signInNative(
  world: ProviderWorld,
  deps: TestDeps,
  opts: { sub?: string; fullName?: string; authorizationCode?: string; mutation?: TokenMutation; ctx?: TestCtx } = {},
): Promise<{ res: Response; sub: string; rawNonce: string }> {
  const sub = opts.sub ?? unique("asub");
  const rawNonce = unique("raw-nonce-");
  const token = await world.idToken("apple", sub, await sha256Hex(rawNonce), opts.mutation, world.secrets.APPLE_BUNDLE_ID);
  const body: Record<string, unknown> = { identity_token: token, raw_nonce: rawNonce };
  if (opts.fullName) body.full_name = opts.fullName;
  if (opts.authorizationCode) body.authorization_code = opts.authorizationCode;
  const res = await call(deps, postJson("/v1/auth/apple/native", body, { "CF-Connecting-IP": uniqueIp() }), world.env(), opts.ctx);
  return { res, sub, rawNonce };
}

// ---------------------------------------------------------------------------------------------------------------
// Direct sessions (sync/account tests)
// ---------------------------------------------------------------------------------------------------------------

export interface DirectSession {
  userId: string;
  sessionId: string;
  accessToken: string;
  refreshToken: string;
  subject: string;
}

/** Creates user + identity + profile + session in D1 and signs an access token (bypasses the provider flow). */
export async function directSession(
  deps: TestDeps,
  opts: { userId?: string; provider?: ProviderName; subject?: string; email?: string; existingUser?: boolean } = {},
): Promise<DirectSession> {
  const db = (env as unknown as Env).DB;
  const userId = opts.userId ?? uuid();
  const provider = opts.provider ?? "google";
  const subject = opts.subject ?? unique("dsub");
  const now = deps.now();
  if (!opts.existingUser) {
    await db.batch([
      db.prepare("INSERT OR IGNORE INTO users (id, created_at, last_login_at) VALUES (?1, ?2, ?2)").bind(userId, now),
      db.prepare("INSERT OR IGNORE INTO profiles (user_id, display_name, avatar_url, created_at, updated_at) VALUES (?1, 'Direkt', NULL, ?2, ?2)").bind(
        userId,
        now,
      ),
    ]);
  }
  await db
    .prepare(
      "INSERT OR IGNORE INTO identities (provider, subject, user_id, email, email_verified, created_at, last_login_at) VALUES (?1, ?2, ?3, ?4, 1, ?5, ?5)",
    )
    .bind(provider, subject, userId, opts.email ?? `${subject}@example.test`, now)
    .run();
  const s = await newSessionIds(deps);
  await db.batch(sessionStatements(db, s, { userId, provider, subject }, now, "test"));
  const keys = (await loadKeys(testEnv()))!;
  return { userId, sessionId: s.sessionId, accessToken: await signAccessToken(keys, userId, s.sessionId, now), refreshToken: s.refreshToken, subject };
}

export function db(): D1Database {
  return (env as unknown as Env).DB;
}

export async function count(sql: string, ...args: unknown[]): Promise<number> {
  const row = await db().prepare(sql).bind(...args).first<{ n: number }>();
  return row?.n ?? 0;
}

export { base64Decode, base64urlDecode, hashToken };
