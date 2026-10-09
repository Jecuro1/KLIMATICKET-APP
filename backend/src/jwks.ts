// Provider JWKS cache (docs/CLOUDFLARE_BACKEND.md §2.5): module-level map per URL, TTL 6 h, at most one refetch per
// 60 s per URL for an unknown kid. The Cache API is not used (it does nothing on *.workers.dev).
import { importRsaJwk } from "./crypto";

const TTL_MS = 6 * 60 * 60 * 1000;
const REFETCH_MIN_INTERVAL_MS = 60 * 1000;
const FETCH_TIMEOUT_MS = 10_000;

interface Entry {
  keys: Map<string, { n: string; e: string }>;
  imported: Map<string, Promise<CryptoKey>>;
  fetchedAt: number;
  lastAttemptAt: number;
}

export class JwksUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JwksUnavailableError";
  }
}

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export class JwksCache {
  private readonly entries = new Map<string, Entry>();
  private readonly inflight = new Map<string, Promise<Entry>>();

  /** RSA verification key for `kid`, or null when the provider does not publish such a key. */
  async key(url: string, kid: string, fetchFn: FetchFn, now: number): Promise<CryptoKey | null> {
    let entry = this.entries.get(url);
    const canRetry = (e: Entry) => now - e.lastAttemptAt >= REFETCH_MIN_INTERVAL_MS || now < e.lastAttemptAt;
    if (!entry) {
      entry = await this.refresh(url, fetchFn, now, undefined);
    } else if ((now - entry.fetchedAt > TTL_MS || now < entry.fetchedAt || !entry.keys.has(kid)) && canRetry(entry)) {
      // Expired or unknown kid: refetch (at most once per 60 s). If the provider is down, keep using the stale key
      // list (keys rotate slowly) rather than failing every sign-in.
      const stale: Entry = entry;
      entry = await this.refresh(url, fetchFn, now, stale).catch(() => stale);
    }
    const current: Entry = entry;
    const jwk = current.keys.get(kid);
    if (!jwk) return null;
    let imported = current.imported.get(kid);
    if (!imported) {
      imported = importRsaJwk(jwk);
      current.imported.set(kid, imported);
      imported.catch(() => current.imported.delete(kid));
    }
    return imported;
  }

  private refresh(url: string, fetchFn: FetchFn, now: number, stale: Entry | undefined): Promise<Entry> {
    const running = this.inflight.get(url);
    if (running) return running;
    if (stale) stale.lastAttemptAt = now;
    const p = this.load(url, fetchFn, now)
      .then((entry) => {
        this.entries.set(url, entry);
        return entry;
      })
      .finally(() => this.inflight.delete(url));
    this.inflight.set(url, p);
    return p;
  }

  private async load(url: string, fetchFn: FetchFn, now: number): Promise<Entry> {
    let res: Response;
    try {
      res = await fetchFn(url, { headers: { Accept: "application/json" }, signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
    } catch {
      throw new JwksUnavailableError("JWKS fetch failed");
    }
    if (!res.ok) throw new JwksUnavailableError(`JWKS HTTP ${res.status}`);
    let body: unknown;
    try {
      body = await res.json();
    } catch {
      throw new JwksUnavailableError("JWKS is not JSON");
    }
    const list = (body as { keys?: unknown })?.keys;
    if (!Array.isArray(list)) throw new JwksUnavailableError("JWKS has no keys");
    const keys = new Map<string, { n: string; e: string }>();
    for (const k of list) {
      if (!k || typeof k !== "object") continue;
      const { kty, kid, n, e, use, alg } = k as Record<string, unknown>;
      if (kty !== "RSA" || typeof kid !== "string" || typeof n !== "string" || typeof e !== "string") continue;
      if (use !== undefined && use !== "sig") continue;
      if (alg !== undefined && alg !== "RS256") continue;
      keys.set(kid, { n, e });
    }
    return { keys, imported: new Map(), fetchedAt: now, lastAttemptAt: now };
  }
}
