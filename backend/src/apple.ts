// Apple refresh-token sealing and revocation (docs/CLOUDFLARE_BACKEND.md §2.9).
import type { Env } from "./env";
import type { Deps } from "./deps";
import { seal, unseal } from "./crypto";
import type { Keys } from "./keys";
import { APPLE_REVOKE_URL, SPECS, appleClientSecret } from "./providers";

const TIMEOUT_MS = 10_000;

export interface SealedAppleToken {
  client_id: string;
  refresh_token: string;
}

export function sealAppleToken(keys: Keys, deps: Deps, token: SealedAppleToken): Promise<string> {
  return seal(keys.current.seal, JSON.stringify({ client_id: token.client_id, refresh_token: token.refresh_token }), deps.randomBytes(12));
}

export async function unsealAppleToken(keys: Keys, sealed: string): Promise<SealedAppleToken | null> {
  for (const set of [keys.current, keys.previous]) {
    if (!set) continue;
    const text = await unseal(set.seal, sealed);
    if (text === null) continue;
    try {
      const v = JSON.parse(text) as Partial<SealedAppleToken>;
      if (typeof v.client_id === "string" && typeof v.refresh_token === "string") {
        return { client_id: v.client_id, refresh_token: v.refresh_token };
      }
    } catch {
      // fall through
    }
  }
  return null;
}

/** Native sign-in: exchanges the authorization code (client_id = bundle id) for a refresh token. Best effort. */
export async function exchangeNativeCode(env: Env, deps: Deps, code: string): Promise<string | null> {
  const clientId = env.APPLE_BUNDLE_ID?.trim();
  if (!clientId) return null;
  const secret = await appleClientSecret(env, deps, clientId);
  if (!secret) return null;
  const res = await deps.fetch(SPECS.apple.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: new URLSearchParams({ grant_type: "authorization_code", code, client_id: clientId, client_secret: secret }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) return null;
  const body = (await res.json().catch(() => null)) as { refresh_token?: unknown } | null;
  return typeof body?.refresh_token === "string" && body.refresh_token.length > 0 ? body.refresh_token : null;
}

/** Revokes sealed Apple refresh tokens after an account deletion (App Store guideline 5.1.1(v)). Best effort. */
export async function revokeAppleTokens(env: Env, deps: Deps, keys: Keys, sealedTokens: string[]): Promise<void> {
  for (const sealed of sealedTokens) {
    try {
      const token = await unsealAppleToken(keys, sealed);
      if (!token) {
        deps.log({ event: "apple_revoke_skipped", reason: "unseal_failed" });
        continue;
      }
      const secret = await appleClientSecret(env, deps, token.client_id);
      if (!secret) {
        deps.log({ event: "apple_revoke_skipped", reason: "no_client_secret" });
        continue;
      }
      const res = await deps.fetch(APPLE_REVOKE_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: token.client_id,
          client_secret: secret,
          token: token.refresh_token,
          token_type_hint: "refresh_token",
        }),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      deps.log({ event: "apple_revoke", status: res.status });
    } catch (err) {
      deps.log({ event: "apple_revoke_failed", error: err instanceof Error ? err.name : "unknown" });
    }
  }
}
