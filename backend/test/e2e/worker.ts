// End-to-end entry point – NEVER deployed (CI deploys src/index.ts from the rendered wrangler.toml).
// The real Worker (`handle` with the production deps), except that outbound calls to Google, Microsoft and Apple go to
// the local fake OIDC server of Packages/KlimaCloud/E2E/fake-oidc.mjs (`E2E_FAKE_OIDC_URL`, set by run-e2e.sh), so a
// complete browser sign-in – start → provider → callback → app code → token – runs against `wrangler dev` + local D1.
// Any other outbound host fails loudly, so the e2e run can never talk to a real provider.
import { handle } from "../../src/app";
import { runCleanup } from "../../src/cron";
import { defaultDeps, type Deps } from "../../src/deps";
import type { Env } from "../../src/env";

interface E2EEnv extends Env {
  E2E_FAKE_OIDC_URL?: string;
}

const PROVIDER_HOSTS: Record<string, string> = {
  "accounts.google.com": "google",
  "oauth2.googleapis.com": "google",
  "www.googleapis.com": "google",
  "login.microsoftonline.com": "microsoft",
  "appleid.apple.com": "apple",
};

let cached: { fake: string; deps: Deps } | null = null;

function e2eDeps(env: E2EEnv): Deps {
  const fake = (env.E2E_FAKE_OIDC_URL ?? "").replace(/\/+$/, "");
  if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(fake)) throw new Error("E2E_FAKE_OIDC_URL must be http://127.0.0.1:<port>");
  if (cached?.fake === fake) return cached.deps;
  const base = defaultDeps();
  const deps: Deps = {
    ...base,
    fetch: (input, init) => {
      const original = new Request(input, init);
      const url = new URL(original.url);
      const provider = url.protocol === "https:" ? PROVIDER_HOSTS[url.hostname] : undefined;
      if (!provider) return Promise.reject(new TypeError(`e2e: unexpected outbound request to ${url.origin}`));
      return fetch(new Request(`${fake}/${provider}${url.pathname}${url.search}`, original));
    },
  };
  cached = { fake, deps };
  return deps;
}

export default {
  fetch(request: Request, env: E2EEnv, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, ctx, e2eDeps(env));
  },
  async scheduled(_controller: ScheduledController, env: E2EEnv): Promise<void> {
    await runCleanup(env, e2eDeps(env));
  },
} satisfies ExportedHandler<E2EEnv>;
