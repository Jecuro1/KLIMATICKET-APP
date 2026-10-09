// Fake OIDC providers (Google, Microsoft, Apple) for the full-flow e2e tests (run-e2e.sh, FullFlowE2ETests.swift).
// It behaves like the real providers towards the Worker and checks what the Worker sends:
//   GET  /{p}/<authorize path>  the "browser" step: validates client_id, redirect_uri, scope, state, nonce, PKCE, then
//                               simulates the user's login (login_sub / login_email / login_name / login_deny) and
//                               answers like the provider: 302 to the callback (Google, Microsoft) or – Apple's
//                               form_post – 200 JSON {action, fields} that the test POSTs as the browser would.
//   POST /{p}/<token path>      code exchange: client_secret (Apple: ES256 JWT verified with the public key), PKCE
//                               verifier, redirect_uri, single-use codes → id_token (RS256, real JWKS), Apple refresh token
//   GET  /{p}/<jwks path>       the RSA public key
//   POST /apple/auth/revoke     records revocations (account deletion)
//   GET  /__calls               what happened (token exchanges, revocations, rejections) for the test's assertions
// Usage: node fake-oidc.mjs <port> <config.json>   config: {worker, google:{client_id,client_secret},
//        microsoft:{client_id,client_secret,tenant}, apple:{services_id,team_id,key_id,public_key_pem}}
import { createHash, createPublicKey, generateKeyPairSync, randomBytes, sign, verify } from "node:crypto";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";

const [portArg, configPath] = process.argv.slice(2);
const config = JSON.parse(readFileSync(configPath, "utf8"));
const b64url = (buf) => Buffer.from(buf).toString("base64url");
const sha256b64url = (s) => b64url(createHash("sha256").update(s).digest());

const PATHS = {
  google: { authorize: "/o/oauth2/v2/auth", token: "/token", jwks: "/oauth2/v3/certs" },
  microsoft: { authorize: "/common/oauth2/v2.0/authorize", token: "/common/oauth2/v2.0/token", jwks: "/common/discovery/v2.0/keys" },
  apple: { authorize: "/auth/authorize", token: "/auth/token", jwks: "/auth/keys" },
};
const SCOPES = { google: "openid email profile", microsoft: "openid email profile", apple: "name email" };

const keys = {};
for (const p of Object.keys(PATHS)) {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  keys[p] = { kid: `fake-${p}-${b64url(randomBytes(4))}`, publicKey, privateKey };
}
const applePublicKey = createPublicKey(config.apple.public_key_pem);

const codes = new Map(); // code → pending login
const calls = []; // {kind, provider, …} – no secrets
const appleRefreshTokens = new Map(); // refresh token → sub

function clientId(p) {
  return p === "apple" ? config.apple.services_id : config[p].client_id;
}

function callbackUrl(p) {
  return `${config.worker}/v1/auth/${p}/callback`;
}

function jwt(p, claims) {
  const header = { alg: "RS256", kid: keys[p].kid, typ: "JWT" };
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  return `${input}.${b64url(sign("sha256", Buffer.from(input), keys[p].privateKey))}`;
}

/** Apple checks the ES256 client secret like this (alg, kid, iss = team, sub = client id, aud, lifetime, signature). */
function verifyAppleSecret(secret, expectedSub) {
  const parts = String(secret).split(".");
  if (parts.length !== 3) return "malformed";
  let header, claims;
  try {
    header = JSON.parse(Buffer.from(parts[0], "base64url"));
    claims = JSON.parse(Buffer.from(parts[1], "base64url"));
  } catch {
    return "malformed";
  }
  if (header.alg !== "ES256" || header.kid !== config.apple.key_id) return "header";
  const now = Math.floor(Date.now() / 1000);
  if (claims.iss !== config.apple.team_id || claims.sub !== expectedSub || claims.aud !== "https://appleid.apple.com") return "claims";
  if (!(claims.exp > now) || claims.exp - claims.iat > 15_777_000) return "times";
  const ok = verify("sha256", Buffer.from(`${parts[0]}.${parts[1]}`), { key: applePublicKey, dsaEncoding: "ieee-p1363" },
    Buffer.from(parts[2], "base64url"));
  return ok ? null : "signature";
}

function send(res, status, body, headers = {}) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  res.writeHead(status, { "Content-Type": typeof body === "string" ? "text/plain" : "application/json", ...headers });
  res.end(text);
}

function oauthError(res, status, error, provider, detail) {
  calls.push({ kind: "rejected", provider, error, detail });
  send(res, status, { error, error_description: detail });
}

function authorize(p, q, res) {
  const fail = (detail) => oauthError(res, 400, "invalid_request", p, detail);
  if (q.get("client_id") !== clientId(p)) return fail("client_id");
  if (q.get("redirect_uri") !== callbackUrl(p)) return fail(`redirect_uri ${q.get("redirect_uri")}`);
  if (q.get("response_type") !== "code") return fail("response_type");
  if (q.get("scope") !== SCOPES[p]) return fail("scope");
  const state = q.get("state");
  const nonce = q.get("nonce");
  if (!state || !nonce) return fail("state/nonce");
  let challenge = null;
  if (p === "apple") {
    if (q.get("response_mode") !== "form_post") return fail("response_mode");
  } else {
    challenge = q.get("code_challenge");
    if (!challenge || q.get("code_challenge_method") !== "S256") return fail("pkce");
    if (q.get("prompt") !== "select_account") return fail("prompt");
    if (p === "microsoft" && q.get("response_mode") !== "query") return fail("response_mode");
  }
  const sub = q.get("login_sub");
  if (!sub) return fail("login_sub (test parameter)");

  const back = new URL(callbackUrl(p));
  const fields = { state };
  if (q.get("login_deny") === "1") {
    fields.error = p === "apple" ? "user_cancelled_authorize" : "access_denied";
  } else {
    const code = b64url(randomBytes(24));
    const email = q.get("login_email") ?? `${sub}@${p}.fake`;
    codes.set(code, { provider: p, sub, nonce, challenge, email, name: q.get("login_name") ?? null, used: false });
    fields.code = code;
    if (p === "apple" && q.get("login_name")) {
      // Apple sends the name only on the first authorization, unsigned, as a form field.
      const [firstName, ...rest] = q.get("login_name").split(" ");
      fields.user = JSON.stringify({ name: { firstName, lastName: rest.join(" ") }, email });
    }
  }
  calls.push({ kind: "authorize", provider: p, sub, denied: !!fields.error });
  if (p === "apple") return send(res, 200, { action: back.toString(), method: "POST", fields });
  for (const [k, v] of Object.entries(fields)) back.searchParams.set(k, v);
  res.writeHead(302, { Location: back.toString() });
  res.end();
}

