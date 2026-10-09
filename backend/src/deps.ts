// Injected dependencies (docs/CLOUDFLARE_BACKEND.md §7 WP-S): tests stub providers, time and randomness without
// global mocks by passing their own Deps to handle().
import { JwksCache } from "./jwks";

export interface Deps {
  /** Outbound HTTP (providers). */
  fetch: (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
  /** Milliseconds since the Unix epoch. */
  now: () => number;
  randomBytes: (n: number) => Uint8Array<ArrayBuffer>;
  randomUUID: () => string;
  jwks: JwksCache;
  /** Structured log line (Workers Logs). Callers never pass secrets or personal data. */
  log: (entry: Record<string, unknown>) => void;
}

/** The minimal part of ExecutionContext the Worker needs. */
export interface Ctx {
  waitUntil(promise: Promise<unknown>): void;
}

const sharedJwks = new JwksCache();

export function defaultDeps(): Deps {
  return {
    fetch: (input, init) => fetch(input, init),
    now: () => Date.now(),
    randomBytes: (n) => crypto.getRandomValues(new Uint8Array(n)),
    randomUUID: () => crypto.randomUUID(),
    jwks: sharedJwks,
    log: (entry) => console.log(JSON.stringify(entry)),
  };
}