function token(p, form, res) {
  const fail = (error, detail, status = 400) => oauthError(res, status, error, p, detail);
  if (form.get("grant_type") !== "authorization_code") return fail("unsupported_grant_type", form.get("grant_type"));
  if (form.get("client_id") !== clientId(p)) return fail("invalid_client", "client_id", 401);
  if (p === "apple") {
    const problem = verifyAppleSecret(form.get("client_secret"), clientId(p));
    if (problem) return fail("invalid_client", `client_secret ${problem}`, 401);
  } else if (form.get("client_secret") !== config[p].client_secret) {
    return fail("invalid_client", "client_secret", 401);
  }
  if (form.get("redirect_uri") !== callbackUrl(p)) return fail("invalid_grant", "redirect_uri");
  if (p === "microsoft" && form.get("scope") !== SCOPES.microsoft) return fail("invalid_request", "scope");
  const pending = codes.get(form.get("code") ?? "");
  if (!pending || pending.provider !== p) return fail("invalid_grant", "unknown code");
  if (pending.used) return fail("invalid_grant", "code already used");
  pending.used = true;
  if (pending.challenge !== null) {
    const verifier = form.get("code_verifier") ?? "";
    if (sha256b64url(verifier) !== pending.challenge) return fail("invalid_grant", "pkce");
  } else if (form.has("code_verifier")) {
    return fail("invalid_request", "unexpected code_verifier");
  }
  const now = Math.floor(Date.now() / 1000);
  const aud = clientId(p);
  const base = { sub: pending.sub, aud, nonce: pending.nonce, iat: now, exp: now + 3600 };
  let claims;
  if (p === "google") {
    claims = { ...base, iss: "https://accounts.google.com", azp: aud, email: pending.email, email_verified: true,
      name: pending.name ?? "Grete Google", picture: "https://lh3.googleusercontent.test/a/photo" };
  } else if (p === "microsoft") {
    const tid = config.microsoft.tenant;
    claims = { ...base, iss: `https://login.microsoftonline.com/${tid}/v2.0`, tid, email: pending.email,
      preferred_username: pending.email, name: pending.name ?? "Mia Microsoft" };
  } else {
    claims = { ...base, iss: "https://appleid.apple.com", email: pending.email, email_verified: "true" };
  }
  const body = { access_token: b64url(randomBytes(16)), token_type: "Bearer", expires_in: 3600, id_token: jwt(p, claims) };
  if (p === "apple") {
    body.refresh_token = `apple-rt-${b64url(randomBytes(16))}`;
    appleRefreshTokens.set(body.refresh_token, pending.sub);
  }
  calls.push({ kind: "token", provider: p, sub: pending.sub });
  send(res, 200, body);
}

function revoke(form, res) {
  const clientIdValue = form.get("client_id");
  const problem = verifyAppleSecret(form.get("client_secret"), clientIdValue);
  if (problem) return oauthError(res, 401, "invalid_client", "apple", `revoke client_secret ${problem}`);
  const token = form.get("token") ?? "";
  calls.push({
    kind: "revoke",
    provider: "apple",
    client_id: clientIdValue,
    token_type_hint: form.get("token_type_hint"),
    sub: appleRefreshTokens.get(token) ?? null,
  });
  send(res, 200, "");
}

const server = createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    try {
      if (url.pathname === "/__calls") return send(res, 200, calls);
      const [, p, ...rest] = url.pathname.split("/");
      const path = `/${rest.join("/")}`;
      const paths = PATHS[p];
      if (!paths) return send(res, 404, { error: "not_found" });
      if (req.method === "GET" && path === paths.jwks) {
        const jwk = keys[p].publicKey.export({ format: "jwk" });
        return send(res, 200, { keys: [{ kty: "RSA", kid: keys[p].kid, use: "sig", alg: "RS256", n: jwk.n, e: jwk.e }] });
      }
      if (req.method === "GET" && path === paths.authorize) return authorize(p, url.searchParams, res);
      const form = new URLSearchParams(Buffer.concat(chunks).toString("utf8"));
      const formOk = (req.headers["content-type"] ?? "").startsWith("application/x-www-form-urlencoded");
      if (req.method === "POST" && path === paths.token) return formOk ? token(p, form, res) : oauthError(res, 400, "invalid_request", p, "content-type");
      if (req.method === "POST" && p === "apple" && path === "/auth/revoke") return revoke(form, res);
      send(res, 404, { error: "not_found" });
    } catch (err) {
      send(res, 500, { error: "fake_crashed", detail: String(err) });
    }
  });
});
server.listen(Number(portArg), "127.0.0.1", () => console.log(`fake-oidc listening on 127.0.0.1:${portArg}`));
